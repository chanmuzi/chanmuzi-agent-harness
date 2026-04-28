#!/bin/bash
# Health check for chanmuzi-agent-harness
# Verifies symlinks, config patches, and dependencies

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=shared/lib/os.sh
. "$SCRIPT_DIR/shared/lib/os.sh"

REPO_DIR="$(resolve_path "$SCRIPT_DIR")"
REPO_DIR="${REPO_DIR%/.}"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
AGENTS_DIR="$HOME/.agents"
CODEX_MCP_FILE="$REPO_DIR/codex/mcp-servers.json"

ERRORS=0
WARNINGS=0

echo -e "${BOLD}=== Agent Harness Health Check ===${NC}"
echo -e "Repo: ${DIM}$REPO_DIR${NC}"
echo ""

# ── Helper ──
check_symlink() {
  local dst="$1" expected_src="$2" label="$3"
  if [ -L "$dst" ]; then
    actual_src="$(resolve_path "$dst" 2>/dev/null || readlink "$dst")"
    if [ "$actual_src" = "$expected_src" ]; then
      log_ok "$label"
    else
      log_warn "$label -> $actual_src (expected $expected_src)"
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ -e "$dst" ]; then
    log_error "$label exists but is NOT a symlink"
    ERRORS=$((ERRORS + 1))
  else
    log_error "$label missing"
    ERRORS=$((ERRORS + 1))
  fi
}

check_shared_skill_if_present() {
  local skill_name="$1"
  local src="$AGENTS_DIR/skills/$skill_name"
  local dst="$CODEX_DIR/skills/$skill_name"

  if [ -d "$src" ]; then
    check_symlink "$dst" "$src" "skill: $skill_name"
  fi
}

check_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -qF "$pattern" "$file" 2>/dev/null; then
    log_ok "$label"
  else
    log_error "$label missing"
    ERRORS=$((ERRORS + 1))
  fi
}

codex_mcp_field() {
  local name="$1" field="$2"
  codex mcp get "$name" 2>/dev/null | awk -F': ' -v key="$field" '$1 ~ "^  " key "$" {print $2}'
}

# ══════════════════════════════════════════
# SHELL RC
# ══════════════════════════════════════════
log_section "[Shell]"

RC_FILE=""
if [ "$(basename "${SHELL:-}")" = "zsh" ]; then
  RC_FILE="$HOME/.zshrc"
elif [ "$(basename "${SHELL:-}")" = "bash" ]; then
  RC_FILE="$HOME/.bashrc"
fi

if [ -n "$RC_FILE" ] && [ -f "$RC_FILE" ]; then
  if grep -qF "chanmuzi-agent-harness" "$RC_FILE"; then
    log_ok "harness source block in $RC_FILE"
  else
    log_error "harness source block missing from $RC_FILE"
    ERRORS=$((ERRORS + 1))
  fi

  if grep -qF "# >>> claude-config >>>" "$RC_FILE"; then
    log_warn "old claude-config block still in $RC_FILE (run setup.sh to clean)"
    WARNINGS=$((WARNINGS + 1))
  fi
fi
echo ""

# ══════════════════════════════════════════
# CLAUDE CODE
# ══════════════════════════════════════════
log_section "[Claude Code]"

if command -v claude &>/dev/null; then
  log_ok "CLI: $(claude --version 2>/dev/null || echo 'found')"
else
  log_warn "CLI not found"
  WARNINGS=$((WARNINGS + 1))
fi

check_symlink "$CLAUDE_DIR/CLAUDE.md"     "$REPO_DIR/claude/CLAUDE.md"     "CLAUDE.md"
check_symlink "$CLAUDE_DIR/settings.json" "$REPO_DIR/claude/settings.json" "settings.json"
check_symlink "$CLAUDE_DIR/statusline.sh" "$REPO_DIR/claude/statusline.sh" "statusline.sh"

