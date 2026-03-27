#!/usr/bin/env bash
# Legacy notify hook for Codex (called via config.toml notify field)
# Suppresses duplicate sounds within a short window
set -u

STATE_FILE="/tmp/codex-approval-last-played.epoch"
POP_SOUND="/System/Library/Sounds/Pop.aiff"
VOLUME="0.2"
SUPPRESS_WINDOW_SEC=6

now=$(date +%s)
last=0
if [[ -f "$STATE_FILE" ]]; then
  read -r last < "$STATE_FILE" || last=0
fi

if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last <= SUPPRESS_WINDOW_SEC )); then
  exit 0
fi

if [ "$(uname)" = "Darwin" ]; then
  afplay -v "$VOLUME" "$POP_SOUND" >/dev/null 2>&1
else
  printf '\a'
fi

echo "$now" > "$STATE_FILE"
