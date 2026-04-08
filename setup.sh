#!/bin/bash
set -e

# ── Parse arguments ──
INSTALL_CLAUDE=false
INSTALL_CODEX=false
INSTALL_OMX=false

if [ $# -eq 0 ]; then
  INSTALL_CLAUDE=true
  INSTALL_CODEX=true
else
  for arg in "$@"; do
    case "$arg" in
      --claude) INSTALL_CLAUDE=true ;;
      --codex)  INSTALL_CODEX=true ;;
      --install-omx) INSTALL_OMX=true ;;
      --help|-h)
        echo "Usage: ./setup.sh [--claude] [--codex] [--install-omx]"
        echo "  No flags: install both"
        echo "  --claude: Claude Code only"
        echo "  --codex:  Codex CLI only"
        echo "  --install-omx: Install/upgrade oh-my-codex CLI only (no omx setup)"
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
AGENTS_DIR="$HOME/.agents"
CODEX_MCP_FILE="$REPO_DIR/codex/mcp-servers.json"

link_shared_skill_if_present() {
  local skill_name="$1"
  local src="$AGENTS_DIR/skills/$skill_name"
  local dst="$CODEX_DIR/skills/$skill_name"

  if [ -d "$src" ]; then
    link_file "$src" "$dst"
  else
    log_warn "$skill_name not found in $src"
    log_info "This is non-fatal. Other setup steps continue."
    log_info "Create ~/.agents/skills/$skill_name and place SKILL.md there, then re-run: ./setup.sh --codex"
  fi
}

get_remote_sha() {
  local repo="$1" ref="${2:-main}"
  git ls-remote "https://github.com/$repo.git" "$ref" 2>/dev/null | awk '{print $1}'
}

write_installed_ref() {
  echo "$2" > "$1/.installed-ref"
}

read_installed_ref() {
  [ -f "$1/.installed-ref" ] && cat "$1/.installed-ref" || echo ""
}

install_dev_browser_cli() {
  if ! command -v npm >/dev/null 2>&1; then
    log_warn "npm not found. Skipping dev-browser CLI install."
    log_info "Install Node.js/npm first, then re-run: ./setup.sh"
    echo ""
    return 0
  fi

  log_section "[dev-browser] Installing CLI..."

  DEV_BROWSER_OUTPUT=$(npm install -g dev-browser 2>&1) && DEV_BROWSER_EXIT=0 || DEV_BROWSER_EXIT=$?
  if [ $DEV_BROWSER_EXIT -eq 0 ]; then
    log_ok "dev-browser CLI installed/updated"
  else
    echo "$DEV_BROWSER_OUTPUT" | sed 's/^/    /'
    log_warn "Failed to install dev-browser CLI"
    echo ""
    return 0
  fi

  if command -v dev-browser >/dev/null 2>&1; then
    DEV_BROWSER_INSTALL_OUTPUT=$(dev-browser install 2>&1) && DEV_BROWSER_INSTALL_EXIT=0 || DEV_BROWSER_INSTALL_EXIT=$?
    if [ $DEV_BROWSER_INSTALL_EXIT -eq 0 ]; then
      log_ok "dev-browser runtime installed"
    else
      echo "$DEV_BROWSER_INSTALL_OUTPUT" | sed 's/^/    /'
      log_warn "Failed to install dev-browser runtime"
    fi
    log_ok "dev-browser CLI ready"
  else
    log_warn "dev-browser CLI installed but not found in PATH"
  fi
  echo ""
}

