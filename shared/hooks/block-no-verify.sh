#!/bin/bash
# Block --no-verify in git commands for both Claude Code and Codex CLI.

set -u

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"

if [ -z "$COMMAND" ]; then
  exit 0
fi

if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

if printf '%s\n' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+commit([[:space:]]+[^;&|]*)?[[:space:]](--no-verify|-n)([;&|[:space:]]|$)' ||
   printf '%s\n' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]+[^;&|]*)?[[:space:]]--no-verify([;&|[:space:]]|$)'; then
  printf 'BLOCKED: --no-verify and git commit -n are not allowed. Fix the underlying issue instead of skipping hooks.\n' >&2
  printf 'Command: %s\n' "$COMMAND" >&2
  exit 2
fi

exit 0
