#!/bin/bash
# Raise the egress firewall (root, via the single sudoers entry), then prepare
# the runtime for a headless session, then run the requested command as the
# unprivileged agent user.
set -e

if [[ "${AGENT_SKIP_FIREWALL:-0}" != "1" ]]; then
  if ! sudo /usr/local/bin/init-firewall.sh; then
    echo "firewall setup failed — the container must run with" >&2
    echo "  --cap-add NET_ADMIN --cap-add NET_RAW" >&2
    echo "(agents/agent passes these; add them to any other runner)" >&2
    exit 1
  fi
fi

# The workspace is a bind mount owned by the host user, not us; without this
# git refuses every operation with "detected dubious ownership".
git config --global --add safe.directory '*'

# Pre-trust the mounted workspace and bypassPermissions mode — headless runs
# cannot answer first-use dialogs.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json"
mkdir -p "$(dirname "$CFG")"
[[ -s "$CFG" ]] || echo '{}' > "$CFG"
tmp="$(mktemp)"
jq --arg p "$PWD" \
  '.projects[$p].hasTrustDialogAccepted = true | .bypassPermissionsModeAccepted = true' \
  "$CFG" > "$tmp" && mv "$tmp" "$CFG"

exec "$@"
