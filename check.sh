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
else
  log_warn "config.toml not found"
  WARNINGS=$((WARNINGS + 1))
fi

# Skills check
SKILLS_FILE="$REPO_DIR/codex/skills.txt"
if [ -f "$SKILLS_FILE" ]; then
  while IFS= read -r skill_name; do
    skill_name="$(echo "$skill_name" | sed 's/#.*//' | xargs)"
    [ -z "$skill_name" ] && continue
    if [ -d "$CODEX_DIR/skills/$skill_name" ]; then
      log_ok "skill: $skill_name"
    else
      log_warn "skill: $skill_name not installed"
      WARNINGS=$((WARNINGS + 1))
    fi
  done < "$SKILLS_FILE"
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
