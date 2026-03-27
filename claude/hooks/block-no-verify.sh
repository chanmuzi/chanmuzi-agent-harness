#!/bin/bash
# PreToolUse hook: Block --no-verify flag on git commits
# Exit 2 = block the tool call, Exit 0 = allow

# jq is required to parse hook input
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check Bash tool calls
[ "$TOOL" != "Bash" ] && exit 0

# Block --no-verify on git commit/push
if echo "$TOOL_INPUT" | grep -qE 'git\s+(commit|push).*--no-verify'; then
  echo "BLOCKED: --no-verify is not allowed. Pre-commit hooks must run."
  exit 2
fi

exit 0
