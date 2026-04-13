#!/bin/bash
# Guard destructive git and filesystem operations when the worktree is dirty.

set -u

SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  case "$SCRIPT_PATH" in
    /*) ;;
    *) SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
# shellcheck source=shared/lib/os.sh
. "$SCRIPT_DIR/../lib/os.sh"

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

if [ "${ALLOW_DESTRUCTIVE:-0}" = "1" ]; then
  exit 0
fi

is_dangerous_git_command() {
  printf '%s\n' "$1" | grep -Eq \
    'git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+(-[[:alnum:]-]*[fF][[:alnum:]-]*([dDxX][[:alnum:]-]*)?|-[[:alnum:]-]*[dDxX][[:alnum:]-]*[fF][[:alnum:]-]*)|checkout[[:space:]]+--([[:space:]]|$)|restore([[:space:]]+--source[[:graph:]]+)?([[:space:]]+--worktree)?[[:space:]]+\.([[:space:]]|$)|branch[[:space:]]+-D([[:space:]]|$)|push[[:space:]].*(--force-with-lease|--force|-f)([[:space:]]|$))'
}

is_dangerous_rm_command() {
  printf '%s\n' "$1" | grep -Eq '(^|[;&|[:space:]])rm[[:space:]]+-[[:alnum:]-]*[rR][[:alnum:]-]*[fF]?[[:space:]]+/([[:space:]]|$)'
}

emit_block_message() {
  local command="$1"
  local status_lines="${2:-}"

  printf 'BLOCKED: destructive command refused because the working tree is not clean.\n'
  printf 'Command: %s\n' "$command"
  if [ -n "$status_lines" ]; then
    printf 'Uncommitted changes detected:\n%s\n' "$status_lines"
  fi
  printf 'Set ALLOW_DESTRUCTIVE=1 only after preserving state, enumerating what will be lost, and getting explicit user confirmation.\n'
}

if is_dangerous_rm_command "$COMMAND"; then
  emit_block_message "$COMMAND"
  exit 2
fi

if ! is_dangerous_git_command "$COMMAND"; then
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

STATUS_OUTPUT="$(git status --porcelain 2>/dev/null || true)"
if [ -z "$STATUS_OUTPUT" ]; then
  exit 0
fi

emit_block_message "$COMMAND" "$STATUS_OUTPUT"
exit 2
