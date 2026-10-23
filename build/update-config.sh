#!/bin/sh
# Allow edited installation inputs only before any wallet setup exists.
set -eu
umask 077
[ "$(id -u)" = 0 ] && [ "$#" = 0 ] || { echo 'Usage: sudo ./build/update-config.sh' >&2; exit 1; }
state=/var/lib/hot-wallet-server
[ -d "$state" ] && [ ! -L "$state" ] &&
  [ "$(stat -c '%u:%a' "$state")" = 0:700 ] || {
    echo 'Missing or unsafe installation directory.' >&2; exit 1;
  }
cd "$state"
exec 9>install.lock
flock -n 9 || { echo 'Another installation is running.' >&2; exit 1; }
for path in .ecx-bridge .ecx-bridge-keys /etc/ecx-bridge; do
  if [ -e "$path" ] || [ -L "$path" ]; then
    echo 'Wallet setup already exists; configuration preserved. Changing initialized settings requires review.' >&2
    exit 1
  fi
done
if [ -e server.conf ] || [ -L server.conf ]; then
  [ -f server.conf ] && [ ! -L server.conf ] &&
    [ "$(stat -c '%u:%a:%h' server.conf)" = 0:600:1 ] || {
      echo 'Unsafe saved configuration; refusing changes.' >&2; exit 1;
    }
  backup=$(mktemp -d ./config-backup.XXXXXXXX)
  mv server.conf "$backup/server.conf"
fi
echo 'Ready to accept edited configuration. Rerun the installer.'
