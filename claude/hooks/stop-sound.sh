#!/bin/bash
# Claude Code Stop hook: play notification sound
# Delegates to shared play_sound helper

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')

if [ "$EVENT" = "Stop" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  . "$SCRIPT_DIR/../../shared/lib/os.sh" 2>/dev/null
  play_sound "" 0.2
fi