sync_codex_mcp_servers() {
  local file="$1" config_toml="$2"
  [ -f "$file" ] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    log_warn "jq missing — skipping Codex MCP sync"
    return 0
  fi

  log_section "  MCP Servers..."

  if ! jq -e 'all(.[]; (.name | type == "string") and (.transport == "streamable_http") and (.url | type == "string") and (.auth | type == "string"))' "$file" >/dev/null 2>&1; then
    log_warn "codex/mcp-servers.json schema mismatch — skipping MCP sync"
    echo ""
    return 0
  fi

  PRUNE_OUTPUT=$(python3 - "$config_toml" "$file" <<'PYEOF'
import json
import re
import sys

path, json_path = sys.argv[1], sys.argv[2]
declared = {entry["name"] for entry in json.load(open(json_path))}
lines = open(path).read().splitlines(True)
out = []
removed = []
i = 0
pattern = re.compile(r'^\[mcp_servers\.([^\]]+)\]\s*$')

while i < len(lines):
    line = lines[i]
    match = pattern.match(line.strip())
    if not match:
        out.append(line)
        i += 1
        continue

    name = match.group(1)
    j = i + 1
    while j < len(lines) and not lines[j].strip().startswith('['):
        j += 1

    if name in declared:
        out.extend(lines[i:j])
    else:
        removed.append(name)

    i = j

open(path, "w").writelines(out)
print("\n".join(removed))
PYEOF
) && PRUNE_EXIT=0 || PRUNE_EXIT=$?
  if [ $PRUNE_EXIT -eq 0 ]; then
    if [ -n "$PRUNE_OUTPUT" ]; then
      while IFS= read -r stale_name; do
        [ -z "$stale_name" ] && continue
        log_remove "removed unmanaged MCP server: $stale_name"
      done <<< "$PRUNE_OUTPUT"
    else
      log_skip "no unmanaged MCP servers to remove"
    fi
  else
    echo "$PRUNE_OUTPUT" | sed 's/^/    /'
    log_warn "Failed to prune unmanaged MCP servers"
  fi

  if [ "$(jq 'length' "$file")" -eq 0 ]; then
    log_skip "no managed MCP servers declared"
    echo ""
    return 0
  fi

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue

    local name url auth bearer_env
    name="$(echo "$entry" | jq -r '.name')"
    url="$(echo "$entry" | jq -r '.url')"
    auth="$(echo "$entry" | jq -r '.auth')"
    bearer_env="$(echo "$entry" | jq -r '.bearer_token_env_var // empty')"

    log_action "syncing $name MCP in config.toml ..."
    MCP_OUTPUT=$(python3 - "$config_toml" "$name" "$url" "$bearer_env" <<'PYEOF'
import sys

path, name, url, bearer_env = sys.argv[1:5]
header = f"[mcp_servers.{name}]"
lines = open(path).read().splitlines(True)

start = None
end = len(lines)
for i, line in enumerate(lines):
    if line.strip() == header:
        start = i
        for j in range(i + 1, len(lines)):
            if lines[j].strip().startswith("["):
                end = j
                break
        break

block = [f"{header}\n", f'url = "{url}"\n']
if bearer_env:
    block.append(f'bearer_token_env_var = "{bearer_env}"\n')

if start is None:
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.extend(block)
    status = "added"
else:
    replacement = lines[start:end]
    normalized_old = [line.strip() for line in replacement if line.strip()]
    normalized_new = [line.strip() for line in block if line.strip()]
    if normalized_old == normalized_new:
        status = "already"
    else:
        lines[start:end] = block
        status = "updated"

open(path, "w").writelines(lines)
print(status)
PYEOF
) && MCP_EXIT=0 || MCP_EXIT=$?
    if [ $MCP_EXIT -eq 0 ]; then
      case "$MCP_OUTPUT" in
        already) log_ok "$name (already configured)" ;;
        added)   log_ok "$name MCP added to config.toml" ;;
        updated) log_ok "$name MCP updated in config.toml" ;;
        *)       log_ok "$name MCP synced" ;;
      esac
    else
      echo "$MCP_OUTPUT" | sed 's/^/    /'
      log_warn "Failed to sync $name MCP"
    fi

    if [ "$auth" = "oauth" ]; then
      log_info "If $name needs authentication on this machine, run: codex mcp login $name"
    elif [ "$auth" = "bearer" ] && [ -n "$bearer_env" ]; then
      if [ -n "${!bearer_env:-}" ]; then
        log_ok "$name auth env present: $bearer_env"
      else
        log_warn "$name requires env var $bearer_env"
        log_info "Export $bearer_env, then retry Codex."
      fi
    fi
  done < <(jq -c '.[]' "$file")

  echo ""
}

