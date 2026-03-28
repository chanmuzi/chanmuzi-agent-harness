#!/bin/bash
# Claude Code Stop hook: play notification sound
# Delegates to shared play_sound helper

command -v jq &>/dev/null || exit 0

resolve_script_dir() {
  local source_path="${BASH_SOURCE[0]}"
  while [ -L "$source_path" ]; do
    local source_dir
    source_dir="$(cd "$(dirname "$source_path")" && pwd)"
    source_path="$(readlink "$source_path")"
    [ "${source_path#/}" = "$source_path" ] && source_path="$source_dir/$source_path"
  done
  cd "$(dirname "$source_path")" && pwd
}

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')

if [ "$EVENT" = "Stop" ]; then
  SCRIPT_DIR="$(resolve_script_dir)"
  . "$SCRIPT_DIR/../../shared/lib/os.sh" 2>/dev/null || exit 0
  play_sound "" 0.2
fi
