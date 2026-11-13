#!/usr/bin/env bash
# Copy the live mod folder (where the code is edited) into this repository.
# Usage: tools/sync-from-game.sh [path-to-mods/isaac_bot]
set -euo pipefail
SRC="${1:-/c/SteamLibrary/steamapps/common/The Binding of Isaac Rebirth/mods/isaac_bot}"
DST="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$SRC/main.lua" ] || { echo "not a mod folder: $SRC" >&2; exit 1; }
cp -r "$SRC/main.lua" "$SRC/metadata.xml" "$SRC/isaacbot" "$SRC/resources" "$DST/"
echo "synced: $SRC -> $DST"