echo -e "${BOLD}=== Agent Harness Setup ===${NC}"
echo -e "Repo:   ${DIM}$REPO_DIR${NC}"
echo -e "OS:     ${DIM}$OS${NC}"
echo -e "Claude: ${DIM}$INSTALL_CLAUDE${NC}"
echo -e "Codex:  ${DIM}$INSTALL_CODEX${NC}"
echo -e "OMX:    ${DIM}$INSTALL_OMX${NC}"
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

    MARKETPLACE_DIR="$CLAUDE_DIR/plugins/marketplaces"
    DECLARED_MARKETPLACES=$(printf '%s\n' "$MARKETPLACE_NAMES" | awk '{print $1}')
    REGISTERED_MARKETPLACE_NAMES=$(printf '%s\n' "$REGISTERED_MARKETPLACES" | sed -n 's/^[[:space:]]*❯[[:space:]]*//p')

    while IFS= read -r registered_name; do
      [ -z "$registered_name" ] && continue
      if ! printf '%s\n' "$DECLARED_MARKETPLACES" | grep -qxF "$registered_name"; then
        log_remove "marketplace: $registered_name ..."
        REMOVE_OUTPUT=$(claude plugin marketplace remove "$registered_name" 2>&1) && REMOVE_EXIT=0 || REMOVE_EXIT=$?
        if [ $REMOVE_EXIT -eq 0 ]; then
          log_remove "removed marketplace $registered_name"
        else
          echo "$REMOVE_OUTPUT" | sed 's/^/    /'
          log_warn "Failed to remove marketplace $registered_name"
        fi
      fi
    done <<< "$REGISTERED_MARKETPLACE_NAMES"

    if [ -d "$MARKETPLACE_DIR" ]; then
      for registered_dir in "$MARKETPLACE_DIR"/*; do
        [ -d "$registered_dir" ] || continue
        registered_name="$(basename "$registered_dir")"
        [ -z "$registered_name" ] && continue
        if ! printf '%s\n' "$DECLARED_MARKETPLACES" | grep -qxF "$registered_name"; then
          log_remove "marketplace: $registered_name ..."
          REMOVE_OUTPUT=$(claude plugin marketplace remove "$registered_name" 2>&1) && REMOVE_EXIT=0 || REMOVE_EXIT=$?
          if [ $REMOVE_EXIT -eq 0 ]; then
            log_remove "removed marketplace $registered_name"
          else
            echo "$REMOVE_OUTPUT" | sed 's/^/    /'
            log_warn "Failed to remove marketplace $registered_name"
          fi
        fi
      done
    fi

    # Pull latest for marketplace clones
    if [ -d "$MARKETPLACE_DIR" ]; then
      for mp_name in $DECLARED_MARKETPLACES; do
        mp_dir="$MARKETPLACE_DIR/$mp_name/"
        [ -d "$mp_dir/.git" ] || continue
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

    echo -e "  Plugins: ${GREEN}$INSTALL_COUNT new${NC}, ${DIM}$SKIP_COUNT present${NC}, ${DIM}$REMOVE_COUNT removed${NC}, ${RED}$FAIL_COUNT failed${NC}"
  fi
  echo ""

  # ── OMC Plugin Patches ──
  OMC_CACHE="$CLAUDE_DIR/plugins/cache/omc/oh-my-claudecode"
  OMC_MARKETPLACE="$CLAUDE_DIR/plugins/marketplaces/omc/skills"
  if [ -d "$OMC_CACHE" ] || [ -d "$OMC_MARKETPLACE" ]; then
    log_section "  OMC Plugin Patches..."

    # deep-interview: lower ambiguity threshold 0.2 → 0.1
    PATCHED=0
    SEARCH_DIRS=""
    [ -d "$OMC_CACHE" ] && SEARCH_DIRS="$OMC_CACHE"
    [ -d "$OMC_MARKETPLACE" ] && SEARCH_DIRS="$SEARCH_DIRS $OMC_MARKETPLACE"
    while IFS= read -r skill_file; do
      [ -z "$skill_file" ] && continue
      if grep -qE '"threshold":[[:space:]]*0\.2|"ambiguityThreshold":[[:space:]]*0\.2|\(default:? 0\.2\)|below 20%|≤ ?20%' "$skill_file"; then
        sed_inplace 's/"threshold": 0\.2/"threshold": 0.1/' "$skill_file"
        sed_inplace 's/(default 0\.2)/(default 0.1)/' "$skill_file"
        sed_inplace 's/(default: 20%)/(default: 10%)/' "$skill_file"
        sed_inplace 's/below 20%/below 10%/g' "$skill_file"
        sed_inplace 's/"ambiguityThreshold": 0\.2/"ambiguityThreshold": 0.1/' "$skill_file"
        sed_inplace 's/≤ 20%/≤ 10%/g' "$skill_file"
        sed_inplace 's/≤20%/≤10%/g' "$skill_file"
        log_ok "deep-interview threshold: 0.2 → 0.1"
        PATCHED=1
      else
        log_skip "deep-interview threshold already patched"
      fi
    done < <(find $SEARCH_DIRS -path "*/deep-interview/SKILL.md" 2>/dev/null)

    if [ "$PATCHED" -eq 0 ] && ! find $SEARCH_DIRS -path "*/deep-interview/SKILL.md" -print -quit 2>/dev/null | grep -q .; then
      log_skip "deep-interview SKILL.md not found in cache"
    fi
    echo ""
  fi
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

  mkdir -p "$CODEX_DIR/hooks" "$CODEX_DIR/skills"

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

  # 1. Remove global model pinning (let Codex use its own default)
  REMOVED_MODEL=false
  if grep -q '^model ' "$CONFIG_TOML" || grep -q '^model_reasoning_effort' "$CONFIG_TOML"; then
    python3 - "$CONFIG_TOML" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path).readlines()
