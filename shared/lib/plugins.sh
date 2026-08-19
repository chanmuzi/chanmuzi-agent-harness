#!/bin/bash
# Claude plugin cache helpers shared by setup.sh (prune) and check.sh (report).
#
# ~/.claude-upstage/plugins is a symlink to ~/.claude/plugins, so
# installed_plugins.json records installPath under whichever config dir the CLI
# session happened to use. Both spellings name the same physical directory, and
# a plain string compare judges a live cache entry stale — which made the prune
# delete plugins that were actually loaded.
# Always compare physical paths.
# See docs/decisions/2026-08-plugin-cache-path-normalization.md
#
# Requires shared/lib/os.sh (resolve_path) to be sourced first.

# Physical path of an existing plugin cache dir; "" when it does not exist.
plugin_cache_realpath() {
  local path="$1"
  [ -n "$path" ] || return 0
  [ -e "$path" ] || return 0
  resolve_path "$path" 2>/dev/null || true
}

# Live cache directories from installed_plugins.json, one physical path per line.
# Entries whose installPath no longer exists are dropped: they cannot match a
# directory on disk anyway, and keeping them would weaken the callers' emptiness
# guard.
plugin_active_cache_paths() {
  local manifest="$1" install_path resolved
  [ -f "$manifest" ] || return 0
  while IFS= read -r install_path; do
    resolved="$(plugin_cache_realpath "$install_path")"
    [ -n "$resolved" ] && printf '%s\n' "$resolved"
  done < <(jq -r \
    '(.plugins // {}) | to_entries[] | .value[]? | .installPath // empty' \
    "$manifest" 2>/dev/null)
}

# Is <version_dir> one of the live cache directories in <active_paths>?
plugin_cache_is_active() {
  local version_dir="$1" active_paths="$2" real_dir
  real_dir="$(plugin_cache_realpath "$version_dir")"
  [ -n "$real_dir" ] || real_dir="$version_dir"
  printf '%s\n' "$active_paths" | grep -qxF "$real_dir"
}
