#!/bin/sh
# Apply the protected record through the Haskell lifecycle, then checked startup.
set -eu
[ "$#" = 0 ] || { echo 'Usage: sudo ./build/update-config.sh' >&2; exit 1; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
exec sh "$root/build/install.sh" --update-config
