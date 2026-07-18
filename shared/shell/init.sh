#!/bin/bash
# Shell functions for Claude Code and Codex CLI
# Sourced from .zshrc/.bashrc via CHANMUZI_AGENT_HARNESS_HOME

export ENABLE_EXPERIMENTAL_MCP_CLI='true'

# ── Claude Code ──

# Resolve the git root of the current directory (empty when not in a git repo).
# Claude sessions must start at the repo root: root CLAUDE.md is an @AGENTS.md
# adapter, and subdirectory starts may skip the parent import expansion.
# See docs/decisions/2026-07-agent-instruction-loading.md
_claude_launch_dir() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Default: skip permissions (hooks provide safety guardrails)
# env -u TMUX: workaround for Claude Code 256-color downgrade in tmux
# See: https://github.com/anthropics/claude-code/issues/36785
# Runs in a subshell at the git root so the caller's cwd is untouched.
claude() {
  local launch_dir
  launch_dir="$(_claude_launch_dir)"
  if [ "$launch_dir" != "$PWD" ]; then
    echo "[harness] Claude 세션을 git 루트에서 시작합니다: $launch_dir" >&2
  fi
  ( cd "$launch_dir" && command env -u TMUX claude --dangerously-skip-permissions "$@" )
}

claude-safe() {
  local launch_dir
  launch_dir="$(_claude_launch_dir)"
  if [ "$launch_dir" != "$PWD" ]; then
    echo "[harness] Claude 세션을 git 루트에서 시작합니다: $launch_dir" >&2
  fi
  ( cd "$launch_dir" && command env -u TMUX claude "$@" )
}

claude-team() {
  local base_name
  if [ -n "$1" ] && case "$1" in -*) false;; *) true;; esac; then
    base_name="$1"; shift
  else
    base_name="$(basename "$PWD")"
  fi

  local name="$base_name"
  local counter=1
  while tmux has-session -t "$name" 2>/dev/null; do
    counter=$((counter + 1))
    name="${base_name}-${counter}"
  done

  if [ "$counter" -gt 1 ]; then
    echo "Session '$base_name' already exists. Creating '$name'..."
  fi

  tmux new-session -d -s "$name" && \
    sleep 0.3 && \
    tmux send-keys -t "$name" "claude --name '$name' $*" Enter

  if [ -z "$TMUX" ]; then
    tmux attach -t "$name"
  else
    tmux switch-client -t "$name"
  fi
}

claude-team-safe() {
  local base_name
  if [ -n "$1" ] && case "$1" in -*) false;; *) true;; esac; then
    base_name="$1"; shift
  else
    base_name="$(basename "$PWD")"
  fi

  local name="$base_name"
  local counter=1
  while tmux has-session -t "$name" 2>/dev/null; do
    counter=$((counter + 1))
    name="${base_name}-${counter}"
  done

  if [ "$counter" -gt 1 ]; then
    echo "Session '$base_name' already exists. Creating '$name'..."
  fi

  tmux new-session -d -s "$name" && \
    sleep 0.3 && \
    tmux send-keys -t "$name" "claude-safe --name '$name' $*" Enter

  if [ -z "$TMUX" ]; then
    tmux attach -t "$name"
  else
    tmux switch-client -t "$name"
  fi
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
