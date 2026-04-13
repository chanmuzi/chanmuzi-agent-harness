#!/bin/bash
# Claude wrapper for the shared destructive operation guard.

SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  case "$SCRIPT_PATH" in
    /*) ;;
    *) SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

exec "$REPO_DIR/shared/hooks/guard-destructive-git.sh"
