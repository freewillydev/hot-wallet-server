#!/bin/sh
# Single unattended entry point. The Haskell record is never sourced or eval'd.
set -eu
umask 077
[ "$(id -u)" = 0 ] || { echo 'Run install.sh as root on the target Ubuntu server.' >&2; exit 1; }
[ "$#" -eq 1 ] || { echo 'Usage: sudo ./build/install.sh /absolute/private/server.conf' >&2; exit 1; }
case "$1" in /*) config=$1;; *) echo 'Supply an absolute configuration path.' >&2; exit 1;; esac
. /etc/os-release
[ "$ID:$VERSION_ID" = ubuntu:24.04 ] || { echo 'Ubuntu 24.04 is required.' >&2; exit 1; }
parent=$(dirname -- "$config")
[ -d "$parent" ] && [ ! -L "$parent" ] && [ "$(stat -c '%u:%a' "$parent")" = 0:700 ] || {
  echo 'Configuration directory must be root-owned, mode 700, and not a symlink.' >&2; exit 1;
}
[ -f "$config" ] && [ ! -L "$config" ] || { echo 'Configuration must be a regular, non-symlink file.' >&2; exit 1; }
# Validate the opened file, then copy those same bytes. Close it before any build.
exec 8<"$config"
[ -f "/proc/$$/fd/8" ] && [ "$(stat -Lc '%u:%a:%h' "/proc/$$/fd/8")" = 0:600:1 ] || {
  echo 'Configuration must be root-owned, mode 600, with one hard link.' >&2; exit 1;
}
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
state=/var/lib/hot-wallet-server
if [ -e "$state" ] || [ -L "$state" ]; then
  [ -d "$state" ] && [ ! -L "$state" ] && [ "$(stat -c '%u:%a' "$state")" = 0:700 ] || {
    echo 'Installation state must be a root-owned directory with mode 700, not a symlink.' >&2; exit 1;
  }
else
  install -d -o root -g root -m 0700 "$state"
fi
exec 9>"$state/install.lock"
flock -n 9 || { echo 'Another installation is running.' >&2; exit 1; }
# Publish only a complete bounded copy; an interrupted copy can be retried.
copy=$(mktemp "$state/config.XXXXXXXX")
trap 'rm -f -- "$copy"' EXIT
trap 'exit 1' HUP INT TERM
head -c 8193 <&8 > "$copy"
exec 8<&-
[ -s "$copy" ] && [ "$(wc -c < "$copy")" -le 8192 ] || { echo 'Configuration must contain 1 to 8192 bytes.' >&2; exit 1; }
# Keep the caller's original. Refuse silently replacing a bound installation.
if [ -e "$state/server.conf" ]; then
  [ -f "$state/server.conf" ] && [ ! -L "$state/server.conf" ] &&
    [ "$(stat -c '%u:%a:%h' "$state/server.conf")" = 0:600:1 ] || {
      echo 'Saved configuration has unsafe ownership, permissions or links.' >&2; exit 1;
    }
  cmp -s "$copy" "$state/server.conf" || { echo 'Configuration differs from saved installation; reviewed update required.' >&2; exit 1; }
  rm -f -- "$copy"
else
  [ ! -L "$state/server.conf" ] || { echo 'Saved configuration must not be a symlink.' >&2; exit 1; }
  mv -T -- "$copy" "$state/server.conf"
fi
trap - EXIT HUP INT TERM
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
# Freeze one commit, and finish its archive before extracting anything. A new
# commit gets a clean tree; retries reuse only a completely extracted tree.
commit=$(git -c safe.directory="$root" -C "$root" rev-parse --verify 'HEAD^{commit}')
source="$buildhome/source-$commit"
archive=$(mktemp "$state/source.XXXXXXXX")
trap 'rm -f -- "$archive"' EXIT
trap 'exit 1' HUP INT TERM
git -c safe.directory="$root" -C "$root" archive --format=tar "$commit" src Docs build LICENSE > "$archive"
# Only the build user writes inside its home, including extraction and cleanup.
runuser -u "$account" -- sh -c '
  set -eu
  umask 077
  source=$1
  commit=$2
  if [ -e "$source" ] || [ -L "$source" ]; then
    [ -d "$source" ] && [ ! -L "$source" ] &&
      [ -f "$source/source-commit" ] && [ ! -L "$source/source-commit" ] &&
      [ "$(cat "$source/source-commit")" = "$commit" ] || {
        echo "Incomplete or mismatched source tree; refusing to build." >&2; exit 1;
      }
    exit 0
  fi
  temporary=$(mktemp -d "$source.XXXXXXXX")
  trap '\''rm -rf -- "$temporary"'\'' EXIT
  trap '\''exit 1'\'' HUP INT TERM
  tar -C "$temporary" -xf -
  printf "%s\n" "$commit" > "$temporary/source-commit"
  mv -T -- "$temporary" "$source"
  trap - EXIT
' sh "$source" "$commit" < "$archive"
rm -f -- "$archive"
trap - EXIT HUP INT TERM
runuser -u "$account" -- sh "$source/build/install/toolchain"
binary=$(runuser -u "$account" -- sh -c 'cd "$1"; export PATH="$HOME/.ghcup/bin:$HOME/.cargo/bin:$PATH"; ghcup run --ghc 9.14.1 --cabal 3.16.1.0 -- cabal --project-dir=build list-bin exe:ecx-bridge' sh "$source")
[ -x "$binary" ] || { echo 'Cabal did not produce the server executable.' >&2; exit 1; }
"$binary" configure-file "$state/server.conf" "$state/.ecx-bridge" </dev/null
"$binary" start "$state/.ecx-bridge" </dev/null
