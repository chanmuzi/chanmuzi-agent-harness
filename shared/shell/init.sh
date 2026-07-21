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

# ── Codex CLI ──

# Default: bypass all approvals and sandbox (hooks provide safety guardrails)
codex() {
  command codex -p harness --dangerously-bypass-approvals-and-sandbox "$@"
}

# Safe: model asks for approval + workspace-write sandbox
codex-safe() {
  command codex -p harness -a on-request -s workspace-write "$@"
}
