#!/bin/bash
set -e

# ── Parse arguments ──
INSTALL_CLAUDE=false
INSTALL_CODEX=false

if [ $# -eq 0 ]; then
  INSTALL_CLAUDE=true
  INSTALL_CODEX=true
else
  for arg in "$@"; do
    case "$arg" in
      --claude) INSTALL_CLAUDE=true ;;
      --codex)  INSTALL_CODEX=true ;;
      --help|-h)
        echo "Usage: ./setup.sh [--claude] [--codex]"
        echo "  No flags: install both"
        echo "  --claude: Claude Code only"
        echo "  --codex:  Codex CLI only"
        exit 0
        ;;
      *) echo "Unknown option: $arg"; exit 1 ;;
    esac
  done
fi

# ── Load shared helpers ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=shared/lib/os.sh
. "$SCRIPT_DIR/shared/lib/os.sh"

REPO_DIR="$(resolve_path "$SCRIPT_DIR")"
REPO_DIR="${REPO_DIR%/.}"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

echo -e "${BOLD}=== Agent Harness Setup ===${NC}"
echo -e "Repo:   ${DIM}$REPO_DIR${NC}"
echo -e "OS:     ${DIM}$OS${NC}"
echo -e "Claude: ${DIM}$INSTALL_CLAUDE${NC}"
echo -e "Codex:  ${DIM}$INSTALL_CODEX${NC}"
echo ""

