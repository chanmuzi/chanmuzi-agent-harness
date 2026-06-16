#!/bin/bash
# Claude Code Stop hook: play notification sound only for main agent
# - Skips sub-agents/teammates (agent_id present)
# - Debounces rapid-fire stops during team operations

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')

# Sub-agent or teammate → skip
[ "$EVENT" != "Stop" ] && exit 0
[ -n "$AGENT_ID" ] && exit 0

HARNESS_HOME="${CHANMUZI_AGENT_HARNESS_HOME:-}"
if [ -z "$HARNESS_HOME" ]; then
  REAL_PATH="$(readlink -f "$0" 2>/dev/null || readlink "$0")"
  HARNESS_HOME="$(cd "$(dirname "$REAL_PATH")/../.." && pwd)"
fi
. "$HARNESS_HOME/shared/lib/os.sh" 2>/dev/null

# Debounce: suppress duplicate sounds within 5 seconds. State lives in a
# per-user 0700 dir (harness_state_file) to avoid the predictable-/tmp symlink
# hazard; skip silently if a safe path can't be had.
LAST_FILE="$(harness_state_file claude-stop-sound-last.epoch)" || exit 0
MIN_INTERVAL=5
NOW=$(date +%s)
LAST=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
[ $((NOW - LAST)) -lt $MIN_INTERVAL ] && exit 0
echo "$NOW" > "$LAST_FILE"

play_sound "" 0.2
