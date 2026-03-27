#!/bin/bash
# Codex Stop hook: play notification sound
# Delegates to shared play_sound helper

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../shared/lib/os.sh" 2>/dev/null
play_sound "" 0.2
