#!/bin/bash
# npm global install location helpers.
# System Node (apt/yum) puts the npm global prefix at /usr, which a non-root
# account cannot write, so `npm install -g` fails with EACCES on shared servers.
# Requires shared/lib/os.sh (log_*) to be sourced first.
# See docs/decisions/2026-10-npm-user-prefix.md

NPM_USER_PREFIX="$HOME/.npm-global"

# Succeeds when `npm install -g` can write to the current global prefix.
# Checks the nearest existing ancestor of <prefix>/lib/node_modules, since a
# fresh prefix may not have created that directory yet.
npm_global_prefix_writable() {
  local prefix target
  prefix="$(npm config get prefix 2>/dev/null)" || return 1
  [ -n "$prefix" ] || return 1
  target="$prefix/lib/node_modules"
  while [ ! -e "$target" ] && [ "$target" != "/" ]; do
    target="$(dirname "$target")"
  done
  [ -w "$target" ]
}

# Point npm's global prefix at $NPM_USER_PREFIX when the current one is not
# writable, and expose its bin dir to the rest of this process. A writable
# prefix (Homebrew, nvm, an existing user prefix) is left untouched.
ensure_npm_user_prefix() {
  if ! command -v npm >/dev/null 2>&1; then
    log_skip "npm not found — skipping global prefix check"
    return 0
  fi

  if npm_global_prefix_writable; then
    log_skip "npm global prefix writable: $(npm config get prefix)"
  else
    local old_prefix
    old_prefix="$(npm config get prefix 2>/dev/null)"
    # Create bin/ up front: npm only makes it on the first install, and
    # init.sh adds it to PATH only when it exists.
    mkdir -p "$NPM_USER_PREFIX/bin"
    npm config set prefix "$NPM_USER_PREFIX"
    log_ok "npm global prefix $old_prefix is not writable — switched to $NPM_USER_PREFIX"
  fi

  case ":$PATH:" in
    *":$NPM_USER_PREFIX/bin:"*) ;;
    *) [ -d "$NPM_USER_PREFIX/bin" ] && export PATH="$NPM_USER_PREFIX/bin:$PATH" ;;
  esac
  return 0
}
