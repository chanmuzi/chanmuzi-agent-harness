#!/bin/bash
# Block --no-verify flag in git commands (Codex version)
# Codex PreToolUse sends JSON on stdin with tool_input.command

INPUT="$(cat)"
COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"

if echo "$COMMAND" | grep -qE -- '--no-verify'; then
  echo '{"decision":"block","reason":"--no-verify is not allowed. Fix the underlying issue instead of skipping hooks."}' >&2
  exit 2
fi