out, in_section = [], False
for line in lines:
    if line.strip().startswith('['):
        in_section = True
    if not in_section and (line.startswith('model ') or line.startswith('model_reasoning_effort')):
        continue
    out.append(line)
open(path, 'w').writelines(out)
PYEOF
    log_ok "removed global model/model_reasoning_effort (let Codex decide)"
    REMOVED_MODEL=true
  fi
  if [ "$REMOVED_MODEL" = false ]; then
    log_skip "global model pinning already absent"
  fi

  # 2. Remove model_instructions_file (migrated to AGENTS.md)
  if grep -q 'model_instructions_file' "$CONFIG_TOML"; then
    sed_inplace '/^model_instructions_file/d' "$CONFIG_TOML"
    log_ok "removed model_instructions_file (migrated to AGENTS.md)"
  else
    log_skip "model_instructions_file already absent"
  fi

  # 3. Enable codex_hooks feature (also fix false → true)
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

  # 4. Merge [profiles.harness] block (remove old, append new)
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

  # 5. Trust this harness repo to avoid repeated workspace trust prompts
  TRUST_STATUS=$(python3 - "$CONFIG_TOML" "$REPO_DIR" <<'PYEOF'
import json
import sys

path, repo_dir = sys.argv[1], sys.argv[2]
target_header = f'[projects.{json.dumps(repo_dir)}]'
lines = open(path).read().splitlines(True)

section_start = None
section_end = None
for i, line in enumerate(lines):
    if line.strip() == target_header:
        section_start = i
        section_end = len(lines)
        for j in range(i + 1, len(lines)):
            if lines[j].strip().startswith('['):
                section_end = j
                break
        break

if section_start is None:
    if lines and lines[-1].strip():
        lines.append('\n')
    lines.append(f'{target_header}\n')
    lines.append('trust_level = "trusted"\n')
    open(path, 'w').writelines(lines)
    print('added')
    raise SystemExit

trust_idx = None
trust_value = None
for idx in range(section_start + 1, section_end):
    stripped = lines[idx].strip()
    if stripped.startswith('trust_level'):
        trust_idx = idx
        _, _, value = stripped.partition('=')
        trust_value = value.strip().strip('"').strip("'")
        break

if trust_value == 'trusted':
    print('already')
elif trust_idx is not None:
    lines[trust_idx] = 'trust_level = "trusted"\n'
    open(path, 'w').writelines(lines)
    print('updated')
else:
    insert_at = section_start + 1
    while insert_at < section_end and lines[insert_at].strip() == '':
        insert_at += 1
    lines.insert(insert_at, 'trust_level = "trusted"\n')
    open(path, 'w').writelines(lines)
    print('inserted')
PYEOF
)
  case "$TRUST_STATUS" in
    already)  log_skip "repo trust already set for $REPO_DIR" ;;
    added)    log_ok "added repo trust for $REPO_DIR" ;;
    updated)  log_ok "updated repo trust for $REPO_DIR" ;;
    inserted) log_ok "inserted repo trust for $REPO_DIR" ;;
    *)        log_warn "Unable to confirm repo trust status for $REPO_DIR" ;;
  esac
  echo ""

  # ── Skills ──
  if command -v codex &>/dev/null; then
    SKILL_INSTALLER="$CODEX_DIR/skills/.system/skill-installer/scripts/install-skill-from-github.py"
    SKILLS_FILE="$REPO_DIR/codex/skills.txt"

    log_section "  Shared Skills..."
    link_shared_skill_if_present "context7"
    echo ""

    if [ -f "$SKILLS_FILE" ]; then
      log_section "  Skills..."

      if [ -f "$SKILL_INSTALLER" ]; then
        OPENAI_SKILLS_SHA=$(get_remote_sha "openai/skills" "main")
        [ -z "$OPENAI_SKILLS_SHA" ] && log_warn "Could not fetch remote ref for openai/skills — skipping update check"

        while IFS= read -r skill_name; do
          # Skip comments and empty lines
          skill_name="$(echo "$skill_name" | sed 's/#.*//' | xargs)"
          [ -z "$skill_name" ] && continue

          if [ "$skill_name" = "context7" ]; then
            if [ -L "$CODEX_DIR/skills/context7" ] || [ -d "$CODEX_DIR/skills/context7" ]; then
              log_ok "context7 (managed via ~/.agents/skills)"
            else
              log_warn "context7 missing (expected symlink from ~/.agents/skills)"
            fi
            continue
          fi

          SKILL_DIR="$CODEX_DIR/skills/$skill_name"
          if [ -d "$SKILL_DIR" ]; then
            INSTALLED_SHA="$(read_installed_ref "$SKILL_DIR")"
            if [ -z "$OPENAI_SKILLS_SHA" ]; then
              log_ok "$skill_name (already installed)"
              continue
            fi
            if [ "$INSTALLED_SHA" = "$OPENAI_SKILLS_SHA" ]; then
              log_ok "$skill_name (up to date)"
              continue
            fi
            if [ -n "$INSTALLED_SHA" ]; then
              log_action "updating $skill_name (${INSTALLED_SHA:0:7} → ${OPENAI_SKILLS_SHA:0:7}) ..."
            else
              log_action "updating $skill_name (no ref tracked) ..."
            fi
            rm -rf "$SKILL_DIR"
          else
            log_action "installing $skill_name ..."
          fi

          SKILL_OUTPUT=$(python3 "$SKILL_INSTALLER" \
            --repo openai/skills \
            --path "skills/.curated/$skill_name" 2>&1) && SKILL_EXIT=0 || SKILL_EXIT=$?
          if [ $SKILL_EXIT -eq 0 ]; then
            log_ok "installed $skill_name"
            [ -n "$OPENAI_SKILLS_SHA" ] && write_installed_ref "$SKILL_DIR" "$OPENAI_SKILLS_SHA"
          else
            echo "$SKILL_OUTPUT" | sed 's/^/    /'
            log_warn "Failed to install $skill_name"
          fi
        done < "$SKILLS_FILE"
      else
        log_warn "Skill installer not found. Run 'codex' once to initialize, then re-run setup."
      fi
      echo ""
    fi

    # ── External Skills (from external-skills.json) ──
    EXTERNAL_SKILLS_FILE="$REPO_DIR/codex/external-skills.json"
    SKILL_LISTER="$CODEX_DIR/skills/.system/skill-installer/scripts/list-skills.py"
    if [ -f "$EXTERNAL_SKILLS_FILE" ] && [ -f "$SKILL_INSTALLER" ]; then
      log_section "  External Skills..."

      EXT_COUNT=$(jq length "$EXTERNAL_SKILLS_FILE")
      for i in $(seq 0 $((EXT_COUNT - 1))); do
        EXT_REPO=$(jq -r ".[$i].repo" "$EXTERNAL_SKILLS_FILE")
        EXT_REF=$(jq -r ".[$i].ref // \"main\"" "$EXTERNAL_SKILLS_FILE")
        EXT_DISCOVER=$(jq -r ".[$i].discover // empty" "$EXTERNAL_SKILLS_FILE")

        REMOTE_SHA=$(get_remote_sha "$EXT_REPO" "$EXT_REF")
        [ -z "$REMOTE_SHA" ] && log_warn "Could not fetch remote ref for $EXT_REPO — skipping update check"

        # Build skill paths: auto-discover via list-skills.py or use explicit paths
        SKILL_PATHS=""
        if [ -n "$EXT_DISCOVER" ]; then
          if [ -f "$SKILL_LISTER" ]; then
            DISCOVER_OUTPUT=$(python3 "$SKILL_LISTER" \
              --repo "$EXT_REPO" --path "$EXT_DISCOVER" --ref "$EXT_REF" \
              --format json 2>/dev/null) && DISCOVER_EXIT=0 || DISCOVER_EXIT=$?
            if [ $DISCOVER_EXIT -eq 0 ]; then
              SKILL_PATHS=$(echo "$DISCOVER_OUTPUT" | jq -er ".[].name | \"$EXT_DISCOVER/\" + ." 2>/dev/null) || {
                log_warn "Failed to parse discovered skills JSON from $EXT_REPO/$EXT_DISCOVER — skipping"
                continue
              }
            else
              log_warn "Failed to discover skills from $EXT_REPO/$EXT_DISCOVER — skipping"
              continue
            fi
          else
            log_warn "list-skills.py not found — cannot auto-discover from $EXT_REPO"
            continue
          fi
        else
          SKILL_PATHS=$(jq -r ".[$i].paths[]" "$EXTERNAL_SKILLS_FILE")
        fi

        while IFS= read -r skill_path; do
          [ -z "$skill_path" ] && continue
          skill_name="$(basename "$skill_path")"
          SKILL_DIR="$CODEX_DIR/skills/$skill_name"

          if [ -d "$SKILL_DIR" ]; then
            INSTALLED_SHA="$(read_installed_ref "$SKILL_DIR")"
            if [ -z "$REMOTE_SHA" ]; then
              log_ok "$skill_name (already installed from $EXT_REPO)"
              continue
            fi
            if [ "$INSTALLED_SHA" = "$REMOTE_SHA" ]; then
              log_ok "$skill_name (up to date)"
              continue
            fi
            if [ -n "$INSTALLED_SHA" ]; then
              log_action "updating $skill_name (${INSTALLED_SHA:0:7} → ${REMOTE_SHA:0:7}) ..."
            else
              log_action "updating $skill_name (no ref tracked) ..."
            fi
            rm -rf "$SKILL_DIR"
          else
            log_action "installing $skill_name from $EXT_REPO ..."
          fi

          SKILL_OUTPUT=$(python3 "$SKILL_INSTALLER" \
            --repo "$EXT_REPO" \
            --ref "$EXT_REF" \
            --path "$skill_path" \
            --name "$skill_name" 2>&1) && SKILL_EXIT=0 || SKILL_EXIT=$?
          if [ $SKILL_EXIT -eq 0 ]; then
            log_ok "installed $skill_name"
            [ -n "$REMOTE_SHA" ] && write_installed_ref "$SKILL_DIR" "$REMOTE_SHA"
          else
            echo "$SKILL_OUTPUT" | sed 's/^/    /'
            log_warn "Failed to install $skill_name from $EXT_REPO"
          fi
        done <<< "$SKILL_PATHS"
      done
      echo ""
    elif [ -f "$EXTERNAL_SKILLS_FILE" ] && [ ! -f "$SKILL_INSTALLER" ]; then
      log_warn "External skills declared but skill installer not found. Run 'codex' once first."
    fi

    sync_codex_mcp_servers "$CODEX_MCP_FILE" "$CONFIG_TOML"
  fi
