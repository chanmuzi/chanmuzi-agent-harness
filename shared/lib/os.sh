#!/bin/bash
# Cross-platform helpers for macOS (BSD) and Linux (GNU)

OS="$(uname -s)"

# Colors (auto-disable if output is not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; DIM=''; NC=''
fi

log_ok()      { echo -e "  ${GREEN}[ok]${NC} $*"; }
log_warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "  ${RED}[ERROR]${NC} $*"; }
log_info()    { echo -e "  ${BLUE}[info]${NC} $*"; }
log_skip()    { echo -e "  ${DIM}[skip]${NC} $*"; }
log_action()  { echo -e "  ${BLUE}[->]${NC} $*"; }
log_remove()  { echo -e "  ${RED}[-]${NC} $*"; }
log_section() { echo -e "${BOLD}$*${NC}"; }

# Cross-platform readlink -f (macOS lacks GNU readlink -f)
resolve_path() {
  local target="$1"
  while [ -L "$target" ]; do
    local dir
    dir="$(cd "$(dirname "$target")" && pwd -P)"
    target="$(readlink "$target")"
    [[ "$target" != /* ]] && target="$dir/$target"
  done
  cd "$(dirname "$target")" 2>/dev/null && echo "$(pwd -P)/$(basename "$target")"
}

# Cross-platform sed in-place (macOS BSD sed vs GNU sed)
sed_inplace() {
  if [ "$OS" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Cross-platform sound playback with fallback chain
play_sound() {
  local sound_file="${1:-}"
  local volume="${2:-0.2}"

  if [ "$OS" = "Darwin" ]; then
    if [ -n "$sound_file" ] && [ -f "$sound_file" ]; then
      afplay -v "$volume" "$sound_file" >/dev/null 2>&1 || true
    else
      afplay -v "$volume" /System/Library/Sounds/Pop.aiff >/dev/null 2>&1 || true
    fi
  elif [ -n "$sound_file" ] && [ -f "$sound_file" ] && command -v paplay &>/dev/null; then
    paplay "$sound_file" 2>/dev/null || true
  elif [ -n "$sound_file" ] && [ -f "$sound_file" ] && command -v aplay &>/dev/null; then
    aplay "$sound_file" 2>/dev/null || true
  else
    # Hooks may require structured stdout, so emit the terminal bell on stderr.
    printf '\a' >&2
  fi

  return 0
}

# Per-user private path for transient hook state (e.g. debounce timestamps).
# Hardens against symlink/ownership attacks on a shared /tmp: the state dir is
# created 0700 and owned by the current user, and a hijacked state path
# (a symlink, or a file owned by someone else) is refused.
# Usage: f="$(harness_state_file <name>)" || exit 0
harness_state_file() {
  local name="${1:?harness_state_file: name required}"
  local base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  local dir="$base/chanmuzi-agent-harness-$(id -u)"

  mkdir -p "$dir" 2>/dev/null || return 1
  chmod 700 "$dir" 2>/dev/null || true
  # Refuse a hijacked state dir (symlink, not a real dir, or not owned by us).
  [ -L "$dir" ] && return 1
  [ -d "$dir" ] || return 1
  [ -O "$dir" ] || return 1

  local f="$dir/$name"
  # Refuse a hijacked state file (symlink, or pre-existing and owned by another).
  [ -L "$f" ] && return 1
  if [ -e "$f" ] && [ ! -O "$f" ]; then
    return 1
  fi

  printf '%s\n' "$f"
}

# Symlink helper: backup existing file, create symlink
link_file() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    log_warn "backup: $dst -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi
  ln -s "$src" "$dst"
  log_ok "linked: $dst -> $src"
}
