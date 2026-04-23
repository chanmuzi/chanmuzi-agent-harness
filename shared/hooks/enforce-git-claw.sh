#!/bin/bash
# Enforce git-claw skill usage by blocking common bypass patterns.
#
# When context grows long, Claude Code and Codex sometimes skip the
# /commit, /pr, /issue skills and call git/gh directly. This hook
# detects those shortcut patterns and nudges the agent back to the skill.
#
# Set ENFORCE_GIT_CLAW=0 to bypass (e.g. for emergency hot-fixes).

set -u

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
# shellcheck source=shared/lib/os.sh
. "$SCRIPT_DIR/../lib/os.sh"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"

if [ -z "$COMMAND" ]; then
  exit 0
fi

if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

if [ "${ENFORCE_GIT_CLAW:-1}" = "0" ]; then
  exit 0
fi

# Conventional Commits prefix the /commit skill always produces (lowercase).
COMMIT_PREFIX='(feat|fix|refactor|style|docs|test|perf|chore|hotfix)(\([^)]+\))?:'
# PR title prefix the /pr skill always produces (capitalized first letter).
PR_TITLE_PREFIX='(Feat|Fix|Refactor|Style|Perf|Docs|Test|Chore|Hotfix|Release):'
# Body marker the /issue skill always embeds.
ISSUE_BODY_MARKER='Generated with \[Claude Code\]'

emit_block() {
  local reason="$1" suggestion="$2"
  printf 'BLOCKED: git-claw skill bypass detected.\n' >&2
  printf 'Command: %s\n' "$COMMAND" >&2
  printf 'Reason: %s\n' "$reason" >&2
  printf 'Action: %s\n' "$suggestion" >&2
  printf 'Override: re-run with ENFORCE_GIT_CLAW=0 only after user confirmation.\n' >&2
  exit 2
}

# 1. Bulk staging (/commit skill forbids "git add -A", "git add .", "git add -u", "git add :/").
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+add[[:space:]]+(-A|--all|-u|--update|\.|:/)([[:space:]]|$)'; then
  emit_block \
    'bulk staging (git add -A/--all/-u/--update/./:\/) bypasses per-file staging required by the /commit skill' \
    'invoke the /commit skill instead'
fi

# 2. git commit -a combined with -m in one flag (e.g. -am, -ma, -amv, -mav).
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+commit[[:space:]]+(-[[:alnum:]]*a[[:alnum:]]*m[[:alnum:]]*|-[[:alnum:]]*m[[:alnum:]]*a[[:alnum:]]*)([[:space:]]|$)'; then
  emit_block \
    'git commit -am/-ma combines staging and commit in one step, bypassing the /commit skill' \
    'invoke the /commit skill instead'
fi

# 3a. git commit -F / --file reads the message from a file, fully sidestepping
#     the /commit skill's message-generation logic.
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+commit\b.*(([[:space:]]-F[[:space:]=])|([[:space:]]--file[[:space:]=]))'; then
  emit_block \
    'git commit -F/--file reads the message from a file, bypassing the /commit skill entirely' \
    'invoke the /commit skill instead'
fi

# 3b. git commit with -m/--message (space, =, or concatenated short form like
#     -m"..." / -m'...' / -mword) whose message lacks the Conventional Commits
#     prefix the /commit skill emits. If -m/--message is present but the message
#     cannot be parsed, block anyway — we cannot verify the prefix safely.
COMMIT_MSG_PARSE="$(printf '%s\n' "$COMMAND" | perl -ne '
  if (/\bgit\s+commit\b[^|;&]*?\s(?:-m(?:[\s=]+|(?=["\x27\S]))|--message(?:[\s=]+|=))("([^"\\]*(?:\\.[^"\\]*)*)"|\x27([^\x27]*)\x27|(\S+))/) {
    my $msg = defined $2 ? $2 : defined $3 ? $3 : $4;
    print "parsed\n$msg";
    exit;
  }
  if (/\bgit\s+commit\b[^|;&]*?\s(?:-m(?:[\s=]+|(?=["\x27\S]))|--message(?:[\s=]+|=))/) {
    print "found";
    exit;
  }
' 2>/dev/null)"
COMMIT_MSG_STATUS="$(printf '%s\n' "$COMMIT_MSG_PARSE" | head -n1)"
if [ "$COMMIT_MSG_STATUS" = "parsed" ]; then
  MSG="$(printf '%s\n' "$COMMIT_MSG_PARSE" | tail -n +2)"
  if ! printf '%s' "$MSG" | grep -Eq "^$COMMIT_PREFIX"; then
    emit_block \
      "commit message \"$MSG\" lacks the Conventional Commits prefix required by the /commit skill" \
      'invoke the /commit skill to generate a properly-formatted message'
  fi
elif [ "$COMMIT_MSG_STATUS" = "found" ]; then
  emit_block \
    'git commit -m/--message detected but the message could not be parsed for Conventional Commits verification' \
    'invoke the /commit skill instead'
fi

# 4. gh pr create whose --title lacks the /pr skill prefix.
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
  TITLE="$(printf '%s\n' "$COMMAND" | perl -ne '
    if (/\bgh\s+pr\s+create\b[^|;&]*?--title[\s=]+("([^"\\]*(?:\\.[^"\\]*)*)"|'"'"'([^'"'"']*)'"'"'|(\S+))/) {
      print defined $2 ? $2 : defined $3 ? $3 : $4;
      exit;
    }
  ' 2>/dev/null)"
  if [ -z "$TITLE" ]; then
    emit_block \
      'gh pr create without explicit --title bypasses the /pr skill (the skill always sets a capitalized prefix title)' \
      'invoke the /pr skill instead'
  elif ! printf '%s' "$TITLE" | grep -Eq "^$PR_TITLE_PREFIX"; then
    emit_block \
      "gh pr create title \"$TITLE\" lacks the capitalized prefix (Feat:/Fix:/...) required by the /pr skill" \
      'invoke the /pr skill instead; it fills in the PR template and title convention'
  fi
fi

# 5. gh issue create without the /issue skill body marker.
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+issue[[:space:]]+create([[:space:]]|$)'; then
  if ! printf '%s\n' "$COMMAND" | grep -Eq "$ISSUE_BODY_MARKER"; then
    emit_block \
      'gh issue create without the /issue skill body marker ("Generated with [Claude Code]")' \
      'invoke the /issue skill instead'
  fi
fi

exit 0
