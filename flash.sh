#!/usr/bin/env bash
set -euo pipefail
#
# Flash the NodeMCU firmware over serial (CLI). Thin wrapper around
# tools/bugzapper/flash.sh. Default image: the in-use build in
# firmware/minimal/ (else the first firmware/*.bin). All options pass through.
# Afterwards, upload the portal: tools/upload.py
#
#   ./flash.sh -e              # erase all flash, then write (use when switching builds)
#   ./flash.sh                 # write without erasing
#   ./flash.sh -p /dev/cu.usbserial-110 -b 460800
#   ./flash.sh -f firmware/tehybug/...   # another image
#   ./flash.sh -l              # list serial ports
#   ./flash.sh -h              # full help
#
#   ./flash.sh --no-reset [-e] [PORT]
#       For boards you put into flash mode by hand (hold FLASH/GPIO0, press
#       reset, release FLASH): esptool's automatic reset would knock such a
#       board back out of flash mode, so connect without touching RTS/DTR.
#       -e erases the whole flash first (settings and uploaded files too).

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
FW="$(ls firmware/minimal/*.bin 2>/dev/null | head -n1 || true)"
[ -n "$FW" ] || FW="$(ls firmware/*.bin 2>/dev/null | head -n1 || true)"

if [ "${1:-}" = "--no-reset" ]; then
  shift
  ERASE=""
  if [ "${1:-}" = "-e" ]; then ERASE="--erase-all"; shift; fi
  PORT="${1:-$(ls /dev/cu.usbserial* /dev/cu.SLAB* /dev/cu.wchusb* /dev/ttyUSB* 2>/dev/null | head -n1 || true)}"
  [ -n "$PORT" ] || { echo "No serial port found" >&2; exit 1; }
  [ -n "$FW" ] || { echo "No firmware .bin found" >&2; exit 1; }
  echo "==> Flashing $FW via $PORT (no automatic reset${ERASE:+, full erase})"
  PYTHONPATH="$DIR/tools/bugzapper/vendor" exec python3 "$DIR/tools/bugzapper/vendor/esptool.py" \
    --port "$PORT" --baud 115200 --before no_reset write_flash $ERASE -fm dio -fs detect 0x0 "$FW"
fi

# default image unless the caller chose one (-f) or just wants -l / -h
for a in "$@"; do case "$a" in -f|-l|-h) exec "$DIR/tools/bugzapper/flash.sh" "$@" ;; esac; done
exec "$DIR/tools/bugzapper/flash.sh" -f "$FW" "$@"
