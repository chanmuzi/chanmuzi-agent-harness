#!/bin/bash
# Claude Code Notification hook: play sound only for main agent
# Skips sound when fired from sub-agents or team members

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')

# Sub-agent/teammate context → skip sound
[ -n "$AGENT_ID" ] && exit 0

HARNESS_HOME="${CHANMUZI_AGENT_HARNESS_HOME:-}"
if [ -z "$HARNESS_HOME" ]; then
  REAL_PATH="$(readlink -f "$0" 2>/dev/null || readlink "$0")"
  HARNESS_HOME="$(cd "$(dirname "$REAL_PATH")/../.." && pwd)"
fi
. "$HARNESS_HOME/shared/lib/os.sh" 2>/dev/null || exit 0
command -v play_sound >/dev/null 2>&1 || exit 0

# play_sound() honors the harness mute switch and falls back to the terminal
# bell on Linux; Morse is distinct from the Stop (Pop) and SubagentStop (Frog)
# sounds so a permission prompt is recognizable by ear.
play_sound "/System/Library/Sounds/Morse.aiff" 0.2
