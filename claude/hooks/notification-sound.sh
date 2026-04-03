#!/bin/bash
# Claude Code Notification hook: play sound only for main agent
# Skips sound when fired from sub-agents or team members

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')

# Sub-agent/teammate context → skip sound
[ -n "$AGENT_ID" ] && exit 0

if [ "$(uname)" = "Darwin" ]; then
  afplay -v 0.2 /System/Library/Sounds/Morse.aiff >/dev/null 2>&1 || true
else
  printf '\a'
fi
