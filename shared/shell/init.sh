#!/bin/bash
# Shell functions for Claude Code and Codex CLI
# Sourced from .zshrc/.bashrc via CHANMUZI_AGENT_HARNESS_HOME

export ENABLE_EXPERIMENTAL_MCP_CLI='true'

# ── Claude Code ──

# Config directory for the work (Upstage) account. The personal account keeps
# the default ~/.claude so existing harness symlinks stay untouched.
# See docs/decisions/ for why accounts are separated this way.
CC_UP_CONFIG_DIR="${CC_UP_CONFIG_DIR:-$HOME/.claude-upstage}"

# Resolve the git root of the current directory (empty when not in a git repo).
# Claude sessions must start at the repo root: root CLAUDE.md is an @AGENTS.md
# adapter, and subdirectory starts may skip the parent import expansion.
# See docs/decisions/2026-07-agent-instruction-loading.md
_cc_launch_dir() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Launch Claude Code at the git root with permissions skipped
# (hooks provide the safety guardrails).
# $1: CLAUDE_CONFIG_DIR to use, or "" for the default (~/.claude).
# env -u TMUX: workaround for Claude Code 256-color downgrade in tmux
# See: https://github.com/anthropics/claude-code/issues/36785
# Runs in a subshell so the caller's cwd and environment are untouched.
_cc_run() {
  local config_dir="$1"
  shift

  local launch_dir
  launch_dir="$(_cc_launch_dir)"
  if [ "$launch_dir" != "$PWD" ]; then
    echo "[harness] Claude 세션을 git 루트에서 시작합니다: $launch_dir" >&2
  fi

  (
    cd "$launch_dir" || return 1
    # unset (not just "skip") matters: a caller may already have
    # CLAUDE_CONFIG_DIR exported (e.g. a shell spawned from a cc-up session),
    # and inheriting it would start the personal command on the work account.
    if [ -n "$config_dir" ]; then
      export CLAUDE_CONFIG_DIR="$config_dir"
    else
      unset CLAUDE_CONFIG_DIR
    fi
    command env -u TMUX claude --dangerously-skip-permissions "$@"
  )
}

# Personal account (default ~/.claude)
cc() {
  _cc_run "" "$@"
}

# Work account: chanmuzi@upstage.ai
cc-up() {
  _cc_run "$CC_UP_CONFIG_DIR" "$@"
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