# ══════════════════════════════════════════
# CLAUDE CODE
# ══════════════════════════════════════════
if [ "$INSTALL_CLAUDE" = true ]; then
  log_section "[Claude] Setting up..."

  if ! command -v claude &>/dev/null; then
    log_warn "Claude Code CLI not found. Symlinks will be created but plugins skipped."
    log_info "Install with: npm install -g @anthropic-ai/claude-code"
    echo ""
  fi

  mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/commands"

  # ── Symlinks ──
  log_section "  Symlinks..."
  link_file "$REPO_DIR/claude/CLAUDE.md"       "$CLAUDE_DIR/CLAUDE.md"
  link_file "$REPO_DIR/claude/settings.json"   "$CLAUDE_DIR/settings.json"
  link_file "$REPO_DIR/claude/statusline.sh"   "$CLAUDE_DIR/statusline.sh"

  for hook in "$REPO_DIR"/claude/hooks/*.sh; do
    [ -f "$hook" ] || continue
    link_file "$hook" "$CLAUDE_DIR/hooks/$(basename "$hook")"
  done

  for cmd in "$REPO_DIR"/claude/commands/*.md; do
    [ -f "$cmd" ] || continue
    link_file "$cmd" "$CLAUDE_DIR/commands/$(basename "$cmd")"
  done
  echo ""

  # ── Plugins ──
  if command -v claude &>/dev/null; then
    log_section "  Plugins..."
    SETTINGS_FILE="$REPO_DIR/claude/settings.json"

    # Register custom marketplaces
    REGISTERED_MARKETPLACES=$(claude plugin marketplace list 2>/dev/null || echo "")
    MARKETPLACE_NAMES=$(python3 -c "
import json, sys
with open('$SETTINGS_FILE') as f:
    d = json.load(f)
for name, val in d.get('extraKnownMarketplaces', {}).items():
    repo = val.get('source', {}).get('repo', '')
    if repo:
        print(name + ' ' + repo)
" 2>/dev/null || true)

    while IFS=' ' read -r mp_name mp_repo; do
      [ -z "$mp_name" ] && continue
      if echo "$REGISTERED_MARKETPLACES" | grep -qF "$mp_name"; then
        log_ok "marketplace: $mp_name (already registered)"
      else
        log_action "marketplace: $mp_name ($mp_repo) ..."
        MP_OUTPUT=$(claude plugin marketplace add "$mp_repo" 2>&1) && MP_EXIT=0 || MP_EXIT=$?
        if [ $MP_EXIT -eq 0 ]; then
          log_ok "registered $mp_name"
        else
          echo "$MP_OUTPUT" | sed 's/^/    /'
          log_warn "Failed to register marketplace $mp_name"
        fi
      fi
    done <<< "$MARKETPLACE_NAMES"

    # Pull latest for marketplace clones
    MARKETPLACE_DIR="$CLAUDE_DIR/plugins/marketplaces"
    if [ -d "$MARKETPLACE_DIR" ]; then
      for mp_dir in "$MARKETPLACE_DIR"/*/; do
        [ -d "$mp_dir/.git" ] || continue
        mp_name="$(basename "$mp_dir")"
        MP_PULL_OUTPUT=$(git -C "$mp_dir" pull --ff-only 2>&1) && MP_PULL_EXIT=0 || MP_PULL_EXIT=$?
        if [ $MP_PULL_EXIT -eq 0 ]; then
          if echo "$MP_PULL_OUTPUT" | grep -q "Already up to date"; then
            log_ok "marketplace $mp_name: up to date"
          else
            log_ok "marketplace $mp_name: updated"
          fi
        else
          log_warn "marketplace $mp_name: pull failed"
        fi
      done
    fi

    # Install/remove plugins
    INSTALLED_PLUGINS=$(claude plugin list 2>/dev/null | grep -oE '[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+' || echo "")
    PLUGINS=$(jq -r '.enabledPlugins // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null || echo "")

    INSTALL_COUNT=0; SKIP_COUNT=0; FAIL_COUNT=0
    for plugin in $PLUGINS; do
      if echo "$INSTALLED_PLUGINS" | grep -qF "$plugin"; then
        log_ok "$plugin (already installed)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
      else
        log_action "$plugin ..."
        INSTALL_OUTPUT=$(claude plugin install "$plugin" 2>&1) && INSTALL_EXIT=0 || INSTALL_EXIT=$?
        echo "$INSTALL_OUTPUT" | sed 's/^/    /'
        if [ $INSTALL_EXIT -eq 0 ] && ! echo "$INSTALL_OUTPUT" | grep -qi "fail\|error\|not found"; then
          INSTALL_COUNT=$((INSTALL_COUNT + 1))
        else
          log_warn "Failed to install $plugin"
          FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
      fi
    done

    # Remove plugins not in enabledPlugins (skip if PLUGINS is empty to prevent accidental mass deletion)
    REMOVE_COUNT=0
    if [ -z "$PLUGINS" ] && [ -n "$INSTALLED_PLUGINS" ]; then
      log_warn "enabledPlugins parsing returned empty — skipping plugin removal"
    else
      while IFS= read -r installed; do
        [ -z "$installed" ] && continue
        if ! echo "$PLUGINS" | grep -qF "$installed"; then
          log_remove "removing $installed ..."
          claude plugin remove "$installed" 2>&1 >/dev/null && \
            log_remove "removed $installed" && REMOVE_COUNT=$((REMOVE_COUNT + 1)) || \
            log_warn "Failed to remove $installed"
        fi
      done <<< "$INSTALLED_PLUGINS"
    fi

    # Restore settings.json (plugin install may toggle enabled flags)
    git -C "$REPO_DIR" checkout -- claude/settings.json 2>/dev/null && \
      log_ok "settings.json restored" || true

    echo -e "  Plugins: ${GREEN}$INSTALL_COUNT new${NC}, ${DIM}$SKIP_COUNT present${NC}, ${DIM}$REMOVE_COUNT removed${NC}, ${RED}$FAIL_COUNT failed${NC}"
  fi
  echo ""
fi

# ══════════════════════════════════════════
# CODEX CLI
# ══════════════════════════════════════════
if [ "$INSTALL_CODEX" = true ]; then
  log_section "[Codex] Setting up..."

  if ! command -v codex &>/dev/null; then
    log_warn "Codex CLI not found. Symlinks will be created but skills skipped."
    log_info "Install with: npm install -g @openai/codex"
    echo ""
  fi

  mkdir -p "$CODEX_DIR/hooks"

  # ── Symlinks ──
  log_section "  Symlinks..."
  link_file "$REPO_DIR/codex/AGENTS.md"   "$CODEX_DIR/AGENTS.md"
  link_file "$REPO_DIR/codex/hooks.json"  "$CODEX_DIR/hooks.json"

  for hook in "$REPO_DIR"/codex/hooks/*.sh; do
    [ -f "$hook" ] || continue
    link_file "$hook" "$CODEX_DIR/hooks/$(basename "$hook")"
  done
  echo ""

  # ── config.toml patch ──
  log_section "  Patching config.toml..."
  CONFIG_TOML="$CODEX_DIR/config.toml"

  # Initialize config.toml if it doesn't exist (fresh install)
  if [ ! -f "$CONFIG_TOML" ]; then
    log_info "config.toml not found — creating minimal config"
    cat > "$CONFIG_TOML" <<'TOML'
personality = "pragmatic"

[features]
codex_hooks = true
TOML
    log_ok "created config.toml with defaults"
  fi

  # 1. Remove model_instructions_file (migrated to AGENTS.md)
  if grep -q 'model_instructions_file' "$CONFIG_TOML"; then
    sed_inplace '/^model_instructions_file/d' "$CONFIG_TOML"
    log_ok "removed model_instructions_file (migrated to AGENTS.md)"
  else
    log_skip "model_instructions_file already absent"
  fi

  # 2. Enable codex_hooks feature (also fix false → true)
  if grep -q 'codex_hooks = true' "$CONFIG_TOML"; then
    log_skip "codex_hooks already enabled"
  elif grep -q 'codex_hooks' "$CONFIG_TOML"; then
    sed_inplace 's/codex_hooks = false/codex_hooks = true/' "$CONFIG_TOML"
    log_ok "codex_hooks changed from false to true"
  elif grep -q '^\[features\]' "$CONFIG_TOML"; then
    sed_inplace '/^\[features\]/a\
codex_hooks = true' "$CONFIG_TOML"
    log_ok "added codex_hooks = true to existing [features]"
  else
    printf '\n[features]\ncodex_hooks = true\n' >> "$CONFIG_TOML"
    log_ok "added [features] codex_hooks = true"
  fi

  # 3. Merge [profiles.harness] block (remove old, append new)
  PROFILE_SRC="$REPO_DIR/codex/profile.toml"
  if [ -f "$PROFILE_SRC" ]; then
    # Remove existing [profiles.harness] block using line-by-line parsing
    if grep -q '^\[profiles\.harness\]' "$CONFIG_TOML"; then
      python3 - "$CONFIG_TOML" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path).readlines()
out, skip = [], False
for line in lines:
    if line.strip() == '[profiles.harness]':
        skip = True
        continue
    if skip and line.strip().startswith('['):
        skip = False
    if not skip:
        out.append(line)
while out and out[-1].strip() == '':
    out.pop()
out.append('\n')
open(path, 'w').writelines(out)
PYEOF
      log_ok "removed old [profiles.harness] block"
    fi

    # Append new profile block (skip comment lines from source)
    echo "" >> "$CONFIG_TOML"
    grep -v '^#' "$PROFILE_SRC" | grep -v '^$' >> "$CONFIG_TOML" || true
    echo "" >> "$CONFIG_TOML"
    log_ok "merged [profiles.harness] from profile.toml"
  fi

  # 4. Add project_doc_fallback_filenames at global level (before first [section])
  HAS_GLOBAL_FALLBACK=$(python3 - "$CONFIG_TOML" <<'PYEOF'
import sys
in_section = False
for line in open(sys.argv[1]):
    if line.strip().startswith('['):
        in_section = True
    if not in_section and 'project_doc_fallback_filenames' in line:
        print('yes'); break
else:
    print('no')
PYEOF
)
  if [ "$HAS_GLOBAL_FALLBACK" = "yes" ]; then
    log_skip "project_doc_fallback_filenames already at global level"
  else
    python3 - "$CONFIG_TOML" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path).readlines()
insert_at = 0
for i, line in enumerate(lines):
    if line.strip().startswith('['):
        break
    if line.strip() and not line.strip().startswith('#'):
        insert_at = i + 1
lines.insert(insert_at, 'project_doc_fallback_filenames = ["CLAUDE.md"]\n')
open(path, 'w').writelines(lines)
PYEOF
    log_ok "added project_doc_fallback_filenames at global level"
  fi
  echo ""

  # ── Skills ──
  if command -v codex &>/dev/null; then
    SKILL_INSTALLER="$CODEX_DIR/skills/.system/skill-installer/scripts/install-skill-from-github.py"
    SKILLS_FILE="$REPO_DIR/codex/skills.txt"
    if [ -f "$SKILLS_FILE" ]; then
      log_section "  Skills..."

      if [ -f "$SKILL_INSTALLER" ]; then
        while IFS= read -r skill_name; do
          # Skip comments and empty lines
          skill_name="$(echo "$skill_name" | sed 's/#.*//' | xargs)"
          [ -z "$skill_name" ] && continue

          if [ -d "$CODEX_DIR/skills/$skill_name" ]; then
            log_ok "$skill_name (already installed)"
          else
            log_action "installing $skill_name ..."
            SKILL_OUTPUT=$(python3 "$SKILL_INSTALLER" \
              --repo openai/skills \
              --path "skills/.curated/$skill_name" 2>&1) && SKILL_EXIT=0 || SKILL_EXIT=$?
            if [ $SKILL_EXIT -eq 0 ]; then
              log_ok "installed $skill_name"
            else
              echo "$SKILL_OUTPUT" | sed 's/^/    /'
              log_warn "Failed to install $skill_name"
            fi
          fi
        done < "$SKILLS_FILE"
      else
        log_warn "Skill installer not found. Run 'codex' once to initialize, then re-run setup."
      fi
      echo ""
    fi

  fi
fi

# ══════════════════════════════════════════
# SHELL FUNCTIONS (.zshrc / .bashrc)
# ══════════════════════════════════════════
log_section "[Shell] Configuring rc file..."

# Detect rc file
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
  RC_FILE="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "bash" ]; then
  RC_FILE="$HOME/.bashrc"
else
  RC_FILE=""
fi

OLD_MARKER_BEGIN="# >>> claude-config >>>"
OLD_MARKER_END="# <<< claude-config <<<"
NEW_MARKER_BEGIN="# >>> chanmuzi-agent-harness >>>"
NEW_MARKER_END="# <<< chanmuzi-agent-harness <<<"

NEW_BLOCK="$NEW_MARKER_BEGIN
export CHANMUZI_AGENT_HARNESS_HOME=\"$REPO_DIR\"
[ -f \"\$CHANMUZI_AGENT_HARNESS_HOME/shared/shell/init.sh\" ] && . \"\$CHANMUZI_AGENT_HARNESS_HOME/shared/shell/init.sh\"
$NEW_MARKER_END"

if [ -n "$RC_FILE" ]; then
  # Remove old claude-config block
  if grep -qF "$OLD_MARKER_BEGIN" "$RC_FILE" 2>/dev/null; then
    sed_inplace "/$OLD_MARKER_BEGIN/,/$OLD_MARKER_END/d" "$RC_FILE"
    log_ok "removed old claude-config block"
  fi

  # Remove old source line if present
  sed_inplace '/^# Claude Code config$/d; \|source.*shell/claude\.sh|d' "$RC_FILE" 2>/dev/null || true

  # Remove existing harness block (for re-runs)
  if grep -qF "$NEW_MARKER_BEGIN" "$RC_FILE" 2>/dev/null; then
    sed_inplace "/$NEW_MARKER_BEGIN/,/$NEW_MARKER_END/d" "$RC_FILE"
  fi

  # Clean trailing blank lines and append new block
  perl -i -0777pe 's/\n+$/\n/' "$RC_FILE"
  echo "" >> "$RC_FILE"
  echo "$NEW_BLOCK" >> "$RC_FILE"
  log_ok "shell functions written to $RC_FILE"
else
  log_warn "Could not detect shell. Add manually:"
  echo ""
  echo "$NEW_BLOCK"
fi
echo ""

# ══════════════════════════════════════════
# DEPENDENCY CHECK
# ══════════════════════════════════════════
log_section "[Dependencies] Checking..."

if ! command -v jq &>/dev/null; then
  log_error "jq is not installed (required by hooks)"
  if [ "$OS" = "Darwin" ]; then
    echo "         brew install jq"
  else
    echo "         sudo apt install jq"
  fi
else
  log_ok "jq: $(jq --version)"
fi

if ! command -v python3 &>/dev/null; then
  log_error "python3 is not installed (required by Codex config patching)"
else
  log_ok "python3: $(python3 --version 2>&1)"
fi

if ! command -v node &>/dev/null; then
  log_warn "node not installed (required by Claude Code plugins)"
else
  log_ok "node: $(node --version)"
fi

if ! command -v tmux &>/dev/null; then
  log_warn "tmux not installed (required by claude-team)"
else
  log_ok "tmux: $(tmux -V)"
fi

if [ "$OS" != "Darwin" ]; then
  log_info "Non-macOS: sound notifications will use terminal bell"
else
  log_ok "macOS: all hooks compatible"
fi
echo ""

echo -e "${BOLD}${GREEN}=== Setup Complete ===${NC}"
echo ""

# Show install instructions for missing CLIs (red highlight)
MISSING_CLI=false
if ! command -v claude &>/dev/null && [ "$INSTALL_CLAUDE" = true ]; then
  echo -e "  ${RED}${BOLD}[ACTION REQUIRED]${NC} Claude Code CLI not installed:"
  echo -e "    ${BOLD}npm install -g @anthropic-ai/claude-code${NC}"
  echo ""
  MISSING_CLI=true
fi
if ! command -v codex &>/dev/null && [ "$INSTALL_CODEX" = true ]; then
  echo -e "  ${RED}${BOLD}[ACTION REQUIRED]${NC} Codex CLI not installed:"
  echo -e "    ${BOLD}npm install -g @openai/codex${NC}"
  echo -e "    Then re-run: ${DIM}./setup.sh --codex${NC} (to install skills)"
  echo ""
  MISSING_CLI=true
fi

if [ "$MISSING_CLI" = false ]; then
  echo -e "  ${DIM}All tools configured. No further action needed.${NC}"
  echo ""
fi

# Reload shell to apply changes
echo -e "${DIM}Reloading shell...${NC}"
exec "$SHELL" -l
