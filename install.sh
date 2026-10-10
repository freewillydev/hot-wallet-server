#!/bin/sh
# Single unattended entry point. The Haskell record is never sourced or eval'd.
set -eu
umask 077
[ "$(id -u)" = 0 ] || { echo 'Run install.sh as root on the target Ubuntu server.' >&2; exit 1; }
[ "$#" -eq 1 ] || { echo 'Usage: sudo ./install.sh /absolute/private/server.conf' >&2; exit 1; }
case "$1" in /*) config=$1;; *) echo 'Supply an absolute configuration path.' >&2; exit 1;; esac
[ -f "$config" ] && [ ! -L "$config" ] || { echo 'Configuration must be a regular, non-symlink file.' >&2; exit 1; }
[ "$(wc -c < "$config")" -le 8192 ] || { echo 'Configuration is too large.' >&2; exit 1; }
. /etc/os-release
[ "$ID:$VERSION_ID" = ubuntu:24.04 ] || { echo 'Ubuntu 24.04 is required.' >&2; exit 1; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
state=/var/lib/hot-wallet-server
install -d -m 0700 "$state"
# Keep the caller's original. Refuse silently replacing a bound installation.
if [ -e "$state/server.conf" ]; then
  cmp -s "$config" "$state/server.conf" || { echo 'Configuration differs from saved installation; reviewed update required.' >&2; exit 1; }
else
  install -o root -g root -m 0600 "$config" "$state/server.conf"
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential cmake jq curl git pkg-config libpq-dev libgmp-dev libffi-dev zlib1g-dev libssl-dev libncurses-dev xz-utils bzip2 unzip python3 openssl ca-certificates
# Build without root privileges. Toolchain setup is resumable and never sees config.
account=hws-build
if ! getent passwd "$account" >/dev/null; then
  useradd --system --create-home --home-dir /var/lib/hot-wallet-build --shell /bin/sh "$account"
fi
buildhome=$(getent passwd "$account" | cut -d: -f6)
[ "$buildhome" = /var/lib/hot-wallet-build ] || { echo 'Unexpected build account home.' >&2; exit 1; }
# Use an isolated copy; runtime data/private input are excluded even if accidentally nearby.
install -d -o "$account" -g "$account" -m 0750 "$buildhome/source"
git -c safe.directory="$root" -C "$root" archive --format=tar HEAD src docs cabal.project cabal.project.freeze LICENSE install.sh | tar -C "$buildhome/source" -xf -
git -c safe.directory="$root" -C "$root" rev-parse HEAD > "$buildhome/source/source-commit"
chown -R "$account:$account" "$buildhome/source"
runuser -u "$account" -- sh "$buildhome/source/src/install/toolchain"
binary=$(runuser -u "$account" -- sh -c 'cd "$1"; export PATH="$HOME/.ghcup/bin:$HOME/.cargo/bin:$PATH"; ghcup run --ghc 9.14.1 --cabal 3.16.1.0 -- cabal list-bin exe:ecx-bridge' sh "$buildhome/source")
[ -x "$binary" ] || { echo 'Cabal did not produce the server executable.' >&2; exit 1; }
"$binary" configure-file "$state/server.conf" "$state/.ecx-bridge" </dev/null
"$binary" start "$state/.ecx-bridge" </dev/null