for hook in "$REPO_DIR"/claude/hooks/*.sh; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook")"
  check_symlink "$CLAUDE_DIR/hooks/$name" "$hook" "hooks/$name"
  if [ -x "$hook" ]; then
    log_ok "repo hook executable: claude/hooks/$name"
  else
    log_error "repo hook not executable: claude/hooks/$name"
    ERRORS=$((ERRORS + 1))
  fi
done

if [ -x "$REPO_DIR/shared/hooks/guard-destructive-git.sh" ]; then
  log_ok "shared/hooks/guard-destructive-git.sh executable"
else
  log_error "shared/hooks/guard-destructive-git.sh missing or not executable"
  ERRORS=$((ERRORS + 1))
fi

if [ -x "$REPO_DIR/shared/hooks/block-no-verify.sh" ]; then
  log_ok "shared/hooks/block-no-verify.sh executable"
else
  log_error "shared/hooks/block-no-verify.sh missing or not executable"
  ERRORS=$((ERRORS + 1))
fi

if [ -x "$REPO_DIR/shared/hooks/enforce-git-claw.sh" ]; then
  log_ok "shared/hooks/enforce-git-claw.sh executable"
else
  log_error "shared/hooks/enforce-git-claw.sh missing or not executable"
  ERRORS=$((ERRORS + 1))
fi

for cmd in "$REPO_DIR"/claude/commands/*.md; do
  [ -f "$cmd" ] || continue
  name="$(basename "$cmd")"
  check_symlink "$CLAUDE_DIR/commands/$name" "$cmd" "commands/$name"
done

# extraKnownMarketplaces path residue check
SETTINGS_FILE="$REPO_DIR/claude/settings.json"
if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
  MP_ISSUES=$(jq -r '
    (.extraKnownMarketplaces // {}) | to_entries[] |
    . as $entry |
    ($entry.value.source? // {}) as $src |
    select($src.path? != null) |
    if $src.repo? != null then
      "error:" + ($entry.key // "")
    else
      "warn:" + ($entry.key // "")
    end
  ' "$SETTINGS_FILE" 2>/dev/null)

  if [ $? -ne 0 ]; then
    log_error "marketplace entries: failed to parse settings.json"
    ERRORS=$((ERRORS + 1))
  elif [ -z "$MP_ISSUES" ]; then
    log_ok "marketplace entries: no path residue"
  else
    while IFS=: read -r level mp_name; do
      [ -z "$level" ] && continue
      if [ "$level" = "error" ]; then
        log_error "marketplace $mp_name: path + repo conflict (remove path from settings.json)"
        ERRORS=$((ERRORS + 1))
      else
        log_warn "marketplace $mp_name: local path set (intentional?)"
        WARNINGS=$((WARNINGS + 1))
      fi
    done <<< "$MP_ISSUES"
  fi
fi

if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null && command -v claude >/dev/null 2>&1; then
  DECLARED_MARKETPLACES="$(jq -r '(.extraKnownMarketplaces // {}) | keys[]' "$SETTINGS_FILE" 2>/dev/null || true)"
  CONFIGURED_MARKETPLACES="$(claude plugin marketplace list 2>/dev/null | sed -n 's/^[[:space:]]*❯[[:space:]]*//p')"
  STALE_MARKETPLACES=""

  while IFS= read -r mp_name; do
    [ -z "$mp_name" ] && continue
    if ! printf '%s\n' "$DECLARED_MARKETPLACES" | grep -qxF "$mp_name"; then
      STALE_MARKETPLACES="${STALE_MARKETPLACES}${mp_name}\n"
    fi
  done <<< "$CONFIGURED_MARKETPLACES"

  if [ -z "$STALE_MARKETPLACES" ]; then
    log_ok "marketplaces: no undeclared registrations"
  else
    while IFS= read -r mp_name; do
      [ -z "$mp_name" ] && continue
      log_warn "marketplace $mp_name: registered but not declared in claude/settings.json"
      WARNINGS=$((WARNINGS + 1))
    done <<< "$(printf '%b' "$STALE_MARKETPLACES")"
  fi
fi
echo ""