fi

# ══════════════════════════════════════════
# OH-MY-CODEX CLI
# ══════════════════════════════════════════
if [ "$INSTALL_OMX" = true ]; then
  log_section "[oh-my-codex] Installing CLI..."

  if ! command -v npm &>/dev/null; then
    log_warn "npm not found. Skipping oh-my-codex install."
    log_info "Install Node.js/npm first, then run: ./setup.sh --install-omx"
    echo ""
  else
    OMX_INSTALL_OUTPUT=$(npm install -g oh-my-codex 2>&1) && OMX_INSTALL_EXIT=0 || OMX_INSTALL_EXIT=$?
    if [ $OMX_INSTALL_EXIT -eq 0 ]; then
      log_ok "oh-my-codex CLI installed/updated"
    else
      echo "$OMX_INSTALL_OUTPUT" | sed 's/^/    /'
      log_warn "Failed to install oh-my-codex CLI"
    fi

    if command -v omx &>/dev/null; then
      log_ok "omx: $(omx --version 2>/dev/null || echo 'found')"
    else
      log_warn "omx command not found after install"
    fi
    echo ""
  fi
fi

if [ "$INSTALL_CLAUDE" = true ] || [ "$INSTALL_CODEX" = true ]; then
  install_dev_browser_cli
fi

