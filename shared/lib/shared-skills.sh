#!/usr/bin/env bash
# Shared (cross-agent) skills declared in shared/skills.json.
#
# Each entry is a GitHub repo that ships a SKILL.md directory. The repo is
# cloned persistently under ${XDG_DATA_HOME:-$HOME/.local/share}/<repo-name>
# and exposed by symlink to every agent:
#   ~/.agents/skills/<name>            (Codex reads this natively; also the
#                                       source for $CODEX_SKILLS_DIR/<name>)
#   $CLAUDE_DIR/skills/<name>          (personal account)
#   $CLAUDE_UP_DIR/skills/<name>       (work account)
#
# Symlinks (not copies) are required: these skills locate their own scripts
# relative to the clone and are updated with a fast-forward pull.
# See docs/decisions/2026-08-gpt-image-shared-skill.md
#
# Expects: REPO_DIR, AGENTS_DIR, log_* helpers, link_file (shared/lib/os.sh), jq.

SHARED_SKILLS_FILE="$REPO_DIR/shared/skills.json"
SHARED_SKILLS_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Print "name|repo|ref|path|node_min" per declared skill.
shared_skill_entries() {
  [ -f "$SHARED_SKILLS_FILE" ] || return 0
  jq -r '.[] | [.name, .repo, (.ref // "main"), (.path // "."), (.node_min // 0 | tostring)] | join("|")' \
    "$SHARED_SKILLS_FILE" 2>/dev/null
}

shared_skill_clone_dir() {
  echo "$SHARED_SKILLS_DATA_HOME/$(basename "$1")"
}

# Warn (never fail) when the local node is older than the skill's minimum.
shared_skill_check_node() {
  local name="$1" node_min="$2"
  [ "$node_min" -gt 0 ] 2>/dev/null || return 0
  if ! command -v node &>/dev/null; then
    log_warn "$name needs Node.js >= $node_min but node is not on PATH (skill links are installed; generation will fail until node is available)"
    return 0
  fi
  local major
  major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  if [ -z "$major" ] || [ "$major" -lt "$node_min" ] 2>/dev/null; then
    log_warn "$name needs Node.js >= $node_min (found $(node --version 2>/dev/null)); with nvm: nvm alias default $node_min"
  fi
}

# Clone or fast-forward one skill repo. Never discards local changes.
shared_skill_sync_clone() {
  local name="$1" repo="$2" ref="$3" clone_dir="$4"
  if [ ! -d "$clone_dir/.git" ]; then
    if [ -e "$clone_dir" ]; then
      log_warn "$name: $clone_dir exists but is not a git clone — leaving it untouched"
      return 1
    fi
    if git clone -q --branch "$ref" "https://github.com/$repo.git" "$clone_dir" 2>/dev/null; then
      log_ok "$name: cloned $repo@$ref -> $clone_dir"
    else
      log_warn "$name: clone of $repo failed (offline?) — skipping"
      return 1
    fi
    return 0
  fi
  local origin
  origin="$(git -C "$clone_dir" remote get-url origin 2>/dev/null)"
  case "$origin" in
    *"github.com/$repo"*|*"github.com:$repo"*) ;;
    *) log_warn "$name: $clone_dir tracks '$origin', not $repo — leaving it untouched"; return 1 ;;
  esac
  if [ -n "$(git -C "$clone_dir" status --porcelain 2>/dev/null)" ]; then
    log_warn "$name: local changes in $clone_dir — skipping update"
    return 0
  fi
  if git -C "$clone_dir" pull -q --ff-only origin "$ref" 2>/dev/null; then
    log_ok "$name: up to date ($(git -C "$clone_dir" rev-parse --short HEAD))"
  else
    log_warn "$name: fast-forward update failed — keeping current checkout"
  fi
  return 0
}

# Install every declared shared skill: clone + ~/.agents/skills link + Claude links.
# $@: Claude config dirs to link into.
install_shared_skills() {
  [ -f "$SHARED_SKILLS_FILE" ] || return 0
  if ! command -v jq &>/dev/null; then
    log_warn "jq missing — cannot read shared/skills.json"
    return 0
  fi
  local name repo ref path node_min clone_dir src dir
  while IFS='|' read -r name repo ref path node_min; do
    [ -z "$name" ] && continue
    clone_dir="$(shared_skill_clone_dir "$repo")"
    shared_skill_sync_clone "$name" "$repo" "$ref" "$clone_dir" || continue
    src="$clone_dir/$path"
    if [ ! -f "$src/SKILL.md" ]; then
      log_warn "$name: $src/SKILL.md not found — skipping links"
      continue
    fi
    mkdir -p "$AGENTS_DIR/skills"
    link_file "$src" "$AGENTS_DIR/skills/$name"
    for dir in "$@"; do
      mkdir -p "$dir/skills"
      link_file "$src" "$dir/skills/$name"
    done
    shared_skill_check_node "$name" "$node_min"
  done < <(shared_skill_entries)
}

# Verify one declared shared skill (for check.sh). Uses check_symlink/log_* from caller.
# $@: Claude config dirs (label:dir pairs are not needed; dirs only).
check_shared_skills() {
  [ -f "$SHARED_SKILLS_FILE" ] || return 0
  command -v jq &>/dev/null || { log_warn "jq missing — cannot verify shared/skills.json"; WARNINGS=$((WARNINGS + 1)); return 0; }
  local name repo ref path node_min clone_dir src dir
  while IFS='|' read -r name repo ref path node_min; do
    [ -z "$name" ] && continue
    clone_dir="$(shared_skill_clone_dir "$repo")"
    src="$clone_dir/$path"
    if [ -f "$src/SKILL.md" ]; then
      log_ok "shared skill $name: clone at $clone_dir"
    else
      log_error "shared skill $name: clone missing at $clone_dir (run ./setup.sh)"
      ERRORS=$((ERRORS + 1))
      continue
    fi
    check_symlink "$AGENTS_DIR/skills/$name" "$src" "shared skill $name: ~/.agents/skills"
    for dir in "$@"; do
      check_symlink "$dir/skills/$name" "$src" "shared skill $name: $dir/skills"
    done
    if [ "$node_min" -gt 0 ] 2>/dev/null; then
      local major
      major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
      if [ -n "$major" ] && [ "$major" -ge "$node_min" ] 2>/dev/null; then
        log_ok "shared skill $name: node $(node --version) >= $node_min"
      else
        log_warn "shared skill $name: needs Node.js >= $node_min (found ${major:-none})"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done < <(shared_skill_entries)
}