# project doc sync check
PROJECT_DOC_RENDERER="$REPO_DIR/shared/render_project_docs.py"
if [ -f "$PROJECT_DOC_RENDERER" ]; then
  PROJECT_DOC_STDOUT_FILE="$(mktemp)"
  PROJECT_DOC_STDERR_FILE="$(mktemp)"
  if python3 "$PROJECT_DOC_RENDERER" --check >"$PROJECT_DOC_STDOUT_FILE" 2>"$PROJECT_DOC_STDERR_FILE"; then
    PROJECT_DOC_RENDER_STATUS=0
  else
    PROJECT_DOC_RENDER_STATUS=$?
  fi
  PROJECT_DOC_CHECK_OUTPUT="$(cat "$PROJECT_DOC_STDOUT_FILE")"
  PROJECT_DOC_CHECK_STDERR="$(cat "$PROJECT_DOC_STDERR_FILE")"
  rm -f "$PROJECT_DOC_STDOUT_FILE" "$PROJECT_DOC_STDERR_FILE"

  if [ "$PROJECT_DOC_RENDER_STATUS" -ne 0 ]; then
    log_warn "project doc renderer failed: shared/render_project_docs.py --check"
    WARNINGS=$((WARNINGS + 1))
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      log_warn "project doc renderer stderr: $line"
      WARNINGS=$((WARNINGS + 1))
    done <<< "$PROJECT_DOC_CHECK_STDERR"
  elif [ -z "$PROJECT_DOC_CHECK_OUTPUT" ]; then
    log_ok "project docs: CLAUDE.md and AGENTS.md are synchronized"
  else
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      doc_name="${line#out_of_sync:}"
      log_warn "project doc $doc_name is out of sync with shared/project-doc.md"
      WARNINGS=$((WARNINGS + 1))
    done <<< "$PROJECT_DOC_CHECK_OUTPUT"
  fi
else
  log_warn "project doc renderer missing: shared/render_project_docs.py"
  WARNINGS=$((WARNINGS + 1))
fi
echo ""

# parity policy checks
check_contains "$REPO_DIR/shared/project-doc.md" "## Agent Parity Policy" "project docs: Agent Parity Policy"
check_contains "$REPO_DIR/claude/CLAUDE.md" "Verify Before Acting or Reporting" "claude global doc: verify policy"
check_contains "$REPO_DIR/claude/CLAUDE.md" "Error Handling Integrity" "claude global doc: error policy"
check_contains "$REPO_DIR/claude/CLAUDE.md" 'Use `/commit`, `/pr`, `/pr release`, `/review` skills' "claude global doc: git workflow policy"
check_contains "$REPO_DIR/codex/AGENTS.md" "Verify Before Acting or Reporting" "codex global doc: verify policy"
check_contains "$REPO_DIR/codex/AGENTS.md" "Error Handling Integrity" "codex global doc: error policy"
check_contains "$REPO_DIR/codex/AGENTS.md" "managed git workflow skills" "codex global doc: git workflow policy"

TEMPLATE_PARITY_STATUS=$(python3 - "$REPO_DIR/templates/AGENTS.md" "$REPO_DIR/templates/CLAUDE.md" <<'PYEOF'
import sys
from pathlib import Path

agents = Path(sys.argv[1])
claude = Path(sys.argv[2])
if not agents.exists() or not claude.exists():
    print("missing")
    raise SystemExit

agents_body = "\n".join(agents.read_text(encoding="utf-8").splitlines()[1:])
claude_body = "\n".join(claude.read_text(encoding="utf-8").splitlines()[1:])
print("ok" if agents_body == claude_body else "diff")
PYEOF
)
case "$TEMPLATE_PARITY_STATUS" in
  ok)      log_ok "templates: AGENTS.md and CLAUDE.md bodies match" ;;
  missing) log_error "templates: AGENTS.md or CLAUDE.md missing"; ERRORS=$((ERRORS + 1)) ;;
  *)       log_warn "templates: AGENTS.md and CLAUDE.md bodies differ"; WARNINGS=$((WARNINGS + 1)) ;;
esac
echo ""

# ══════════════════════════════════════════
# CODEX CLI
# ══════════════════════════════════════════
log_section "[Codex CLI]"

