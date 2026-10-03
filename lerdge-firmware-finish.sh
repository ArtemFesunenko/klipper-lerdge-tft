#!/bin/bash
# Finish a Lerdge firmware update: verify the firmware version on the board
# and remove the firmware file from the TF card (the Lerdge bootloader
# would install it again on every start otherwise).
#
# Runs at boot from lerdge-firmware-finish.service (before Klipper starts)
# or from "install.sh --finish".  Klipper must not be running.
#
# This file may be distributed under the terms of the GNU GPLv3 license.

ENV_FILE="${1:-$HOME/printer_data/systemd/lerdge-firmware.env}"
# shellcheck disable=SC1090
. "$ENV_FILE" || exit 1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

if [ ! -f "$FLAG" ]; then
    echo "No pending firmware update"
    exit 0
fi

log "Checking the Lerdge firmware on $SERIAL"
# Wait for the serial port (USB adapters may appear late at boot)
for i in $(seq 1 60); do
    [ -e "$SERIAL" ] && break
    sleep 1
done
if [ ! -e "$SERIAL" ]; then
    log "Serial port $SERIAL not found"
    exit 1
fi

# The new firmware alternates between the main and the fallback baud rate
# until it is contacted, so try both
for baud in $BAUDS; do
    out="$(cd "$KLIPPER_DIR" && ./scripts/flash-sdcard.sh -c -b "$baud" \
           "$SERIAL" "lerdge-$BOARD" 2>&1)"
    echo "$out" | grep -v '^  ' >> "$LOG"
    if echo "$out" | grep -q "Firmware Flash Successful"; then
        rm -f "$FLAG"
        log "OK: $(echo "$out" | grep 'Current Firmware' | tail -1)"
        exit 0
    fi
    if echo "$out" | grep -q "Version Mismatch"; then
        log "The board does not run the new firmware yet - was the printer" \
            "switched off and on?"
        exit 1
    fi
    if echo "$out" | grep -q "Failed to Initialize SD Card"; then
        rm -f "$FLAG"
        log "No TF card in the board - make sure the firmware file is not" \
            "left on the card"
        exit 0
    fi
    log "No answer at $baud baud"
done
log "Could not check the firmware"
exit 1
