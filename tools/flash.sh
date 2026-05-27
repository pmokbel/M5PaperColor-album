#!/usr/bin/env bash
# Flash the M5PaperColor by catching the brief USB-Serial-JTAG window before
# TinyUSB MSC takes over the USB-C port.
#
# Why this is needed: on the ESP32-S3, USB-Serial-JTAG (which esptool needs)
# and USB-OTG (which TinyUSB MSC drives, exposing the device as a USB mass
# storage volume) share the single USB-C wire. The boot ROM exposes
# USB-Serial-JTAG for ~1–2 seconds at every power-on, then the firmware
# initializes TinyUSB MSC and the JTAG/CDC endpoint disappears. esptool can
# only reach the chip during that boot window.
#
# Usage:
#   tools/flash.sh                # idf.py app-flash  (preserves NVS / photos)
#   tools/flash.sh full           # idf.py flash      (bootloader + app + partitions + storage)
#   tools/flash.sh erase          # idf.py erase-flash, then full flash
#   tools/flash.sh monitor        # just open serial monitor
#
# Environment overrides:
#   PAPERCOLOR_PORT   exact device path or glob pattern of the CDC port.
#                     Defaults to "/dev/cu.usbmodem*" (macOS). On Linux you'd
#                     usually set PAPERCOLOR_PORT=/dev/ttyACM* or similar.
#   FLASH_TIMEOUT_S   seconds to wait for the CDC port. Defaults to 180.
#
# Power-cycle the device while this script is running. Long-press the power
# button to turn it off, then a short press to turn it back on.

set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-app-flash}"
PORT_GLOB="${PAPERCOLOR_PORT:-/dev/cu.usbmodem*}"
TIMEOUT_S="${FLASH_TIMEOUT_S:-180}"

if ! command -v idf.py >/dev/null 2>&1; then
    echo "error: idf.py not on PATH — source the ESP-IDF environment first:" >&2
    echo "  . \$IDF_PATH/export.sh" >&2
    exit 1
fi

echo ">>> Waiting up to ${TIMEOUT_S}s for ${PORT_GLOB}"
echo ">>> Power-cycle the M5PaperColor now."

# Note: deliberately not quoting $PORT_GLOB so a wildcard pattern expands.
# Quote the env var if you set it to a path containing whitespace.
for ((i = 1; i <= TIMEOUT_S; i++)); do
    # shellcheck disable=SC2086
    PORT=$(ls -1 $PORT_GLOB 2>/dev/null | head -1 || true)
    if [ -n "$PORT" ]; then
        echo ">>> Port: $PORT  (after ${i}s)"
        case "$MODE" in
            full)
                exec idf.py -p "$PORT" flash
                ;;
            erase)
                idf.py -p "$PORT" erase-flash
                exec idf.py -p "$PORT" flash
                ;;
            monitor)
                exec idf.py -p "$PORT" monitor
                ;;
            app-flash | flash)
                exec idf.py -p "$PORT" "$MODE"
                ;;
            *)
                echo "error: unknown mode '$MODE'" >&2
                echo "valid: app-flash | full | erase | monitor" >&2
                exit 2
                ;;
        esac
    fi
    sleep 1
done

echo ">>> Timeout — no device matching '${PORT_GLOB}' appeared on USB." >&2
echo ">>> Check the cable, then re-run and power-cycle the device sooner." >&2
exit 1
