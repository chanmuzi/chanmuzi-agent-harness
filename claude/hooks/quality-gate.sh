#!/bin/bash
# PostToolUse hook: Run linter/formatter check after file edits
# Informational only (exit 0) — shows warnings but never blocks

# jq is required to parse hook input
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only run after Edit or Write
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

EXT="${FILE_PATH##*.}"

case "$EXT" in
  py)
    if command -v ruff &>/dev/null; then
      RESULT=$(ruff check "$FILE_PATH" 2>&1) || true
      if [ -n "$RESULT" ]; then
        echo "ruff issues found:"
        echo "$RESULT" | head -10
      fi
    fi
    ;;
  ts|tsx|js|jsx)
    # Try Biome first, then ESLint
    if command -v biome &>/dev/null; then
      RESULT=$(biome check "$FILE_PATH" 2>&1) || true
      if [ -n "$RESULT" ]; then
        echo "biome issues found:"
        echo "$RESULT" | head -10
      fi
    elif command -v npx &>/dev/null && [ -f "$(dirname "$FILE_PATH")/node_modules/.bin/eslint" ]; then
      RESULT=$(npx eslint "$FILE_PATH" --no-error-on-unmatched-pattern 2>&1) || true
      if [ -n "$RESULT" ]; then
        echo "eslint issues found:"
        echo "$RESULT" | head -10
      fi
    fi
    ;;
esac

exit 0
