#!/bin/bash
# Lerdge TFT touch screen support for Klipper - installer
#
# This script patches an existing Klipper installation, builds and
# flashes the board firmware, adds the display configuration and
# (optionally) sets up KlipperScreen on the Lerdge screen.
#
# Run "./install.sh --help" for the options.
#
# This file may be distributed under the terms of the GNU GPLv3 license.
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (can be changed with options or environment variables)
KLIPPER_DIR="${KLIPPER_DIR:-$HOME/klipper}"
KLIPPY_ENV="${KLIPPY_ENV:-$HOME/klippy-env}"
DATA_DIR="${DATA_DIR:-$HOME/printer_data}"
KS_DIR="${KS_DIR:-$HOME/KlipperScreen}"
KS_ENV="${KS_ENV:-$HOME/.KlipperScreen-env}"
KLIPPER_SERVICE="${KLIPPER_SERVICE:-klipper}"
MOONRAKER_URL="${MOONRAKER_URL:-http://127.0.0.1:7125}"
XDISPLAY="${XDISPLAY:-:99}"
FIRMWARE_OUT="${FIRMWARE_OUT:-$HOME/lerdge_firmware}"
FALLBACK_BAUD=250000

BOARD=""
BAUD=""
MIRROR=""
FLASH=""
SERIAL_DEV=""
BASE_REF=""
ASSUME_YES=0
MODE="install"
DO_SERVICES=1

LERDGE_BRANCH="lerdge"
STATE_FILE=""

######################################################################
# Helpers
######################################################################

if [ -t 1 ]; then
    C_INFO="\e[1;36m"; C_OK="\e[1;32m"; C_WARN="\e[1;33m"; C_ERR="\e[1;31m"
    C_OFF="\e[0m"
else
    C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""
fi
step() { echo -e "\n${C_INFO}==> $*${C_OFF}"; }
info() { echo -e "    $*"; }
ok() { echo -e "${C_OK}    $*${C_OFF}"; }
warn() { echo -e "${C_WARN}WARNING: $*${C_OFF}"; }
die() { echo -e "${C_ERR}ERROR: $*${C_OFF}" >&2; exit 1; }

# ask "question" default -> sets REPLY
ask() {
    local question="$1" default="$2"
    if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then
        REPLY="$default"
        echo "    $question [$default] -> $REPLY"
        return
    fi
    read -r -p "    $question [$default] " REPLY
    REPLY="${REPLY:-$default}"
}
ask_yn() {
    ask "$1 (y/n)" "$2"
    case "$REPLY" in [yY]*) return 0;; *) return 1;; esac
}

usage() {
    cat <<EOF
Usage: ./install.sh [options]

Installs Lerdge TFT touch screen support into an existing Klipper setup.

Modes:
  (default)          Patch Klipper, build the firmware, write it to the TF
                     card of the board (or create a file for it) and
                     configure Klipper.  The installation completes after
                     the printer was switched off and on once.
  --finish           Complete the installation now (after switching the
                     printer off and on, when the host was not restarted)
  --update           Update Klipper from upstream, re-apply the patches,
                     rebuild and install the firmware
  --build-only       Only patch Klipper and build the firmware

Options:
  --board k|x        Lerdge board type (Lerdge-K or Lerdge-X)
  --baud N           MCU serial baud rate (250000 or 1500000)
  --mirror           Show KlipperScreen on the Lerdge screen
  --no-mirror        Use the built-in Klipper menu on the Lerdge screen
  --flash sd|file|none
                     sd:   write the firmware to the TF card in the board
                           through the running firmware (the board must
                           already run Klipper)
                     file: create the firmware file to copy to the TF card
                           yourself (first installation over the stock
                           Lerdge firmware)
                     none: only build the firmware
  --serial DEV       MCU serial port (default: from printer.cfg)
  --base REF         Klipper commit to apply the patches to
  --klipper DIR      Klipper directory (default: $KLIPPER_DIR)
  --data DIR         printer_data directory (default: $DATA_DIR)
  --klipper-service NAME
                     Klipper systemd service name (default: klipper)
  --no-services      Do not install/restart any systemd service
  -y, --yes          Do not ask questions, use defaults
  -h, --help         Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --board) BOARD="$2"; shift;;
        --baud) BAUD="$2"; shift;;
        --mirror) MIRROR=1;;
        --no-mirror) MIRROR=0;;
        --flash) FLASH="$2"; shift;;
        --serial) SERIAL_DEV="$2"; shift;;
        --base) BASE_REF="$2"; shift;;
        --klipper) KLIPPER_DIR="$2"; shift;;
        --data) DATA_DIR="$2"; shift;;
        --klipper-service) KLIPPER_SERVICE="$2"; shift;;
        --no-services) DO_SERVICES=0;;
        --finish) MODE="finish";;
        --update) MODE="update";;
        --build-only) MODE="build";;
        -y|--yes) ASSUME_YES=1;;
        -h|--help) usage; exit 0;;
        *) usage; die "Unknown option: $1";;
    esac
    shift
