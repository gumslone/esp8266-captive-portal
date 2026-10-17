#!/usr/bin/env bash
set -euo pipefail
#
# Flash the NodeMCU firmware over serial (CLI). Thin wrapper around
# tools/bugzapper/flash.sh, which defaults to the first ./firmware/*.bin.
# All options pass through. Afterwards, upload the portal: tools/upload.py --lfs
#
#   ./flash.sh                 # flash firmware/nodemcu_*.bin at 0x0
#   ./flash.sh -e              # erase all flash first (recommended on a new board)
#   ./flash.sh -p /dev/cu.usbserial-110 -b 460800
#   ./flash.sh -l              # list serial ports
#   ./flash.sh -h              # full help
#
#   ./flash.sh --no-reset [PORT]
#       For boards you put into flash mode by hand (hold FLASH/GPIO0, press
#       reset, release FLASH): esptool's automatic reset would knock such a
#       board back out of flash mode, so connect without touching RTS/DTR.

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

if [ "${1:-}" = "--no-reset" ]; then
  PORT="${2:-$(ls /dev/cu.usbserial* /dev/cu.SLAB* /dev/cu.wchusb* /dev/ttyUSB* 2>/dev/null | head -n1 || true)}"
  FW="$(ls firmware/*.bin | head -n1)"
  [ -n "$PORT" ] || { echo "No serial port found" >&2; exit 1; }
  echo "==> Flashing $FW via $PORT (no automatic reset)"
  PYTHONPATH="$DIR/tools/bugzapper/vendor" exec python3 "$DIR/tools/bugzapper/vendor/esptool.py" \
    --port "$PORT" --baud 115200 --before no_reset write_flash -fm dio -fs detect 0x0 "$FW"
fi

exec "$DIR/tools/bugzapper/flash.sh" "$@"