# ══════════════════════════════════════════
# GLOBAL GITIGNORE (AI tool runtime dirs)
# ══════════════════════════════════════════
log_section "[Git] Global gitignore..."

GLOBAL_GITIGNORE="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
mkdir -p "$(dirname "$GLOBAL_GITIGNORE")"
touch "$GLOBAL_GITIGNORE"

for pattern in ".omc/" ".omx/"; do
  if grep -qxF "$pattern" "$GLOBAL_GITIGNORE"; then
    log_skip "$pattern already in global gitignore"
  else
    echo "$pattern" >> "$GLOBAL_GITIGNORE"
    log_ok "added $pattern to global gitignore"
  fi
done
echo ""

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

RC_CHANGED=false

if [ -n "$RC_FILE" ]; then
  touch "$RC_FILE"

  # Remove old claude-config block
  if grep -qF "$OLD_MARKER_BEGIN" "$RC_FILE" 2>/dev/null; then
    sed_inplace "/$OLD_MARKER_BEGIN/,/$OLD_MARKER_END/d" "$RC_FILE"
    log_ok "removed old claude-config block"
    RC_CHANGED=true
  fi

  # Remove old source line if present
  if grep -qE '^# Claude Code config$|source.*shell/claude\.sh' "$RC_FILE" 2>/dev/null; then
    sed_inplace '/^# Claude Code config$/d; \|source.*shell/claude\.sh|d' "$RC_FILE" 2>/dev/null || true
    RC_CHANGED=true
  fi

  # Extract existing block content for comparison
  EXISTING_BLOCK=""
  if grep -qF "$NEW_MARKER_BEGIN" "$RC_FILE" 2>/dev/null; then
    EXISTING_BLOCK=$(sed -n "/$NEW_MARKER_BEGIN/,/$NEW_MARKER_END/p" "$RC_FILE")
  fi

  if [ "$EXISTING_BLOCK" = "$NEW_BLOCK" ]; then
    log_ok "shell functions already up to date in $RC_FILE"
  else
    # Remove existing harness block (for re-runs)
    if grep -qF "$NEW_MARKER_BEGIN" "$RC_FILE" 2>/dev/null; then
      sed_inplace "/$NEW_MARKER_BEGIN/,/$NEW_MARKER_END/d" "$RC_FILE"
    fi

    # Clean trailing blank lines and append new block
    perl -i -0777pe 's/\n+$/\n/' "$RC_FILE"
    echo "" >> "$RC_FILE"
    echo "$NEW_BLOCK" >> "$RC_FILE"
    log_ok "shell functions written to $RC_FILE"
    RC_CHANGED=true
  fi
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
  log_warn "node not installed (required by Claude Code plugins / oh-my-codex)"