if command -v codex &>/dev/null; then
  log_ok "CLI: $(codex --version 2>/dev/null || echo 'found')"
  CODEX_FEATURES_OUTPUT="$(codex features list 2>/dev/null || true)"
  if [ -n "$CODEX_FEATURES_OUTPUT" ]; then
    CODEX_HOOKS_FEATURE="$(printf '%s\n' "$CODEX_FEATURES_OUTPUT" | awk '$1 == "codex_hooks" {print $2 " " $3; exit}')"
    case "$CODEX_HOOKS_FEATURE" in
      "stable true")
        log_ok "codex_hooks feature: stable/enabled"
        ;;
      "")
        log_error "codex_hooks feature missing (upgrade @openai/codex; hooks guardrails unavailable)"
        ERRORS=$((ERRORS + 1))
        ;;
      *)
        log_error "codex_hooks feature not stable/enabled: $CODEX_HOOKS_FEATURE"
        ERRORS=$((ERRORS + 1))
        ;;
    esac
  else
    log_warn "codex features list unavailable (could not verify codex_hooks support)"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  log_warn "CLI not found"
  WARNINGS=$((WARNINGS + 1))
fi

check_symlink "$CODEX_DIR/AGENTS.md"   "$REPO_DIR/codex/AGENTS.md"   "AGENTS.md"
check_symlink "$CODEX_DIR/hooks.json"  "$REPO_DIR/codex/hooks.json"  "hooks.json"

if command -v omx &>/dev/null; then
  log_ok "oh-my-codex CLI: $(omx --version 2>/dev/null || echo 'found')"
else
  log_warn "oh-my-codex CLI not found (optional)"
  WARNINGS=$((WARNINGS + 1))
fi

check_symlink "$CODEX_DIR/hooks/codex-turn-complete-sound.sh" \
  "$REPO_DIR/codex/hooks/codex-turn-complete-sound.sh" "hooks/codex-turn-complete-sound.sh"
check_symlink "$CODEX_DIR/hooks/block-no-verify.sh" \
  "$REPO_DIR/codex/hooks/block-no-verify.sh" "hooks/block-no-verify.sh"
check_symlink "$CODEX_DIR/hooks/guard-destructive-git.sh" \
  "$REPO_DIR/codex/hooks/guard-destructive-git.sh" "hooks/guard-destructive-git.sh"
check_symlink "$CODEX_DIR/hooks/enforce-git-claw.sh" \
  "$REPO_DIR/codex/hooks/enforce-git-claw.sh" "hooks/enforce-git-claw.sh"
check_symlink "$CODEX_DIR/hooks/stop-sound.sh" \
  "$REPO_DIR/codex/hooks/stop-sound.sh" "hooks/stop-sound.sh"

if [ -x "$REPO_DIR/codex/hooks/guard-destructive-git.sh" ]; then
  log_ok "repo hook executable: codex/hooks/guard-destructive-git.sh"
else
  log_error "repo hook not executable: codex/hooks/guard-destructive-git.sh"
  ERRORS=$((ERRORS + 1))
fi

if [ -x "$REPO_DIR/codex/hooks/enforce-git-claw.sh" ]; then
  log_ok "repo hook executable: codex/hooks/enforce-git-claw.sh"
else
  log_error "repo hook not executable: codex/hooks/enforce-git-claw.sh"
  ERRORS=$((ERRORS + 1))
fi

if [ -x "$REPO_DIR/codex/hooks/block-no-verify.sh" ]; then
  log_ok "repo hook executable: codex/hooks/block-no-verify.sh"
else
  log_error "repo hook not executable: codex/hooks/block-no-verify.sh"
  ERRORS=$((ERRORS + 1))
fi

