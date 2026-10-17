#!/usr/bin/env bash
set -euo pipefail
#
# Launch BugZapper (GUI flasher + serial monitor + NodeMCU Lua upload tab)
# for the captive portal. It lists firmware/*.bin; flash it once, then upload
# the portal files with tools/upload.py (or BugZapper's Lua tab).
#
# Usage: ./bugzapper.sh [firmware-dir]   (default: ./firmware)

DIR="$(cd "$(dirname "$0")" && pwd)"

export BUGZAPPER_TITLE="Captive Portal Flasher"
export BUGZAPPER_ICON="$DIR/tools/bugzapper/icon.png"
export BUGZAPPER_FW_DIR="${1:-$DIR/firmware}"

exec "$DIR/tools/bugzapper/bugzapper.sh" "$@"
