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

# Build a body-stripped copy of the command for git/gh argument detection.
# `gh issue create` and `gh pr create` may embed code examples (including
# `git commit -m "..."`) inside body arguments; without stripping them,
# the git detectors below would trip on documentation snippets that are
# not actually being executed. Restrict the strip to gh issue/pr create
# segments so that `-F` (which is also `git commit -F/--file`, a real
# violation) is only redacted in gh contexts.
COMMAND_NO_BODY="$(printf '%s' "$COMMAND" | perl -0777 -pe '
  # Pre-pass (global, no segment bounding): strip heredoc-form `--body
  # "$(cat <<TAG\n...\nTAG\n)"`. Heredoc bodies are data, not code: they may
  # legitimately contain command separators (`;`, `|`, `&`) and literal `"`
  # chars (markdown, code examples) that would otherwise truncate either the
  # outer segment regex below or the inner quoted-string regex. The TAG
  # backreference makes the body extent unambiguous, so we redact it first
  # and let the segment regex see a tidy `--body REDACTED` placeholder.
  #
  # Two alternations to mirror bash heredoc rules:
  # - `<<-TAG`  — terminator may be preceded by zero or more TABS (no spaces)
  # - `<<TAG`   — terminator must equal TAG exactly (no leading whitespace)
  # In both cases trailing whitespace on the terminator line breaks closure
  # in bash, so the regex requires `\1\n` immediately, not `\1\s*\n`.
  # Both whitespace-separated (`--body "..."`) and equals-separated
  # (`--body="..."`) flag forms are accepted. TAG capture is `\S+?` to admit
  # bash-legal non-`\w` delimiters (hyphens, dots, etc.).
  s{(?<=\s)(?:--body|-b)(?:\s+|=)"\$\(cat\s+<<-\s*[\x27"]?(\S+?)[\x27"]?\s*\n.*?\n\t*\1\n\s*\)\s*"}{--body REDACTED}gs;
  s{(?<=\s)(?:--body|-b)(?:\s+|=)"\$\(cat\s+<<\s*[\x27"]?(\S+?)[\x27"]?\s*\n.*?\n\1\n\s*\)\s*"}{--body REDACTED}gs;
  # Main pass: segment by `gh issue/pr create ...` (bounded by command
  # separators) and strip plain `--body "..."` / `--body-file FILE` forms.
  s{(\bgh\s+(?:issue|pr)\s+create\b[^|;&]*)}{
    my $seg = $1;
    $seg =~ s{(?<=\s)(?:--body|-b)(?:[\s=]+|(?=["\x27\S]))("([^"\\]*(?:\\.[^"\\]*)*)"|\x27([^\x27]*)\x27|(\S+))}{--body REDACTED}g;
    $seg =~ s{(?<=\s)(?:--body-file|-F)(?:[\s=]+|(?=["\x27\S]))\S+}{--body-file REDACTED}g;
    $seg;
  }ge;
' 2>/dev/null)"
if [ -z "$COMMAND_NO_BODY" ]; then
  COMMAND_NO_BODY="$COMMAND"
fi

# Symmetric strip: a `git commit -m "..."` message may itself reference
# `gh pr create --title ...` or `gh issue create ...` as documentation
# (e.g. release notes that quote those commands). Without stripping, the
# gh detectors below would falsely trigger on text inside commit messages.
# Match the entire `git commit ...` segment, then strip every -m/--message
# value within that segment so multi-`-m` invocations are fully covered.
COMMAND_NO_GIT_MSG="$(printf '%s' "$COMMAND" | perl -0777 -pe '
  # Pre-pass (mirrors COMMAND_NO_BODY): strip heredoc-form -m/--message
  # values globally before the segment regex bounds at command separators.
  # Same bash-rule alternations: `<<-` allows leading tabs only, `<<` is
  # exact. Both whitespace and equals flag forms supported.
  s{(?<=\s)(?:-m|--message)(?:\s+|=)"\$\(cat\s+<<-\s*[\x27"]?(\S+?)[\x27"]?\s*\n.*?\n\t*\1\n\s*\)\s*"}{-m REDACTED}gs;
  s{(?<=\s)(?:-m|--message)(?:\s+|=)"\$\(cat\s+<<\s*[\x27"]?(\S+?)[\x27"]?\s*\n.*?\n\1\n\s*\)\s*"}{-m REDACTED}gs;
  s{(\bgit\s+commit\b[^|;&]*)}{
    my $seg = $1;
    $seg =~ s{(?<=\s)-m(?:[\s=]+|(?=["\x27\S]))("([^"\\]*(?:\\.[^"\\]*)*)"|\x27([^\x27]*)\x27|(\S+))}{-m REDACTED}g;
    $seg =~ s{(?<=\s)--message(?:[\s=]+|=)("([^"\\]*(?:\\.[^"\\]*)*)"|\x27([^\x27]*)\x27|(\S+))}{--message REDACTED}g;
    $seg;
  }ge;
' 2>/dev/null)"
if [ -z "$COMMAND_NO_GIT_MSG" ]; then
  COMMAND_NO_GIT_MSG="$COMMAND"
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
if printf '%s\n' "$COMMAND_NO_BODY" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+add[[:space:]]+(-A|--all|-u|--update|\.|:/)([[:space:]]|$)'; then
  emit_block \
    'bulk staging (git add -A/--all/-u/--update/./:\/) bypasses per-file staging required by the /commit skill' \
    'invoke the /commit skill instead'
fi

# 2. git commit -a combined with -m in one flag (e.g. -am, -ma, -amv, -mav).
if printf '%s\n' "$COMMAND_NO_BODY" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+commit[[:space:]]+(-[[:alnum:]]*a[[:alnum:]]*m[[:alnum:]]*|-[[:alnum:]]*m[[:alnum:]]*a[[:alnum:]]*)([[:space:]]|$)'; then
  emit_block \
    'git commit -am/-ma combines staging and commit in one step, bypassing the /commit skill' \
    'invoke the /commit skill instead'
fi

# 3a. git commit -F / --file reads the message from a file, fully sidestepping
#     the /commit skill's message-generation logic. Match against
#     COMMAND_NO_GIT_MSG (not COMMAND_NO_BODY): the -F/--file flag is never
#     inside a -m message, so stripping the commit message first removes false
#     positives where the literal text "-F"/"--file" appears in the message
#     body (e.g. -m "docs: ... -F 차단 ...") while still catching a real
#     `git commit -F file` flag, which COMMAND_NO_GIT_MSG leaves intact.
if printf '%s\n' "$COMMAND_NO_GIT_MSG" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+commit\b.*(([[:space:]]-F[[:space:]=])|([[:space:]]--file[[:space:]=]))'; then
  emit_block \
    'git commit -F/--file reads the message from a file, bypassing the /commit skill entirely' \
    'invoke the /commit skill instead'
fi

# 3b. git commit with -m/--message (space, =, or concatenated short form like
#     -m"..." / -m'...' / -mword) whose message lacks the Conventional Commits
#     prefix the /commit skill emits. If -m/--message is present but the message
#     cannot be parsed, block anyway — we cannot verify the prefix safely.
COMMIT_MSG_PARSE="$(printf '%s\n' "$COMMAND_NO_BODY" | perl -0777 -ne '
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
  FIRST_LINE="$(printf '%s' "$MSG" | head -n1)"
  # Anchor the prefix check to the FIRST line only. With `-0777` slurp mode,
  # `grep -E "^..."` would otherwise match any line in a multi-line message,
  # letting `git commit -m "garbage\nfix: pretend"` slip past Conventional
  # Commits validation. (See PR #14.)
  #
  # Heredoc form `$(cat <<EOF...EOF\n)` — Claude Code's recommended default
  # for multi-line commit messages — generates the real text at bash-
  # substitution time, AFTER this PreToolUse hook runs. The captured text
  # begins with literal `$(cat`, so a strict prefix check would block every
  # legitimate multi-line commit. Allow only this narrow `$(cat ...)` pattern:
  # it is the platform's documented form, and `cat` produces no side effects,
  # keeping the bypass surface minimal. Other shell-substitution forms —
  # `$(printf ...)`, `$'...'`, `${VAR}`, backticks — fall through to the
  # prefix check (or are truncated by the perl `\S+` capture), preserving the
  # /commit skill's guarantees on the dynamic-`-m` surface. (See PR #14 for
  # the literal-newline anchor rationale, and PR #18 for the heredoc allow
  # decision; the narrow pattern below is from PR #18 review.)
  case "$FIRST_LINE" in
    '$(cat'*) ;;
    *)
      if ! printf '%s' "$FIRST_LINE" | grep -Eq "^$COMMIT_PREFIX"; then
        emit_block \
          "commit message \"$MSG\" lacks the Conventional Commits prefix required by the /commit skill" \
          'invoke the /commit skill to generate a properly-formatted message'
      fi
      ;;
  esac
elif [ "$COMMIT_MSG_STATUS" = "found" ]; then
  emit_block \
    'git commit -m/--message detected but the message could not be parsed for Conventional Commits verification' \
    'invoke the /commit skill instead'
fi

# 4. gh pr create whose --title lacks the /pr skill prefix.
if printf '%s\n' "$COMMAND_NO_GIT_MSG" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
  TITLE="$(printf '%s\n' "$COMMAND_NO_GIT_MSG" | perl -0777 -ne '
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
if printf '%s\n' "$COMMAND_NO_GIT_MSG" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+issue[[:space:]]+create([[:space:]]|$)'; then
  if ! printf '%s\n' "$COMMAND_NO_GIT_MSG" | grep -Eq "$ISSUE_BODY_MARKER"; then
    emit_block \
      'gh issue create without the /issue skill body marker ("Generated with [Claude Code]")' \
      'invoke the /issue skill instead'
  fi
fi

exit 0