else
  log_ok "node: $(node --version)"
fi

if command -v omx &>/dev/null; then
  log_ok "oh-my-codex: $(omx --version 2>/dev/null || echo 'installed')"
else
  log_info "oh-my-codex CLI optional: ./setup.sh --install-omx"
fi

if ! command -v tmux &>/dev/null; then
  log_warn "tmux not installed (required by claude-team / omx team mode)"
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
if [ "$INSTALL_OMX" = true ] && ! command -v omx &>/dev/null; then
  echo -e "  ${RED}${BOLD}[ACTION REQUIRED]${NC} oh-my-codex CLI not installed:"
  echo -e "    ${BOLD}npm install -g oh-my-codex${NC}"
  echo ""
  MISSING_CLI=true
fi
if ! command -v omx &>/dev/null; then
  echo -e "  ${YELLOW}${BOLD}[RECOMMENDED]${NC} oh-my-codex CLI is not installed:"
  echo -e "    ${BOLD}./setup.sh --install-omx${NC}"
  echo -e "    or ${BOLD}npm install -g oh-my-codex${NC}"
  echo -e "    ${DIM}Install the CLI globally, then use it only per project with:${NC} ${BOLD}omx setup --scope project${NC}"
  echo ""
fi

if [ "$MISSING_CLI" = false ]; then
  echo -e "  ${DIM}All tools configured. No further action needed.${NC}"
  echo ""
fi

if command -v omx &>/dev/null; then
  echo -e "  ${DIM}OMX policy:${NC} keep ${BOLD}~/.codex${NC} managed by this harness."
  echo -e "  ${DIM}Use OMX only per project:${NC} ${BOLD}cd <project> && omx setup --scope project${NC}"
  echo -e "  ${DIM}Avoid:${NC} ${BOLD}omx setup --scope user${NC}"
  echo ""
fi

if [ "$RC_CHANGED" = true ]; then
  echo -e "${DIM}Run 'source ${RC_FILE:-~/.zshrc}' or open a new terminal to apply changes.${NC}"
fi
