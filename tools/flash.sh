#!/usr/bin/env bash
# Kept for old instructions: uploading the portal files is now done by
# tools/upload.py (bundled nodemcu-uploader, no npm / nodemcu-tool needed).
# Usage: tools/flash.sh [serial_port]
set -e
cd "$(dirname "$0")/.."
exec python3 tools/upload.py ${1:+-p "$1"}
