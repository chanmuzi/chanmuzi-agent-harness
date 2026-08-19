#!/bin/bash
# Shell functions for Claude Code and Codex CLI
# Sourced from .zshrc/.bashrc via CHANMUZI_AGENT_HARNESS_HOME

export ENABLE_EXPERIMENTAL_MCP_CLI='true'

# ── Claude Code ──

# Config directory for the work (Upstage) account. The personal account keeps
# the default ~/.claude so existing harness symlinks stay untouched.
# See docs/decisions/ for why accounts are separated this way.
CCU_CONFIG_DIR="${CCU_CONFIG_DIR:-$HOME/.claude-upstage}"

# Resolve the git root of the current directory (empty when not in a git repo).
# Claude sessions must start at the repo root: root CLAUDE.md is an @AGENTS.md
# adapter, and subdirectory starts may skip the parent import expansion.
# See docs/decisions/2026-07-agent-instruction-loading.md
_cc_launch_dir() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Launch Claude Code at the git root with permissions skipped
# (hooks provide the safety guardrails). Runs in a subshell so the caller's cwd
# and environment are untouched.
# $1: CLAUDE_CONFIG_DIR to use, or "" for the default (~/.claude).
# $2: mode — "agents" (background agents; cmux hooks disabled so teammates inherit
#     the lead's bypass) or "session" (plain interactive session; cmux hooks kept).
# Remaining args are passed through to claude.
# env -u TMUX: workaround for Claude Code 256-color downgrade in tmux
# See: https://github.com/anthropics/claude-code/issues/36785
_cc_run() {
  local config_dir="$1"
  local mode="$2"
  shift 2

  local launch_dir
  launch_dir="$(_cc_launch_dir)"
  if [ "$launch_dir" != "$PWD" ]; then
    echo "[harness] Claude 세션을 git 루트에서 시작합니다: $launch_dir" >&2
  fi

  (
    cd "$launch_dir" || return 1
    # unset (not just "skip") matters: a caller may already have
    # CLAUDE_CONFIG_DIR exported (e.g. a shell spawned from a ccu session),
    # and inheriting it would start the personal command on the work account.
    if [ -n "$config_dir" ]; then
      export CLAUDE_CONFIG_DIR="$config_dir"
    else
      unset CLAUDE_CONFIG_DIR
    fi
    # Resuming a session that lives in the other account's config dir (e.g.
    # `ccd --resume <ccu-session>`) would otherwise fail with "No conversation
    # found" — re-resolve from the transcript location, same as the claude()
    # wrapper below. The export stays inside this subshell.
    local session_id override
    session_id="$(_cc_resume_session_id "$@")"
    if [ -n "$session_id" ]; then
      override="$(_cc_find_session_config_dir "$session_id")"
      if [ -n "$override" ]; then
        echo "[harness] 세션 $session_id 은(는) $override 계정 소속 — CLAUDE_CONFIG_DIR 재지정" >&2
        export CLAUDE_CONFIG_DIR="$override"
      fi
    fi
    if [ "$mode" = "agents" ]; then
      # Background agents (`cc` / `ccu`): inside a cmux terminal the cmux `claude`
      # wrapper injects a PermissionRequest hook that routes permission requests to
      # cmux. The lead bypasses via --dangerously-skip-permissions, but daemon-
      # spawned teammates do not carry that flag, so their requests hit the hook and
      # prompt. Disabling the cmux hook injection makes the wrapper pass through to
      # the real claude, so teammates inherit the lead's bypass (matching plain
      # non-cmux / SSH behavior). The export lives only in this subshell, so it
      # never leaks to the caller's shell or other terminals, and the harness's own
      # settings.json hooks stay active.
      # See docs/decisions/2026-07-agent-teams-cmux-permission.md
      export CMUX_CLAUDE_HOOKS_DISABLED=1
      command env -u TMUX claude --dangerously-skip-permissions agents "$@"
    else
      # Plain interactive session: keep cmux hooks (notifications/status feed).
      command env -u TMUX claude --dangerously-skip-permissions "$@"
    fi
  )
}

# Personal account (default ~/.claude) — background agents (cmux hooks off).
cc() {
  _cc_run "" agents "$@"
}

# Work account (chanmuzi@upstage.ai) — background agents (cmux hooks off).
ccu() {
  _cc_run "$CCU_CONFIG_DIR" agents "$@"
}

# Personal account — plain interactive session (cmux hooks kept).
ccd() {
  _cc_run "" session "$@"
}

# Work account — plain interactive session (cmux hooks kept).
ccud() {
  _cc_run "$CCU_CONFIG_DIR" session "$@"
}

# Print the session ID from a `--resume <uuid>` / `--resume=<uuid>` / `-r <uuid>`
# argument, or nothing when the args carry no resumable session ID.
_cc_resume_session_id() {
  local arg session_id="" expect_id=0
  for arg in "$@"; do
    if [ "$expect_id" = 1 ]; then
      expect_id=0
      case "$arg" in
        ????????-????-????-????-????????????) session_id="$arg" ;;
      esac
    fi
    case "$arg" in
      --resume|-r) expect_id=1 ;;
      --resume=*) session_id="${arg#--resume=}" ;;
    esac
  done
  [ -n "$session_id" ] && printf '%s\n' "$session_id"
}

# Print the config dir that holds the transcript for session $1, but only when
# it differs from the effective config dir (empty output = no override needed).
# Search order: effective dir first, so a session present in both never flips.
_cc_find_session_config_dir() {
  local id="$1" effective_dir dir
  effective_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  for dir in "$effective_dir" "$HOME/.claude" "$CCU_CONFIG_DIR"; do
    [ -d "$dir/projects" ] || continue
    if [ -n "$(find "$dir/projects" -maxdepth 2 -name "$id.jsonl" -print 2>/dev/null | head -n 1)" ]; then
      [ "$dir" != "$effective_dir" ] && printf '%s\n' "$dir"
      return 0
    fi
  done
}

# Orca restores a pane after SSH reconnect by typing `claude --resume <id>`
# into a fresh shell, which drops the CLAUDE_CONFIG_DIR the ccu/ccud subshell
# had exported — resume then searches the wrong account and fails with
# "No conversation found". Re-resolve the account from the transcript location.
# Pass-through in every other case; the override env applies to this single
# invocation only and never leaks into the caller's shell.
claude() {
  local session_id
  session_id="$(_cc_resume_session_id "$@")"
  if [ -n "$session_id" ]; then
    local override
    override="$(_cc_find_session_config_dir "$session_id")"
    if [ -n "$override" ]; then
      echo "[harness] 세션 $session_id 은(는) $override 계정 소속 — CLAUDE_CONFIG_DIR 재지정" >&2
      CLAUDE_CONFIG_DIR="$override" command claude "$@"
      return $?
    fi
  fi
  command claude "$@"
}

# ── Orca ──

# Reset a stuck "working" spinner for an Orca pane whose Claude session is
# actually idle. See claude/skills/orca-relay/SKILL.md for the full playbook.
orca-nudge() {
  "$CHANMUZI_AGENT_HARNESS_HOME/shared/bin/orca-nudge" "$@"
}

# ── Codex CLI ──

# Default: bypass all approvals and sandbox (hooks provide safety guardrails)
codex() {
  command codex -p harness --dangerously-bypass-approvals-and-sandbox "$@"
}

# Safe: model asks for approval + workspace-write sandbox
codex-safe() {
  command codex -p harness -a on-request -s workspace-write "$@"
}
