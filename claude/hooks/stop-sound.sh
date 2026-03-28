#!/bin/bash
# Claude Code Stop hook: play notification sound
# Delegates to shared play_sound helper

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')

if [ "$EVENT" = "Stop" ]; then
  HARNESS_HOME="${CHANMUZI_AGENT_HARNESS_HOME:-}"
  if [ -z "$HARNESS_HOME" ]; then
    # Resolve symlink to find repo root
    REAL_PATH="$(readlink -f "$0" 2>/dev/null || readlink "$0")"
    HARNESS_HOME="$(cd "$(dirname "$REAL_PATH")/../.." && pwd)"
  fi
  . "$HARNESS_HOME/shared/lib/os.sh" 2>/dev/null
  play_sound "" 0.2
fi