# config.toml checks
CONFIG_TOML="$CODEX_DIR/config.toml"
if [ -f "$CONFIG_TOML" ]; then
  if grep -qE '^model[[:space:]]*=' "$CONFIG_TOML" || grep -qE '^model_reasoning_effort[[:space:]]*=' "$CONFIG_TOML"; then
    log_warn "global model/model_reasoning_effort still present (setup.sh should remove top-level model pinning)"
    WARNINGS=$((WARNINGS + 1))
  else
    log_ok "global model/model_reasoning_effort pinning absent"
  fi

  if grep -q 'model_instructions_file' "$CONFIG_TOML"; then
    log_warn "model_instructions_file still present (should be removed)"
    WARNINGS=$((WARNINGS + 1))
  else
    log_ok "model_instructions_file removed"
  fi

  if grep -q 'codex_hooks = true' "$CONFIG_TOML"; then
    log_ok "codex_hooks enabled"
  else
    log_warn "codex_hooks not enabled"
    WARNINGS=$((WARNINGS + 1))
  fi

  if grep -q 'profiles\.harness' "$CONFIG_TOML"; then
    log_ok "[profiles.harness] present"
  else
    log_warn "[profiles.harness] missing"
    WARNINGS=$((WARNINGS + 1))
  fi

  TOP_LEVEL_NOTIFY_COUNT=$(python3 - "$CONFIG_TOML" <<'PYEOF'
import ast
import re
import sys

path = sys.argv[1]
managed = ["bash", "-lc", "~/.codex/hooks/codex-turn-complete-sound.sh"]
text = open(path, encoding="utf-8").read().splitlines()
count = 0
in_section = False
collecting = False
buffer = []
balance = 0

for raw_line in text:
    stripped = raw_line.strip()

    if collecting:
        buffer.append(raw_line)
        balance += raw_line.count("[") - raw_line.count("]")
        if balance > 0:
            continue

        candidate = "\n".join(buffer)
        candidate = re.sub(r"#.*", "", candidate)
        candidate = re.sub(r"^\s*notify\s*=\s*", "", candidate, count=1)
        try:
            parsed = ast.literal_eval(candidate.strip())
        except Exception:
            parsed = None
        if parsed == managed:
            count += 1
        collecting = False
        buffer = []
        balance = 0
        continue

    if not stripped or stripped.startswith("#"):
        continue
    if stripped.startswith("["):
        in_section = True
        continue
    if in_section or not re.match(r"^notify\s*=", stripped):
        continue

    collecting = True
    buffer = [raw_line]
    balance = raw_line.count("[") - raw_line.count("]")
    if balance <= 0:
        candidate = "\n".join(buffer)
        candidate = re.sub(r"#.*", "", candidate)
        candidate = re.sub(r"^\s*notify\s*=\s*", "", candidate, count=1)
        try:
            parsed = ast.literal_eval(candidate.strip())
        except Exception:
            parsed = None
        if parsed == managed:
            count += 1
        collecting = False
        buffer = []
        balance = 0

if collecting:
    candidate = "\n".join(buffer)
    candidate = re.sub(r"#.*", "", candidate)
    candidate = re.sub(r"^\s*notify\s*=\s*", "", candidate, count=1)
    try:
        parsed = ast.literal_eval(candidate.strip())
    except Exception:
        parsed = None
    if parsed == managed:
        count += 1

print(count)
PYEOF
)
  if [ "$TOP_LEVEL_NOTIFY_COUNT" -eq 1 ]; then
    log_ok "top-level managed notify configured exactly once"
  elif [ "$TOP_LEVEL_NOTIFY_COUNT" -gt 1 ]; then
    log_warn "top-level managed notify duplicated ($TOP_LEVEL_NOTIFY_COUNT entries)"
    WARNINGS=$((WARNINGS + 1))
  else
    log_warn "top-level managed notify missing"
    WARNINGS=$((WARNINGS + 1))
  fi

  if grep -q 'stop-sound\.sh' "$CODEX_DIR/hooks.json"; then
    log_warn "hooks.json still references stop-sound.sh"
    WARNINGS=$((WARNINGS + 1))
  else
    log_ok "hooks.json has no stop-sound.sh reference"
  fi

  if jq -e '
    (.hooks.PreToolUse // []) |
    any(.matcher == "Bash" and any(.hooks[]?; .command == "bash ~/.codex/hooks/block-no-verify.sh"))
  ' "$CODEX_DIR/hooks.json" >/dev/null 2>&1; then
    log_ok "hooks.json registers block-no-verify.sh"
  else
    log_error "hooks.json missing block-no-verify.sh registration"
    ERRORS=$((ERRORS + 1))
  fi

  if jq -e '
    (.hooks.PreToolUse // []) |
    any(.matcher == "Bash" and any(.hooks[]?; .command == "bash ~/.codex/hooks/guard-destructive-git.sh"))
  ' "$CODEX_DIR/hooks.json" >/dev/null 2>&1; then
    log_ok "hooks.json registers guard-destructive-git.sh"
  else
    log_error "hooks.json missing guard-destructive-git.sh registration"
    ERRORS=$((ERRORS + 1))
  fi

  if jq -e '
    (.hooks.PreToolUse // []) |
    any(.matcher == "Bash" and any(.hooks[]?; .command == "bash ~/.codex/hooks/enforce-git-claw.sh"))
  ' "$CODEX_DIR/hooks.json" >/dev/null 2>&1; then
    log_ok "hooks.json registers enforce-git-claw.sh"
  else
    log_error "hooks.json missing enforce-git-claw.sh registration"
    ERRORS=$((ERRORS + 1))
  fi

  if grep -q 'oh-my-codex (OMX) Configuration' "$CONFIG_TOML" || \
     grep -q 'developer_instructions = "You have oh-my-codex installed' "$CONFIG_TOML" || \
     grep -q '^\[mcp_servers\.omx_' "$CONFIG_TOML"; then
    log_warn "global ~/.codex/config.toml contains oh-my-codex user-scope entries"
    log_warn "recommended: keep OMX project-scoped only (avoid 'omx setup --scope user')"
    WARNINGS=$((WARNINGS + 1))
  else
    log_ok "no oh-my-codex user-scope config detected in ~/.codex/config.toml"
  fi

  REPO_TRUSTED=$(python3 - "$CONFIG_TOML" "$REPO_DIR" <<'PYEOF'
import json
import sys

path, repo_dir = sys.argv[1], sys.argv[2]
target_header = f'[projects.{json.dumps(repo_dir)}]'
lines = open(path).read().splitlines()

for i, line in enumerate(lines):
    if line.strip() != target_header:
        continue
    for j in range(i + 1, len(lines)):
        stripped = lines[j].strip()
        if stripped.startswith('['):
            break
        if stripped.startswith('trust_level'):
            print('yes' if '"trusted"' in stripped or "'trusted'" in stripped else 'no')
            raise SystemExit
    print('no')
    raise SystemExit
print('no')
PYEOF
)
  if [ "$REPO_TRUSTED" = "yes" ]; then
    log_ok "repo trust set for $REPO_DIR"
  else
    log_warn "repo trust missing for $REPO_DIR"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  log_warn "config.toml not found"
  WARNINGS=$((WARNINGS + 1))
fi

# Skills check
check_shared_skill_if_present "context7"

SKILLS_FILE="$REPO_DIR/codex/skills.txt"
if [ -f "$SKILLS_FILE" ]; then
  DUPLICATE_SKILLS=$(sed 's/#.*//' "$SKILLS_FILE" | xargs -n1 2>/dev/null | sort | uniq -d)
  if [ -n "$DUPLICATE_SKILLS" ]; then
    log_warn "codex/skills.txt has duplicate entries: $(echo "$DUPLICATE_SKILLS" | xargs)"
    WARNINGS=$((WARNINGS + 1))
  else
    log_ok "codex/skills.txt has no duplicate entries"
  fi

  while IFS= read -r skill_name; do
    skill_name="$(echo "$skill_name" | sed 's/#.*//' | xargs)"
    [ -z "$skill_name" ] && continue
    [ "$skill_name" = "context7" ] && continue
    if [ -d "$CODEX_DIR/skills/$skill_name" ]; then
      log_ok "skill: $skill_name"
    else
      log_warn "skill: $skill_name not installed"
      WARNINGS=$((WARNINGS + 1))
    fi
  done < "$SKILLS_FILE"
fi

# External skills check
EXTERNAL_SKILLS_FILE="$REPO_DIR/codex/external-skills.json"
if [ -f "$EXTERNAL_SKILLS_FILE" ] && command -v jq &>/dev/null; then
  # Schema: each entry needs repo (string), optional ref (string),
  # and either paths (string[]) or discover (string) — but not both empty
  if jq -e 'all(.[]; (.repo | type == "string") and ((.ref // "main") | type == "string") and ((.discover // null) | . == null or type == "string") and ((.paths | type == "array" and length > 0 and all(.[]; type == "string")) or (.discover | type == "string" and length > 0)))' "$EXTERNAL_SKILLS_FILE" >/dev/null 2>&1; then
    log_ok "codex/external-skills.json schema"
  else
    log_warn "codex/external-skills.json schema mismatch"
    WARNINGS=$((WARNINGS + 1))
  fi

  EXT_COUNT=$(jq length "$EXTERNAL_SKILLS_FILE")
  for i in $(seq 0 $((EXT_COUNT - 1))); do
    EXT_REPO=$(jq -r ".[$i].repo" "$EXTERNAL_SKILLS_FILE")
    EXT_DISCOVER=$(jq -r ".[$i].discover // empty" "$EXTERNAL_SKILLS_FILE")

    if [ -n "$EXT_DISCOVER" ]; then
      # Use list-skills.py to resolve expected skills, then check each
      SKILL_LISTER="$CODEX_DIR/skills/.system/skill-installer/scripts/list-skills.py"
      EXT_REF=$(jq -r ".[$i].ref // \"main\"" "$EXTERNAL_SKILLS_FILE")
      if [ -f "$SKILL_LISTER" ]; then
        DISCOVER_JSON=$(python3 "$SKILL_LISTER" \
          --repo "$EXT_REPO" --path "$EXT_DISCOVER" --ref "$EXT_REF" \
          --format json 2>/dev/null) && DISCOVER_OK=true || DISCOVER_OK=false
        if [ "$DISCOVER_OK" = true ] && [ -n "$DISCOVER_JSON" ]; then
          DISCOVER_NAMES=$(echo "$DISCOVER_JSON" | jq -er '.[].name' 2>/dev/null) || {
            log_warn "failed to parse discovered skills JSON from $EXT_REPO/$EXT_DISCOVER"
            WARNINGS=$((WARNINGS + 1))
            DISCOVER_NAMES=""
          }
          while IFS= read -r skill_name; do
            [ -z "$skill_name" ] && continue
            if [ -d "$CODEX_DIR/skills/$skill_name" ]; then
              log_ok "skill: $skill_name (discovered from $EXT_REPO)"
            else
              log_warn "skill: $skill_name not installed (discovered from $EXT_REPO)"
              WARNINGS=$((WARNINGS + 1))
            fi
          done <<< "$DISCOVER_NAMES"
        else
          log_warn "could not discover skills from $EXT_REPO/$EXT_DISCOVER (network?)"
          WARNINGS=$((WARNINGS + 1))
        fi
      else
        log_warn "list-skills.py not found — cannot verify discover entry for $EXT_REPO"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      while IFS= read -r skill_path; do
        skill_name="$(basename "$skill_path")"
        if [ -d "$CODEX_DIR/skills/$skill_name" ]; then
          log_ok "skill: $skill_name (from $EXT_REPO)"
        else
          log_warn "skill: $skill_name not installed (from $EXT_REPO)"
          WARNINGS=$((WARNINGS + 1))
        fi
      done < <(jq -r ".[$i].paths[]" "$EXTERNAL_SKILLS_FILE")
    fi
  done
fi

PROFILE_TOML="$REPO_DIR/codex/profile.toml"
if [ -f "$PROFILE_TOML" ]; then
  if grep -q '^\[profiles\.harness\]' "$PROFILE_TOML"; then
    log_ok "codex/profile.toml has [profiles.harness]"
  else
    log_warn "codex/profile.toml missing [profiles.harness]"
    WARNINGS=$((WARNINGS + 1))
  fi

fi

if [ -f "$CODEX_MCP_FILE" ] && command -v jq &>/dev/null; then
  if jq -e 'all(.[]; (.name | type == "string") and (.transport == "streamable_http") and (.url | type == "string") and (.auth | type == "string"))' "$CODEX_MCP_FILE" >/dev/null 2>&1; then
    log_ok "codex/mcp-servers.json schema"
  else
    log_warn "codex/mcp-servers.json schema mismatch"
    WARNINGS=$((WARNINGS + 1))
  fi

  if [ "$(jq 'length' "$CODEX_MCP_FILE")" -eq 0 ]; then
    log_ok "no managed MCP servers declared"
  elif command -v codex >/dev/null 2>&1; then
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      name="$(echo "$entry" | jq -r '.name')"
      url="$(echo "$entry" | jq -r '.url')"
      auth="$(echo "$entry" | jq -r '.auth')"
      bearer_env="$(echo "$entry" | jq -r '.bearer_token_env_var // empty')"

      if codex mcp get "$name" >/dev/null 2>&1; then
        current_url="$(codex_mcp_field "$name" "url")"
        current_bearer_env="$(codex_mcp_field "$name" "bearer_token_env_var")"
        [ "$current_bearer_env" = "-" ] && current_bearer_env=""

        if [ "$current_url" = "$url" ] && [ "$current_bearer_env" = "$bearer_env" ]; then
          log_ok "mcp: $name"
        else
          log_warn "mcp: $name config drift detected"
          WARNINGS=$((WARNINGS + 1))
        fi
      else
        log_warn "mcp: $name not configured"
        WARNINGS=$((WARNINGS + 1))
      fi

      if [ "$auth" = "bearer" ] && [ -n "$bearer_env" ]; then
        if [ -n "${!bearer_env:-}" ]; then
          log_ok "mcp auth env: $bearer_env"
        else
          log_warn "mcp auth env missing: $bearer_env"
          WARNINGS=$((WARNINGS + 1))
        fi
      fi
    done < <(jq -c '.[]' "$CODEX_MCP_FILE")
  fi

  EXISTING_MCP_NAMES="$(python3 - "$CONFIG_TOML" <<'PYEOF'
import re
import sys

path = sys.argv[1]
pattern = re.compile(r'^\[mcp_servers\.([^\]]+)\]\s*$')

for line in open(path):
    match = pattern.match(line.strip())
    if match:
        print(match.group(1))
PYEOF
)"
  DECLARED_MCP_NAMES="$(jq -r '.[].name' "$CODEX_MCP_FILE" 2>/dev/null || true)"
  STALE_MCP_NAMES=""

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if ! printf '%s\n' "$DECLARED_MCP_NAMES" | grep -qxF "$name"; then
      STALE_MCP_NAMES="${STALE_MCP_NAMES}${name}\n"
    fi
  done <<< "$EXISTING_MCP_NAMES"

  if [ -z "$STALE_MCP_NAMES" ]; then
    log_ok "mcp servers: no unmanaged entries"
  else
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      log_warn "mcp server $name: present in ~/.codex/config.toml but not declared in codex/mcp-servers.json"
      WARNINGS=$((WARNINGS + 1))
    done <<< "$(printf '%b' "$STALE_MCP_NAMES")"
  fi
fi
echo ""

if jq -e '
  (.hooks.PreToolUse // []) |
  any(.matcher == "Bash" and any(.hooks[]?; .command == "bash ~/.claude/hooks/guard-destructive-git.sh"))
' "$REPO_DIR/claude/settings.json" >/dev/null 2>&1; then
  log_ok "claude/settings.json registers guard-destructive-git.sh"
else
  log_error "claude/settings.json missing guard-destructive-git.sh registration"
  ERRORS=$((ERRORS + 1))
fi

if jq -e '
  (.hooks.PreToolUse // []) |
  any(.matcher == "Bash" and any(.hooks[]?; .command == "bash ~/.claude/hooks/enforce-git-claw.sh"))
' "$REPO_DIR/claude/settings.json" >/dev/null 2>&1; then
  log_ok "claude/settings.json registers enforce-git-claw.sh"
else
  log_error "claude/settings.json missing enforce-git-claw.sh registration"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# ══════════════════════════════════════════
# DEPENDENCIES
# ══════════════════════════════════════════
log_section "[Dependencies]"

for dep in jq python3 node tmux; do
  if command -v "$dep" &>/dev/null; then
    log_ok "$dep"
  else
    case "$dep" in
      jq)      log_error "$dep missing (required by hooks)"; ERRORS=$((ERRORS + 1)) ;;
      python3) log_error "$dep missing (required by config patching)"; ERRORS=$((ERRORS + 1)) ;;
      *)       log_warn "$dep missing (optional)"; WARNINGS=$((WARNINGS + 1)) ;;
    esac
  fi
done

if command -v dev-browser &>/dev/null; then
  log_ok "dev-browser: found"
else
  log_warn "dev-browser missing (recommended for Claude/Codex browser automation)"
  WARNINGS=$((WARNINGS + 1))
fi
echo ""

# ══════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
  echo -e "${BOLD}${GREEN}All checks passed.${NC}"
elif [ $ERRORS -eq 0 ]; then
  echo -e "${BOLD}${YELLOW}$WARNINGS warning(s), no errors.${NC}"
else
  echo -e "${BOLD}${RED}$ERRORS error(s), $WARNINGS warning(s).${NC}"
  echo "Run ./setup.sh to fix."
fi
