#!/bin/sh
# Authenticate a release, then enter the existing checkpointed upgrade lifecycle.
set -eu
umask 077
[ "$(id -u)" = 0 ] || { echo 'Run update.sh with sudo.' >&2; exit 1; }
[ "$#" = 3 ] || {
  echo 'Usage: sudo ./build/update.sh TRUSTED_PUBLIC_KEY RELEASE_DIRECTORY ORIGINAL_SETUP_DIRECTORY' >&2
  exit 1
}
for path in "$@"; do
  case "$path" in /*) ;; *) echo 'Use absolute paths for all three arguments.' >&2; exit 1;; esac
done
[ -f /etc/ecx-bridge/installed ] || { echo 'No installed server; use the installer first.' >&2; exit 1; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# release-auth executes a private snapshot of the signed bytes, not the caller's
# mutable download. The key must be trusted independently of that download.
exec python3 "$root/scripts/release-auth" install "$1" "$2" "$(uname -m)" -- update "$3"
