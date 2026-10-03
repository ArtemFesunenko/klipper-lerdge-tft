#!/bin/bash
# Lerdge TFT touch screen support for Klipper - uninstaller
#
# Removes the KlipperScreen mirror services and the display configuration
# and switches Klipper back to its upstream branch.  The board keeps the
# Lerdge firmware until a new firmware is flashed (build it with
# "make menuconfig" and flash it with scripts/flash-sdcard.sh or a TF card).
#
# This file may be distributed under the terms of the GNU GPLv3 license.
set -e

KLIPPER_DIR="${KLIPPER_DIR:-$HOME/klipper}"
DATA_DIR="${DATA_DIR:-$HOME/printer_data}"
KLIPPER_SERVICE="${KLIPPER_SERVICE:-klipper}"
DO_SERVICES=1

while [ $# -gt 0 ]; do
    case "$1" in
        --klipper) KLIPPER_DIR="$2"; shift;;
        --data) DATA_DIR="$2"; shift;;
        --klipper-service) KLIPPER_SERVICE="$2"; shift;;
        --no-services) DO_SERVICES=0;;
        -h|--help)
            echo "Usage: ./uninstall.sh [--klipper DIR] [--data DIR]" \
                 "[--klipper-service NAME] [--no-services]"
            exit 0;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
    shift
done

PRINTER_CFG="$DATA_DIR/config/printer.cfg"

if [ "$DO_SERVICES" = "1" ]; then
    echo "==> Removing the KlipperScreen mirror services"
    for unit in lerdge-mirror KlipperScreen-lerdge lerdge-xvfb; do
        if [ -f "/etc/systemd/system/$unit.service" ]; then
            sudo systemctl disable --now "$unit" || true
            sudo rm -f "/etc/systemd/system/$unit.service"
        fi
    done
    sudo systemctl daemon-reload
fi

if [ -f "$PRINTER_CFG" ]; then
    echo "==> Removing the display configuration from printer.cfg"
    stamp="$(date +%Y%m%d_%H%M%S)"
    cp "$PRINTER_CFG" "$DATA_DIR/config/printer-before-lerdge-uninstall-$stamp.cfg"
    python3 - "$PRINTER_CFG" <<'EOF'
import sys, re
path = sys.argv[1]
lines = open(path, encoding='utf-8').read().split('\n')
out = []
for line in lines:
    if re.match(r'^\[include\s+lerdge_tft\.cfg\]', line):
        continue
    if line.startswith('#lerdge# '):
        line = line[len('#lerdge# '):]
    out.append(line)
open(path, 'w', encoding='utf-8').write('\n'.join(out))
EOF
    if [ -f "$DATA_DIR/config/lerdge_tft.cfg" ]; then
        mv "$DATA_DIR/config/lerdge_tft.cfg" \
           "$DATA_DIR/config/lerdge_tft.cfg.removed-$stamp"
    fi
    echo "    Note: the [mcu] baud setting was kept - change it if you flash"
    echo "    a firmware with a different baud rate."
fi

if [ -d "$KLIPPER_DIR/.git" ]; then
    echo "==> Switching Klipper back to the upstream branch"
    cd "$KLIPPER_DIR"
    upstream="$(git symbolic-ref -q --short refs/remotes/origin/HEAD \
                || echo origin/master)"
    branch="${upstream#origin/}"
    if git rev-parse -q --verify "$branch" >/dev/null; then
        git checkout -q "$branch"
    else
        git checkout -q -b "$branch" "$upstream"
    fi
    if [ -f .config.before-lerdge ]; then
        mv .config.before-lerdge .config
        echo "    Restored the previous firmware build configuration"
    fi
    echo "    Klipper is on '$branch' (the 'lerdge' branch was kept)"
fi

if [ "$DO_SERVICES" = "1" ]; then
    sudo systemctl restart "$KLIPPER_SERVICE" || true
fi
echo "==> Done"