done

PRINTER_CFG="$DATA_DIR/config/printer.cfg"
STATE_FILE="$KLIPPER_DIR/.git/lerdge-tft.state"

# Command line to continue the installation with the same directories
FINISH_CMD="$REPO_DIR/install.sh --finish"
[ "$KLIPPER_DIR" != "$HOME/klipper" ] && FINISH_CMD="$FINISH_CMD --klipper $KLIPPER_DIR"
[ "$DATA_DIR" != "$HOME/printer_data" ] && FINISH_CMD="$FINISH_CMD --data $DATA_DIR"
[ "$KLIPPER_SERVICE" != "klipper" ] && FINISH_CMD="$FINISH_CMD --klipper-service $KLIPPER_SERVICE"

save_state() {
    cat > "$STATE_FILE" <<EOF
BOARD=$BOARD
BAUD=$BAUD
MIRROR=$MIRROR
BASE=$BASE
EOF
}
load_state() {
    # Fill in the options that were not given on the command line from
    # the previous run
    [ -f "$STATE_FILE" ] || return 0
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            BOARD) [ -n "$BOARD" ] || BOARD="$value";;
            BAUD) [ -n "$BAUD" ] || BAUD="$value";;
            MIRROR) [ -n "$MIRROR" ] || MIRROR="$value";;
            BASE) BASE="$value";;
        esac
    done < "$STATE_FILE"
}

sysctl() {
    if [ "$DO_SERVICES" = "1" ]; then
        sudo systemctl "$@"
    else
        info "(skipped: systemctl $*)"
    fi
}

# Read a value from the [mcu] section of printer.cfg
cfg_mcu_value() {
    [ -f "$PRINTER_CFG" ] || return 0
    python3 - "$PRINTER_CFG" "$1" <<'EOF'
import sys, re
path, key = sys.argv[1], sys.argv[2]
section = None
for line in open(path, encoding='utf-8', errors='replace'):
    if line.startswith('#*#'):
        break
    m = re.match(r'^\[([^\]]+)\]', line)
    if m:
        section = m.group(1).strip()
        continue
    if section == 'mcu':
        m = re.match(r'^%s\s*[:=]\s*(\S+)' % re.escape(key), line)
        if m:
            print(m.group(1))
            break
EOF
}

klipper_version() {
    git -C "$KLIPPER_DIR" describe --always --tags --long --dirty 2>/dev/null
}

wait_klipper_ready() {
    local i state
    for i in $(seq 1 60); do
        state=$(curl -s -m 3 "$MOONRAKER_URL/printer/info" | python3 -c \
            "import json,sys;print(json.load(sys.stdin)['result']['state'])" \
            2>/dev/null || true)
        if [ "$state" = "ready" ]; then
            return 0
        fi
        sleep 3
    done
    return 1
}

mcu_version() {
    curl -s -m 3 "$MOONRAKER_URL/printer/objects/query?mcu" | python3 -c \
        "import json,sys;print(json.load(sys.stdin)['result']['status']['mcu']['mcu_version'])" \
        2>/dev/null || true
}

######################################################################
# Checks and questions
######################################################################

