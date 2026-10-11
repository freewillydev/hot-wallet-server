#!/bin/sh
# Authenticate a release, then enter the existing checkpointed upgrade lifecycle.
set -eu
umask 077
[ "$(id -u)" = 0 ] || { echo 'Run update.sh with sudo.' >&2; exit 1; }
[ "$#" = 0 ] || {
  echo 'Usage: sudo ./build/update.sh (reads /root/hot-wallet/server.conf)' >&2
  exit 1
}
[ -f /etc/ecx-bridge/installed ] || { echo 'No installed server; use the installer first.' >&2; exit 1; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
settings=$(/opt/ecx-bridge/current/bin/ecx-bridge update-settings /root/hot-wallet/server.conf)
key=$(printf '%s' "$settings" | jq -er .publicKey)
release=$(printf '%s' "$settings" | jq -er .release)
setup=$(printf '%s' "$settings" | jq -er .setup)
# release-auth executes a private snapshot of the signed bytes, not the caller's
# mutable download. The key must be trusted independently of that download.
exec python3 "$root/scripts/release-auth" install "$key" "$release" "$(uname -m)" -- update "$setup"
