#!/bin/bash
# Regression tests for shared/hooks/enforce-git-claw.sh.
#
# Runs the real hook against crafted PreToolUse JSON payloads and asserts
# whether each command is blocked (exit 2) or allowed (exit 0). Covers the
# check-3a false positives that motivated the -F/--file detection rework:
#   - a literal "-F"/"--file" inside a git commit -m MESSAGE (not a flag)
#   - a `git commit -F/--file` code EXAMPLE inside a gh pr/issue --body
# while confirming a real `git commit -F file` flag is still blocked and the
# gh detectors (checks 4/5) keep working (they need the gh body intact).
#
# Usage: bash shared/hooks/enforce-git-claw.test.sh
# Exit 0 = all pass, 1 = at least one failure.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/enforce-git-claw.sh"
D=$(printf '\x2d')   # a bare dash, kept out of literal tokens so THIS file's
                     # own `git commit -F` strings never trip the live hook

PASS=0
FAIL=0

# assert <expected: block|allow> <description> <command>
assert() {
  local expected="$1" desc="$2" cmd="$3"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
    | ENFORCE_GIT_CLAW=1 bash "$HOOK" >/dev/null 2>&1
  local code=$?
  local got=allow
  [ "$code" = "2" ] && got=block
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1))
    printf '  ok   %-58s (%s)\n' "$desc" "$got"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL   %-58s expected=%s got=%s (exit=%s)\n' "$desc" "$expected" "$got" "$code"
  fi
}

# --- check 3a: real file-input flag must stay blocked ---
assert block "real ${D}F flag"                 "git commit ${D}F /tmp/msg.txt"
assert block "real ${D}${D}file= flag"         "git commit ${D}${D}file=/tmp/msg.txt"

# --- check 3a false positives that must NOT block ---
assert allow "${D}F text inside commit message" \
  "git commit ${D}m \"docs: /commit ${D}F 차단 대응 항목 추가\""
assert allow "git-commit-${D}${D}file example inside gh pr --body" \
  "gh pr create ${D}${D}title \"Fix: x\" ${D}${D}body \"example: git commit ${D}${D}file msg.txt\""
assert allow "git-commit-${D}F example inside gh pr --body" \
  "gh pr create ${D}${D}title \"Fix: x\" ${D}${D}body \"run git commit ${D}F note.txt then push\""

# --- regression guard: gh detectors (checks 4/5) must keep working ---
assert allow "gh issue create carrying the body marker" \
  "gh issue create ${D}${D}title \"[Bug] x\" ${D}${D}body \"detail... Generated with [Claude Code]\""
assert block "gh issue create WITHOUT the body marker" \
  "gh issue create ${D}${D}title \"[Bug] x\" ${D}${D}body \"no marker here\""
assert block "gh pr create WITHOUT a capitalized-prefix title" \
  "gh pr create ${D}${D}title \"random title\" ${D}${D}body \"x\""
assert allow "gh pr create WITH a valid prefixed title" \
  "gh pr create ${D}${D}title \"Fix: proper\" ${D}${D}body \"x\""

# --- sanity: ordinary valid commit ---
assert allow "plain valid ${D}m commit" "git commit ${D}m \"fix: 뭔가 고침\""

echo
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS checks passed."
  exit 0
fi
echo "$FAIL failure(s), $PASS passed."
exit 1
