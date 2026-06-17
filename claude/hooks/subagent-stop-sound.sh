#!/bin/bash
# Claude Code SubagentStop hook: play a distinct sound when a delegated
# sub-agent finishes.
#
# Why: background/sub-agent completion is not guaranteed to wake the main
# agent (see anthropics/claude-code #21048, #6854), so the user otherwise has
# to babysit the session and check manually. This gives an audible signal the
# moment delegated work completes.
#
# Unlike notification-sound.sh / stop-sound.sh this does NOT skip on agent_id:
# SubagentStop fires *from* a sub-agent context, so agent_id is expected here.

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')
[ "$EVENT" != "SubagentStop" ] && exit 0

HARNESS_HOME="${CHANMUZI_AGENT_HARNESS_HOME:-}"
if [ -z "$HARNESS_HOME" ]; then
  REAL_PATH="$(readlink -f "$0" 2>/dev/null || readlink "$0")"
  HARNESS_HOME="$(cd "$(dirname "$REAL_PATH")/../.." && pwd)"
fi
. "$HARNESS_HOME/shared/lib/os.sh" 2>/dev/null

# Debounce: collapse a burst of parallel sub-agent completions into one sound.
# State lives in a per-user 0700 dir (harness_state_file) to avoid the
# predictable-/tmp symlink hazard; skip silently if a safe path can't be had.
LAST_FILE="$(harness_state_file claude-subagent-stop-sound-last.epoch)" || exit 0
MIN_INTERVAL=5
NOW=$(date +%s)
LAST=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
[ $((NOW - LAST)) -lt $MIN_INTERVAL ] && exit 0
echo "$NOW" > "$LAST_FILE"

# Frog is distinct from the main-agent Stop sound, so a delegated-work
# completion is recognizable by ear. Falls back to terminal bell off macOS.
play_sound "/System/Library/Sounds/Frog.aiff" 0.2