check_environment() {
    step "Checking the environment"
    [ "$(id -u)" != "0" ] || die "Do not run this script as root (it uses sudo when needed)"
    [ -d "$KLIPPER_DIR/.git" ] || die "No Klipper git checkout at $KLIPPER_DIR (use --klipper)"
    [ -x "$KLIPPY_ENV/bin/python" ] || warn "No Klipper python environment at $KLIPPY_ENV"
    command -v python3 >/dev/null || die "python3 is required"
    command -v git >/dev/null || die "git is required"
    if [ "$MODE" != "build" ]; then
        [ -f "$PRINTER_CFG" ] || die "No printer.cfg at $PRINTER_CFG (use --data)"
    fi
    info "Klipper:     $KLIPPER_DIR ($(klipper_version))"
    info "Config:      $PRINTER_CFG"
    if [ "$DO_SERVICES" = "1" ] || [ "$MODE" != "finish" ]; then
        # Ask for the sudo password once, before anything is changed
        if ! sudo -n true 2>/dev/null; then
            info "Some steps need administrator rights (sudo):"
            sudo -v || die "sudo is required (run the installer from a terminal)"
        fi
    fi
}

choose_options() {
    load_state
    step "Installation options"
    if [ -z "$BOARD" ]; then
        ask "Lerdge board type: k (Lerdge-K) or x (Lerdge-X)?" "k"
        BOARD="$REPLY"
    fi
    BOARD="$(echo "$BOARD" | tr 'A-Z' 'a-z')"
    case "$BOARD" in k|x) ;; *) die "Unsupported board '$BOARD' (use k or x)";; esac
    if [ -z "$MIRROR" ]; then
        if ask_yn "Show KlipperScreen on the Lerdge screen (recommended)?" "y"; then
            MIRROR=1
        else
            MIRROR=0
        fi
    fi
    if [ -z "$BAUD" ]; then
        local def=250000
        [ "$MIRROR" = "1" ] && def=1500000
        info "KlipperScreen needs a fast MCU link: 1500000 baud is recommended."
        info "The firmware falls back to $FALLBACK_BAUD baud automatically if"
        info "the wiring can not handle it."
        ask "MCU serial baud rate?" "$def"
        BAUD="$REPLY"
    fi
    case "$BAUD" in *[!0-9]*|"") die "Invalid baud rate '$BAUD'";; esac
    info "Board: Lerdge-${BOARD^^}, baud: $BAUD, KlipperScreen mirror: $MIRROR"
}

######################################################################
# Patching Klipper
######################################################################

