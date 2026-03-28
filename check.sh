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
done

for cmd in "$REPO_DIR"/claude/commands/*.md; do
  [ -f "$cmd" ] || continue
  name="$(basename "$cmd")"
  check_symlink "$CLAUDE_DIR/commands/$name" "$cmd" "commands/$name"
done
echo ""

# ══════════════════════════════════════════
# CODEX CLI
# ══════════════════════════════════════════
log_section "[Codex CLI]"

if command -v codex &>/dev/null; then
  log_ok "CLI: $(codex --version 2>/dev/null || echo 'found')"
else
  log_warn "CLI not found"
  WARNINGS=$((WARNINGS + 1))
fi

check_symlink "$CODEX_DIR/AGENTS.md"   "$REPO_DIR/codex/AGENTS.md"   "AGENTS.md"
check_symlink "$CODEX_DIR/hooks.json"  "$REPO_DIR/codex/hooks.json"  "hooks.json"

for hook in "$REPO_DIR"/codex/hooks/*.sh; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook")"
  check_symlink "$CODEX_DIR/hooks/$name" "$hook" "hooks/$name"
done

# config.toml checks
CONFIG_TOML="$CODEX_DIR/config.toml"
if [ -f "$CONFIG_TOML" ]; then
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

  if grep -q 'project_doc_fallback_filenames' "$CONFIG_TOML"; then
    log_ok "project_doc_fallback_filenames set"
  else
    log_warn "project_doc_fallback_filenames missing"
    WARNINGS=$((WARNINGS + 1))
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
  if jq -e 'all(.[]; (.repo | type == "string") and ((.ref // "main") | type == "string") and (.paths | type == "array") and (.paths | length > 0) and all(.paths[]; type == "string"))' "$EXTERNAL_SKILLS_FILE" >/dev/null 2>&1; then
    log_ok "codex/external-skills.json schema"
  else
    log_warn "codex/external-skills.json schema mismatch"
    WARNINGS=$((WARNINGS + 1))
  fi

  EXT_COUNT=$(jq length "$EXTERNAL_SKILLS_FILE")
  for i in $(seq 0 $((EXT_COUNT - 1))); do
    EXT_REPO=$(jq -r ".[$i].repo" "$EXTERNAL_SKILLS_FILE")
    while IFS= read -r skill_path; do
      skill_name="$(basename "$skill_path")"
      if [ -d "$CODEX_DIR/skills/$skill_name" ]; then
        log_ok "skill: $skill_name (from $EXT_REPO)"
      else
        log_warn "skill: $skill_name not installed (from $EXT_REPO)"
        WARNINGS=$((WARNINGS + 1))
      fi
    done < <(jq -r ".[$i].paths[]" "$EXTERNAL_SKILLS_FILE")
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

  if grep -q '^project_doc_fallback_filenames' "$PROFILE_TOML"; then
    log_ok "codex/profile.toml sets project_doc_fallback_filenames"
  else
    log_warn "codex/profile.toml missing project_doc_fallback_filenames"
    WARNINGS=$((WARNINGS + 1))
  fi
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
