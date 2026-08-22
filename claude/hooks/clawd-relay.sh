#!/usr/bin/env bash
# Clawd on Desk relay — harness-owned wrapper around Clawd's hook runtime.
#
# Why a wrapper: Clawd's installer (hooks/install.js) rewrites any settings.json
# hook whose command contains "clawd-hook.js" to its own absolute-path form and
# replaces the file via rename(), which breaks the harness symlink. Keeping the
# literal "clawd-hook.js" out of claude/settings.json and resolving everything
# here at runtime lets the harness stay the single owner of settings.json.
# Clawd's local auto-management must stay OFF (Settings → Agents → Claude Code).
# Decision record: docs/decisions/2026-08-clawd-on-desk-hooks.md
#
# Usage: clawd-relay.sh <HookEventName>   (stdin = Claude Code hook JSON)
#        clawd-relay.sh --mode             (prints remote|local|none; used by check.sh)
# Always exits 0 and prints nothing when Clawd is not deployed on this machine.

EVENT="${1:-}"
HOOKS_DIR="$HOME/.claude/hooks"          # Clawd runtime files live here (not CLAUDE_CONFIG_DIR)
REMOTE_IDENTITY="$HOOKS_DIR/clawd-remote.json"
LOCAL_APP_HOOK="/Applications/Clawd on Desk.app/Contents/Resources/app.asar.unpacked/hooks/clawd-hook.js"
LOCAL_PORT=23333
LOCAL_RUNTIME="$HOME/.clawd/runtime.json"  # desktop Clawd records the port it actually bound (pretty JSON)

drain_stdin() { cat >/dev/null 2>&1 || :; }

find_node() {
  local n
  n="$(command -v node 2>/dev/null)" && { echo "$n"; return 0; }
  for n in /usr/local/bin/node /opt/homebrew/bin/node "$HOME"/.nvm/versions/node/*/bin/node; do
    [ -x "$n" ] && { echo "$n"; return 0; }
  done
  return 1
}

json_field() {  # json_field <file> <key>  — jq, same dependency as every other hook here
  jq -r --arg k "$2" '.[$k] // empty' "$1" 2>/dev/null
}

# ---- resolve deployment mode -------------------------------------------------
MODE=""
if [ -f "$REMOTE_IDENTITY" ] && [ -f "$HOOKS_DIR/clawd-hook.js" ]; then
  MODE="remote"   # this machine is an SSH remote deployed from a desktop Clawd
elif [ "$(uname -s)" = "Darwin" ] && [ -f "$LOCAL_APP_HOOK" ]; then
  MODE="local"    # desktop Clawd app installed here
fi
if [ "$EVENT" = "--mode" ]; then printf '%s\n' "${MODE:-none}"; exit 0; fi
[ -n "$MODE" ] || { drain_stdin; exit 0; }

# ---- PermissionRequest: relay stdin to Clawd's permission endpoint ------------
# Mirrors Claude Code's "http" hook semantics: POST the hook JSON, echo the
# response body (same decision schema). Any failure → empty stdout → native prompt.
# Values read from identity/runtime files are validated before they reach the URL,
# and only a body that actually carries a permission decision is forwarded — the
# loopback port is shared by every user on a multi-user host (see decision record).
if [ "$EVENT" = "PermissionRequest" ]; then
  command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { drain_stdin; exit 0; }
  if [ "$MODE" = "remote" ]; then
    port="$(json_field "$REMOTE_IDENTITY" remotePort)"
    nonce="$(json_field "$REMOTE_IDENTITY" routingNonce)"
    case "$port" in ''|*[!0-9]*) drain_stdin; exit 0 ;; esac
    printf '%s' "$nonce" | grep -Eq '^[a-f0-9]{32}$' || { drain_stdin; exit 0; }   # same rule as Clawd ingress
    url="http://127.0.0.1:${port}/permission/${nonce}"
  else
    port="$([ -f "$LOCAL_RUNTIME" ] && json_field "$LOCAL_RUNTIME" port)"
    case "$port" in ''|*[!0-9]*) port="$LOCAL_PORT" ;; esac
    url="http://127.0.0.1:${port}/permission"
  fi
  body="$(curl -sS --fail --connect-timeout 2 --max-time "${CLAWD_PERMISSION_TIMEOUT:-110}" \
           -H 'Content-Type: application/json' --data-binary @- "$url" 2>/dev/null)" || exit 0
  [ -n "$body" ] && printf '%s' "$body" | jq -e '.hookSpecificOutput.decision? // .decision? | strings' >/dev/null 2>&1 \
    && printf '%s\n' "$body"
  exit 0
fi

# ---- state events: hand off to Clawd's own hook script -----------------------
NODE="$(find_node)" || { drain_stdin; exit 0; }
if [ "$MODE" = "remote" ]; then
  CLAWD_REMOTE=1 CLAWD_SSH_REMOTE=1 \
  CLAWD_REMOTE_IDENTITY_PATH="$REMOTE_IDENTITY" \
  CLAWD_SSH_SECURE_MARKER_PATH="$HOOKS_DIR/clawd-ssh-secure-v1" \
  CLAWD_HOST_PREFIX_PATH="$HOOKS_DIR/clawd-host-prefix" \
  CLAWD_REMOTE_LAST_LOG_PATH="$HOME/.clawd/remote-last-error.log" \
  CLAWD_STATUSLINE_SIDECAR_PATH="$HOOKS_DIR/clawd-statusline-chain.json" \
  exec "$NODE" "$HOOKS_DIR/clawd-hook.js" "$EVENT"
else
  exec "$NODE" "$LOCAL_APP_HOOK" "$EVENT"
fi