patch_subjects() {
    python3 - "$REPO_DIR"/patches/*.patch <<'EOF'
import sys, re, email
for path in sys.argv[1:]:
    with open(path, encoding='utf-8', errors='replace') as f:
        msg = email.message_from_file(f)
    subject = ' '.join(str(msg['Subject']).split())
    print(re.sub(r'^\[PATCH[^\]]*\]\s*', '', subject))
EOF
}

find_applied_base() {
    # If the patches are already applied on HEAD, print the commit below
    # the first one of them
    local first subject commit
    first="$(patch_subjects | head -1)"
    commit="$(git -C "$KLIPPER_DIR" log -n 300 --format='%H %s' \
        | while read -r hash subj; do
            if [ "$subj" = "$first" ]; then echo "$hash"; break; fi
          done)"
    if [ -n "$commit" ]; then
        git -C "$KLIPPER_DIR" rev-parse "$commit^"
    fi
}

patch_klipper() {
    step "Applying the Lerdge patches to Klipper"
    cd "$KLIPPER_DIR"
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        die "Klipper has local modifications - commit or stash them first:
$(git status --short --untracked-files=no)"
    fi
    if [ -n "$(git status --porcelain | grep '^?? scripts/\|^?? klippy/\|^?? src/' || true)" ]; then
        warn "Untracked files in Klipper:"
        git status --short | grep '^??' || true
    fi
    local orig
    orig="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$MODE" = "update" ]; then
        info "Fetching upstream Klipper..."
        git fetch -q origin
        local upstream
        upstream="$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo origin/master)"
        BASE="$(git rev-parse "$upstream")"
    elif [ -n "$BASE_REF" ]; then
        BASE="$(git rev-parse "$BASE_REF")"
    else
        BASE="$(find_applied_base)"
        if [ -z "$BASE" ]; then
            BASE="$(git rev-parse HEAD)"
        else
            info "The patches are already applied, re-applying them"
        fi
    fi
    info "Base commit: $(git log -1 --format='%h %s' "$BASE")"
    git checkout -q -B "$LERDGE_BRANCH" "$BASE"
    if ! git -c user.name="klipper-lerdge-tft" \
            -c user.email="klipper-lerdge-tft@localhost" \
            am -q -3 "$REPO_DIR"/patches/*.patch; then
        git am --abort || true
        git checkout -q "$orig" 2>/dev/null || true
        die "The patches do not apply to this Klipper version.
Try '--base <older commit>' or update this repository."
    fi
    save_state
    ok "Klipper is now on branch '$LERDGE_BRANCH' ($(klipper_version))"
    if [ "$MODE" = "update" ] && [ -x "$KLIPPY_ENV/bin/pip" ]; then
        info "Updating the Klipper python environment..."
        "$KLIPPY_ENV/bin/pip" install -q -r scripts/klippy-requirements.txt \
            || warn "Could not update the Klipper python packages"
    fi
    cd - >/dev/null
}

######################################################################
# Packages
######################################################################

install_packages() {
    step "Installing system packages"
    local pkgs="gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi make"
    if [ "$MIRROR" = "1" ]; then
        pkgs="$pkgs xvfb python3-numpy python3-xlib"
    fi
    local missing=""
    for p in $pkgs; do
        dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    if [ -z "$missing" ]; then
        ok "All packages are installed"
        return
    fi
    info "Installing:$missing"
    sudo apt-get update -q
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        --no-install-recommends $missing
}

######################################################################
# Firmware
######################################################################

build_firmware() {
    step "Building the Lerdge-${BOARD^^} firmware ($BAUD baud)"
    cd "$KLIPPER_DIR"
    if [ -f .config ] && [ ! -f .config.before-lerdge ]; then
        cp .config .config.before-lerdge
        info "Saved the previous build configuration as .config.before-lerdge"
    fi
    local fallback=$FALLBACK_BAUD
    [ "$BAUD" = "$FALLBACK_BAUD" ] && fallback=0
    sed -e "s/@BAUD@/$BAUD/" -e "s/@FALLBACK@/$fallback/" \
        "$REPO_DIR/boards/lerdge.config" > .config
    make olddefconfig >/dev/null
    make clean >/dev/null
    if ! make -j"$(nproc)" >/tmp/lerdge-build.log 2>&1; then
        tail -20 /tmp/lerdge-build.log
        die "Firmware build failed (see /tmp/lerdge-build.log)"
    fi
    FW_VERSION="$(python3 -c "import json;print(json.load(open('out/klipper.dict'))['version'])")"
    save_state
    ok "Built out/klipper.bin ($FW_VERSION)"
    cd - >/dev/null
}

write_firmware_file() {
    step "Creating the firmware file for a manual TF card update"
    rm -rf "$FIRMWARE_OUT"
    mkdir -p "$FIRMWARE_OUT"
    python3 "$KLIPPER_DIR/scripts/update_lerdge.py" -b "$BOARD" \
        "$KLIPPER_DIR/out/klipper.bin" "$FIRMWARE_OUT" >/dev/null
    local sys="Lerdge_${BOARD^^}_system"
    ok "Created $FIRMWARE_OUT/$sys/Firmware/Lerdge_${BOARD^^}_firmware_force.bin"
    MANUAL_COPY_TEXT="
      Copy the folder \"$sys\" from $FIRMWARE_OUT to the root of a FAT32
      formatted TF (micro SD) card, for example from your computer:
        scp -r $(whoami)@$(hostname -I 2>/dev/null | awk '{print $1}'):$FIRMWARE_OUT/$sys .
      and insert the card into the TF slot of the Lerdge board.
"
}

current_baud() {
    local b
    b="$(cfg_mcu_value baud)"
    echo "${b:-250000}"
}

serial_device() {
    if [ -n "$SERIAL_DEV" ]; then
        echo "$SERIAL_DEV"
    else
        cfg_mcu_value serial
    fi
}

# Upload the firmware to the TF card in the board through the running
# Klipper firmware.  The bootloader can only read the card after a power
# cycle, so the new version is not active yet afterwards.
upload_sd() {
    local dev log
    dev="$(serial_device)"
    [ -n "$dev" ] || die "Unknown MCU serial port (use --serial)"
    log=/tmp/lerdge-flash.log
    step "Writing the firmware to the TF card in the board"
    sysctl stop "$KLIPPER_SERVICE" \
        || die "Could not stop the $KLIPPER_SERVICE service"
    set +e
    (cd "$KLIPPER_DIR" && ./scripts/flash-sdcard.sh -b "$(current_baud)" \
        "$dev" "lerdge-$BOARD") >"$log" 2>&1
    set -e
    grep -v '^  ' "$log" | grep -E '^(Connected|Uploading|Validating|Firmware Upload|SD Card Flash Error)' || true
    if grep -q "Firmware Upload Complete" "$log"; then
        ok "Firmware written to the TF card"
        return 0
    fi
    sysctl start "$KLIPPER_SERVICE"
    if grep -q "Failed to Initialize SD Card" "$log"; then
        die "No usable TF card in the Lerdge board. Insert a FAT32 formatted
       TF card into the board's TF slot and run the installer again, or
       use --flash file."
    elif grep -q "Unable to connect" "$log"; then
        die "Could not connect to the board at $(current_baud) baud on $dev.
       Does it run Klipper?  For the first installation use --flash file."
    fi
    die "Writing the firmware failed, see $log"
}

choose_flash_mode() {
    if [ -z "$FLASH" ]; then
        info "How should the firmware be installed?"
        info "  sd   - through the TF card in the Lerdge board, written by the"
        info "         installer (the board must already run Klipper)"
        info "  file - create a file to copy to the TF card yourself (needed for"
        info "         the first installation over the stock Lerdge firmware)"
        info "  none - only build the firmware"
        ask "Firmware installation (sd/file/none)?" "sd"
        FLASH="$REPLY"
    fi
    case "$FLASH" in sd|file|none) ;; *) die "Unknown flash mode '$FLASH'";; esac
}

# The bootloader installs the firmware file on every start, so it has to
# be removed after the update.  A one-shot service does this (and checks
# the firmware version) at the next start of the host, before Klipper.
setup_finisher() {
    step "Setting up the firmware check for the next start"
    local env_file="$DATA_DIR/systemd/lerdge-firmware.env"
    local fallback=$FALLBACK_BAUD
    [ "$BAUD" = "$FALLBACK_BAUD" ] && fallback=""
    mkdir -p "$DATA_DIR/systemd" "$DATA_DIR/logs"
    cat > "$env_file" <<EOF
KLIPPER_DIR=$KLIPPER_DIR
BOARD=$BOARD
BAUDS="$BAUD $fallback"
SERIAL=$(serial_device)
FLAG=$DATA_DIR/systemd/lerdge-firmware.pending
LOG=$DATA_DIR/logs/lerdge-firmware.log
EOF
    touch "$DATA_DIR/systemd/lerdge-firmware.pending"
    sed -e "s|@USER@|$(whoami)|g" -e "s|@REPO_DIR@|$REPO_DIR|g" \
        -e "s|@ENV_FILE@|$env_file|g" \
        -e "s|@FLAG@|$DATA_DIR/systemd/lerdge-firmware.pending|g" \
        -e "s|klipper.service|$KLIPPER_SERVICE.service|g" \
        "$REPO_DIR/systemd/lerdge-firmware-finish.service" \
        > /tmp/lerdge-firmware-finish.service
    if [ "$DO_SERVICES" = "1" ]; then
        sudo install -m 644 /tmp/lerdge-firmware-finish.service \
            /etc/systemd/system/
    fi
    sysctl daemon-reload
    sysctl enable lerdge-firmware-finish
    ok "The firmware will be checked and removed from the card at the next start"
}

######################################################################
# Configuration
######################################################################

configure_printer() {
    step "Configuring Klipper"
    local cfg_dir="$DATA_DIR/config" stamp
    stamp="$(date +%Y%m%d_%H%M%S)"
    cp "$PRINTER_CFG" "$cfg_dir/printer-before-lerdge-$stamp.cfg"
    info "Backup: $cfg_dir/printer-before-lerdge-$stamp.cfg"
    if [ ! -f "$cfg_dir/lerdge_tft.cfg" ]; then
        cp "$REPO_DIR/boards/lerdge-$BOARD.cfg" "$cfg_dir/lerdge_tft.cfg"
        ok "Created lerdge_tft.cfg"
    else
        info "Keeping the existing lerdge_tft.cfg"
    fi
    python3 - "$PRINTER_CFG" "$BAUD" <<'EOF'
import sys, re
path, baud = sys.argv[1], sys.argv[2]
lines = open(path, encoding='utf-8').read().split('\n')
out = []
section = None
in_auto = False
have_include = any(re.match(r'^\[include\s+lerdge_tft\.cfg\]', l)
                   for l in lines)
mcu_baud_done = False
for i, line in enumerate(lines):
    if line.startswith('#*#'):
        in_auto = True
    m = re.match(r'^\[([^\]]+)\]', line)
    if m and not in_auto:
        if section == 'mcu' and not mcu_baud_done:
            out.append('baud: %s' % baud)
            mcu_baud_done = True
        section = m.group(1).strip()
        if section == 'display':
            # Disable any other display definition (the Lerdge display is
            # defined in lerdge_tft.cfg)
            out.append('#lerdge# ' + line)
            continue
    elif section == 'display' and not in_auto and not line.startswith('#'):
        out.append('#lerdge# ' + line if line.strip() else line)
        continue
    if section == 'mcu' and not in_auto:
        if re.match(r'^baud\s*[:=]', line):
            out.append('baud: %s' % baud)
            mcu_baud_done = True
            continue
    out.append(line)
if section == 'mcu' and not mcu_baud_done:
    out.append('baud: %s' % baud)
if not have_include:
    out.insert(0, '[include lerdge_tft.cfg]')
open(path, 'w', encoding='utf-8').write('\n'.join(out))
EOF
    ok "printer.cfg: [include lerdge_tft.cfg], [mcu] baud: $BAUD"
}

add_update_manager() {
    local moon="$DATA_DIR/config/moonraker.conf" url
    [ -f "$moon" ] || return 0
    cp "$moon" /tmp/lerdge-moonraker.conf.orig
    url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
    if [ -n "$url" ] && ! grep -q '^\[update_manager klipper-lerdge-tft\]' "$moon"; then
        cat >> "$moon" <<EOF

[update_manager klipper-lerdge-tft]
type: git_repo
path: $REPO_DIR
origin: $url
primary_branch: $(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)
is_system_service: False
EOF
        info "Added [update_manager klipper-lerdge-tft] to moonraker.conf"
    fi
    if [ "$MIRROR" = "1" ] && [ -d "$KS_DIR/.git" ] \
       && ! grep -qi '^\[update_manager KlipperScreen\]' "$moon"; then
        cat >> "$moon" <<EOF

[update_manager KlipperScreen]
type: git_repo
path: $KS_DIR
origin: https://github.com/KlipperScreen/KlipperScreen.git
virtualenv: $KS_ENV
requirements: scripts/KlipperScreen-requirements.txt
system_dependencies: scripts/system-dependencies.json
managed_services: KlipperScreen
EOF
        info "Added [update_manager KlipperScreen] to moonraker.conf"
    fi
    if ! cmp -s "$moon" "/tmp/lerdge-moonraker.conf.orig"; then
        sysctl restart moonraker
    fi
}

install_klipperscreen() {
    if [ -d "$KS_DIR" ] && [ -x "$KS_ENV/bin/python" ]; then
        return
    fi
    step "Installing KlipperScreen"
    if [ ! -d "$KS_DIR" ]; then
        git clone -q https://github.com/KlipperScreen/KlipperScreen.git "$KS_DIR"
    fi
    local service=N
    if ask_yn "Also run KlipperScreen on an HDMI screen connected to the host?" "n"; then
        service=Y
    fi
    (cd "$KS_DIR" && BACKEND=X SERVICE=$service NETWORK=N START=1 \
        ./scripts/KlipperScreen-install.sh)
}

install_mirror() {
    step "Setting up KlipperScreen on the Lerdge screen"
    install_klipperscreen
    local cfg="$DATA_DIR/config/KlipperScreen-lerdge.conf"
    if [ ! -f "$cfg" ]; then
        cp "$REPO_DIR/klipperscreen/KlipperScreen-lerdge.conf" "$cfg"
        ok "Created KlipperScreen-lerdge.conf"
    fi
    mkdir -p "$DATA_DIR/logs"
    local unit
    for unit in lerdge-xvfb KlipperScreen-lerdge lerdge-mirror; do
        sed -e "s|@USER@|$(whoami)|g" -e "s|@DISPLAY@|$XDISPLAY|g" \
            -e "s|@KS_DIR@|$KS_DIR|g" -e "s|@KS_ENV@|$KS_ENV|g" \
            -e "s|@DATA_DIR@|$DATA_DIR|g" -e "s|@KLIPPER_DIR@|$KLIPPER_DIR|g" \
            -e "s|klipper.service|$KLIPPER_SERVICE.service|g" \
            "$REPO_DIR/systemd/$unit.service" > "/tmp/$unit.service"
        if [ "$DO_SERVICES" = "1" ]; then
            sudo install -m 644 "/tmp/$unit.service" /etc/systemd/system/
        else
            info "(skipped: install /etc/systemd/system/$unit.service)"
        fi
    done
    sysctl daemon-reload
    sysctl enable lerdge-xvfb KlipperScreen-lerdge lerdge-mirror
    sysctl restart lerdge-xvfb KlipperScreen-lerdge lerdge-mirror
    ok "KlipperScreen mirror services installed"
}

remove_mirror() {
    if [ -f /etc/systemd/system/lerdge-mirror.service ]; then
        step "Removing the KlipperScreen mirror services"
        sysctl disable --now lerdge-mirror KlipperScreen-lerdge lerdge-xvfb || true
    fi
}

######################################################################
# Finishing
######################################################################

configure_all() {
    configure_printer
    if [ "$MIRROR" = "1" ]; then
        install_mirror
    else
        remove_mirror
    fi
    add_update_manager
    save_state
}

print_power_cycle() {
    cat <<EOF

    ${MANUAL_COPY_TEXT}
    To complete the installation the printer has to be switched off and on
    once, so that the Lerdge bootloader installs the new firmware:

      * Host powered by the printer: shut the host down first
            sudo poweroff
        wait until it is off, then switch the printer off, wait 10 seconds
        and switch it on again.  Everything else happens automatically at
        the next start (the result is logged to
        $DATA_DIR/logs/lerdge-firmware.log).

      * Host with its own power supply: switch the printer off and on,
        then run
            $FINISH_CMD

    The Lerdge screen then shows five crosses for the touch calibration:
    tap their centers, then run SAVE_CONFIG.
EOF
}

# Verify the new firmware, remove it from the TF card and start Klipper
finish_now() {
    step "Checking the firmware on the board"
    local env_file="$DATA_DIR/systemd/lerdge-firmware.env"
    [ -f "$env_file" ] || die "Nothing to finish (no $env_file)"
    sysctl stop "$KLIPPER_SERVICE" \
        || die "Could not stop the $KLIPPER_SERVICE service"
    touch "$DATA_DIR/systemd/lerdge-firmware.pending"
    if "$REPO_DIR/lerdge-firmware-finish.sh" "$env_file"; then
        ok "The board runs the new firmware"
    else
        warn "The firmware check failed, see $DATA_DIR/logs/lerdge-firmware.log"
    fi
    step "Starting Klipper"
    sysctl start "$KLIPPER_SERVICE"
    if [ "$DO_SERVICES" = "1" ]; then
        if wait_klipper_ready; then
            ok "Klipper is ready (MCU firmware: $(mcu_version))"
        else
            warn "Klipper is not ready yet - check $DATA_DIR/logs/klippy.log.
         If the MCU does not connect at $BAUD baud, set 'baud: $FALLBACK_BAUD'
         in the [mcu] section of printer.cfg and restart Klipper."
        fi
    fi
}

######################################################################
# Main
######################################################################

MANUAL_COPY_TEXT=""
check_environment
choose_options
case "$MODE" in
    build)
        patch_klipper
        install_packages
        build_firmware
        ;;
    finish)
        finish_now
        ;;
    install|update)
        choose_flash_mode
        patch_klipper
        install_packages
        build_firmware
        case "$FLASH" in
            none)
                step "Firmware built"
                info "Install out/klipper.bin and run the installer again."
                ;;
            sd|file)
                if [ "$FLASH" = "sd" ]; then
                    upload_sd
                else
                    write_firmware_file
                fi
                configure_all
                setup_finisher
                step "Almost done"
                print_power_cycle
                ;;
        esac
        ;;
esac
