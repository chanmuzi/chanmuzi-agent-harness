#!/usr/bin/env bash
# Legacy notify hook for Codex (called via config.toml notify field)
# Suppresses duplicate sounds within a short window
set -u

HARNESS_HOME="${CHANMUZI_AGENT_HARNESS_HOME:-}"
if [ -z "$HARNESS_HOME" ]; then
  REAL_PATH="$(readlink -f "$0" 2>/dev/null || readlink "$0")"
  HARNESS_HOME="$(cd "$(dirname "$REAL_PATH")/../.." && pwd)"
fi
. "$HARNESS_HOME/shared/lib/os.sh" 2>/dev/null

POP_SOUND="/System/Library/Sounds/Pop.aiff"
VOLUME="0.2"
SUPPRESS_WINDOW_SEC=6

# State lives in a per-user 0700 dir (harness_state_file) to avoid the
# predictable-/tmp symlink hazard; skip silently if a safe path can't be had.
STATE_FILE="$(harness_state_file codex-approval-last-played.epoch)" || exit 0

now=$(date +%s)
last=0
if [[ -f "$STATE_FILE" ]]; then
  read -r last < "$STATE_FILE" || last=0
fi

if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last <= SUPPRESS_WINDOW_SEC )); then
  exit 0
fi

play_sound "$POP_SOUND" "$VOLUME"

echo "$now" > "$STATE_FILE"
