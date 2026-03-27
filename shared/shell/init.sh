#!/bin/bash
# Shell functions for Claude Code and Codex CLI
# Sourced from .zshrc/.bashrc via CHANMUZI_AGENT_HARNESS_HOME

export ENABLE_EXPERIMENTAL_MCP_CLI='true'

# ── Claude Code ──

# Default: skip permissions (hooks provide safety guardrails)
# env -u TMUX: workaround for Claude Code 256-color downgrade in tmux
# See: https://github.com/anthropics/claude-code/issues/36785
claude() {
  command env -u TMUX claude --dangerously-skip-permissions "$@"
}

claude-safe() {
  command env -u TMUX claude "$@"
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

# Default: no approval prompts + workspace-write sandbox (safe, no popups)
codex() {
  command codex -p harness -a never -s workspace-write "$@"
}

# Safe: model asks for approval when needed
codex-safe() {
  command codex -p harness -a on-request -s workspace-write "$@"
}

# YOLO: bypass all approvals and sandbox (use with caution)
codex-y() {
  command codex -p harness --dangerously-bypass-approvals-and-sandbox "$@"
}
