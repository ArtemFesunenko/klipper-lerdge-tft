# Klipper on Lerdge boards – with the stock Lerdge screen

**English** | [Русский](README.ru.md)

Use the original Lerdge screen – the 3.5" color touch screen, with or
without the Lerdge knob module – with [Klipper](https://www.klipper3d.org/):
run a full [KlipperScreen](https://github.com/KlipperScreen/KlipperScreen) on
it, or the built-in Klipper menu. Everything installs with one script.

<p align="center">
  <img src="docs/images/klipperscreen.png" alt="KlipperScreen on the Lerdge screen" width="480"><br>
  <em>KlipperScreen mirrored to the 480×320 Lerdge screen</em>
</p>

<p align="center">
  <img src="docs/images/menu_status.png" alt="Built-in menu: status" width="320">
  <img src="docs/images/menu_list.png" alt="Built-in menu: list" width="320"><br>
  <em>Built-in Klipper menu mode with touch buttons</em>
</p>

## Contents

- [Features](#features)
- [Supported hardware](#supported-hardware)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
  - [1. Download](#1-download)
  - [2. Run the installer](#2-run-the-installer)
  - [3a. First installation (board runs the stock Lerdge firmware)](#3a-first-installation-board-runs-the-stock-lerdge-firmware)
  - [3b. Board already runs Klipper](#3b-board-already-runs-klipper)
  - [3c. Switching the printer off and on](#3c-switching-the-printer-off-and-on)
  - [4. Touch calibration](#4-touch-calibration)
- [Using the screen](#using-the-screen)
- [Configuration](#configuration)
- [Updating](#updating)
- [Serial baud rate](#serial-baud-rate)
- [Load on the printer board](#load-on-the-printer-board)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)
- [Technical details](#technical-details)
- [Development](#development)
- [Credits and license](#credits-and-license)

## Features

- **KlipperScreen on the Lerdge screen** – a second KlipperScreen instance
  runs on a virtual 480×320 display on the host and is mirrored to the
  printer's screen. All KlipperScreen features work: printing from files,
  temperatures, moving, extruding, macros, settings, themes.
- **Or the built-in Klipper menu** – the standard Klipper display and menu,
  rendered as a large 16×6 character screen with on-screen touch buttons
  and tappable menu rows. Nothing extra runs on the host.
- **Touch gestures** – tap to click, swipe to scroll lists, hold for a
  long press. Touch calibration with five targets.
- **Knob module support** – the optional Lerdge rotary encoder with push
  button works in both modes: it moves through the menu (or the buttons of
  KlipperScreen), a click selects, a long click goes back.
- **Works after errors** – the touch panel is read by the board itself, so
  after a Klipper shutdown you can still press *Firmware Restart* on the
  screen.
- **Firmware updates from the host** – the installer writes the firmware
  to the TF card in the board, the stock Lerdge bootloader installs it when
  the printer is switched on, and the file is removed automatically. After
  the first installation you never need to take the card out.
- **Fast and safe serial link** – up to 1.5 Mbaud between the host and the
  board, with an automatic fallback to 250000 baud if the wiring can not
  handle it.
- **One installer** – patches your existing Klipper, builds and installs
  the firmware, writes the configuration and sets up the services.
- Coexists with an HDMI screen running its own KlipperScreen.

## Supported hardware

| Board | Status | Notes |
| --- | --- | --- |
| **Lerdge-K** | ✅ Tested (Anycubic Predator, Orange Pi PC host) | Touch interrupt pin PG12 |
| **Lerdge-X** | ⚠️ Should work, not tested | Same screen and bootloader layout; touch CS on PB6, no touch interrupt pin (pins from Marlin) |
| Lerdge-S | ❌ Not supported by the installer | Same screen; bootloader file name unknown – see [docs/hardware.md](docs/hardware.md) |

Lerdge boards use one type of screen: the Lerdge 3.5" 480×320 color touch
screen (ST7796S controller, resistive XPT2046 touch). Lerdge also sells a
**knob module** – a rotary encoder with a push button that is fitted to the
same touch screen (kit "screen + knob") – which is supported as well. There
is no separate knob-only screen. ILI9488 and ILI9341 based screens are
supported by the driver too (detected automatically).

**Host:** any Linux computer that already runs Klipper and Moonraker
(Raspberry Pi, Orange Pi, other single board computers or a PC) with a
Debian based OS (Raspberry Pi OS, Armbian, MainsailOS, FluiddPI, Debian,
Ubuntu). The board can be connected through its USB port or directly to the
UART pins (USART1, PA9/PA10). Both work the same way: the USB port of
Lerdge boards is a USB-serial chip on the same USART1, so the firmware,
the baud rate and everything else are identical – only the port name in
`printer.cfg` differs (`/dev/serial/by-id/usb-1a86_...` or `/dev/ttyUSB0`
for USB, for example `/dev/ttyS3` for the UART of an Orange Pi).

## How it works

Klipper normally only supports small character and monochrome displays.
The Lerdge screen is a plain TFT panel connected to the parallel memory bus
(FSMC) of the board's STM32F407 microcontroller, so this project adds:

- **MCU firmware code** (`src/stm32/tft_fsmc.c`) – drawing primitives for
  the FSMC display (fills, scaled bitmaps, an RLE compressed pixel stream)
  and a touch panel reader.
- **A Klipper display module** (`lerdge_tft`) – initializes the screen,
  renders the Klipper menu, handles touch input and calibration, and offers
  an API for external programs.
- **A mirror service** (`lerdge_mirror.py`) – takes the picture of a
  KlipperScreen running on a virtual X display (Xvfb), sends only the
  changed areas (compressed) to the board, and turns touches into mouse
  clicks and scrolling.
- **Lerdge bootloader support** – firmware encryption, a "lerdge-k"/
  "lerdge-x" target for Klipper's `flash-sdcard.sh`, and a fix for the RAM
  layout the bootloader needs.

The changes are kept as a patch series (`patches/`) on top of the official
Klipper. The installer applies them to your Klipper checkout on a local
branch called `lerdge`.

## Requirements

- Klipper and Moonraker installed on the host the usual way (for example
  with [KIAUH](https://github.com/dw-0/kiauh)) in `~/klipper` and
  `~/printer_data` (other locations can be given to the installer).
- A working `printer.cfg` for your printer.
- A **TF (micro SD) card formatted as FAT32**, any size, that stays in the
  board's TF slot. The Lerdge bootloader installs firmware from it.
- About 300 MB of free space on the host for the ARM compiler, and for the
  KlipperScreen mode about 150 MB of RAM.

## Installation

### 1. Download

Log in to the host (SSH) as the user that runs Klipper and run:

```bash
cd ~
git clone https://github.com/ArtemFesunenko/klipper-lerdge-tft.git
cd klipper-lerdge-tft
```

### 2. Run the installer

```bash
./install.sh
```

The installer asks a few questions (all have sensible defaults):

| Question | Answer |
| --- | --- |
| Board type | `k` for Lerdge-K, `x` for Lerdge-X |
| Show KlipperScreen on the Lerdge screen | `y` for KlipperScreen, `n` for the built-in menu |
| Knob module fitted | `y` if the Lerdge rotary encoder is installed on the screen |
| MCU serial baud rate | `1500000` (recommended for KlipperScreen) or `250000` |
| Firmware installation | `file` for the first installation, `sd` if the board already runs Klipper (and has a TF card) |

It then applies the patches to Klipper, installs the needed packages
(ARM compiler, and for KlipperScreen: Xvfb, numpy, python-xlib) and builds
the firmware.

All questions can also be answered with options, for example:

```bash
./install.sh --board k --mirror --baud 1500000 --flash file
```

Run `./install.sh --help` for all options.

### 3a. First installation (board runs the stock Lerdge firmware)

Choose `file`. The installer creates
`~/lerdge_firmware/Lerdge_K_system/Firmware/Lerdge_K_firmware_force.bin`
(`Lerdge_X_...` for Lerdge-X), configures Klipper and prints what to do:

1. Copy the whole `Lerdge_K_system` folder to the **root** of the FAT32 TF
   card (the installer prints an `scp` command for this) and insert the
   card into the TF slot of the Lerdge board. **Leave it there** - it is
   used for later updates too.
2. If the `[mcu]` section of `printer.cfg` was written for the stock
   firmware connection, set `serial:` to the port of the board (for
   example `/dev/ttyUSB0`, `/dev/serial/by-id/...` or the UART of your host
   such as `/dev/ttyS3`).
3. Switch the printer off and on (see [3c](#3c-switching-the-printer-off-and-on)).

### 3b. Board already runs Klipper

If the board already runs a Klipper firmware built for the Lerdge
bootloader (64KiB bootloader offset) and a FAT32 card is in its TF slot,
choose `sd`. The installer writes the new firmware to the card through the
running firmware and configures Klipper. Then switch the printer off and
on (see [3c](#3c-switching-the-printer-off-and-on)).

### 3c. Switching the printer off and on

The Lerdge bootloader reads the card only after the power was off (the
card has to leave the mode the installer used to write it), so the printer
has to be switched off and on once after every firmware installation:

- **Host powered by the printer:** shut the host down first
  (`sudo poweroff`), wait until it is off, switch the printer off, wait 10
  seconds and switch it on. When the host starts, a one-shot service checks
  the new firmware and removes the file from the card before Klipper
  starts - nothing else to do. The result is logged to
  `~/printer_data/logs/lerdge-firmware.log`.
- **Host with its own power supply:** switch the printer off and on, then
  run `~/klipper-lerdge-tft/install.sh --finish`.

The bootloader installs the firmware in a few seconds (it may show
messages about logo/UI/font updates - they are harmless).

### 4. Touch calibration

On the first start the Lerdge screen shows five crosses: tap their centers
(hold your finger for a moment on each). Then save the result:

```
SAVE_CONFIG
```

Recalibrate any time with the `TOUCH_CALIBRATE` command.

## Using the screen

**KlipperScreen mode**

- tap – click a button
- swipe up/down – scroll lists (files, macros, settings)
- hold your finger still for 0.6 s – long press

If the mirror service stops, the screen falls back to the built-in menu
after 20 seconds and returns to KlipperScreen automatically.

**Built-in menu mode**

- tap the status screen – open the menu
- ▲ / ▼ – move in the menu, or change the value while editing (hold to
  repeat)
- ✓ – select (hold for a long click), ◄ – back
- tap a menu row to select it, tap it again to activate it

**Knob module**

| Action | KlipperScreen mode | Built-in menu mode |
| --- | --- | --- |
| Turn | Move the highlight between buttons | Move in the menu / change the value |
| Click | Press the highlighted button | Select |
| Long click (0.8 s) | Back to the main screen | Long click (menu action) |

If the screen backlight is off (`backlight_timeout`), the first touch or
knob action only switches it on.

**G-code commands**

| Command | Description |
| --- | --- |
| `TOUCH_CALIBRATE` | Calibrate the touch panel (then `SAVE_CONFIG`) |
| `TFT_REDRAW` | Redraw the screen |
| `TFT_REDRAW INIT=1` | Re-initialize the display controller |

## Configuration

The display is configured in `~/printer_data/config/lerdge_tft.cfg`, which
is included from `printer.cfg`. Useful options:

| Option | Default | Description |
| --- | --- | --- |
| `rotate_180` | `False` | Rotate the picture (the touch calibration is kept) |
| `touch_tap_activates` | `False` | Built-in menu: activate a row with a single tap |
| `backlight_timeout` | `0` | Switch the backlight off after this many seconds without touch (0 = never) |
| `beeper_pin` | – | Short click on every touch (Lerdge-K: `PC7`, Lerdge-X: `PD12`) |
| `touch_pressure_threshold` | `300` | Lower it if light touches are not detected |
| `encoder_pins`, `click_pin` | commented out | Knob module (Lerdge-K: `^PG11, ^PG10` and `^!PG9`; Lerdge-X: `^PE4, ^PE3` and `^!PE2`) – enabled by the installer when you answer that the knob is fitted |
| `encoder_steps_per_detent` | `4` | Set to `2` if one knob click moves two steps |
| `controller` | `auto` | `st7796`, `ili9488` or `ili9341` if auto detection fails |
| `invert_colors` | controller default | Fix inverted (negative) colors |
| `background_color`, `text_color`, `button_color`, … | | Built-in menu colors (`RRGGBB`) |
| `fsmc_write_addset`, `fsmc_write_datast` | `4`, `10` | Slower bus timing if the picture has artifacts |

KlipperScreen on the Lerdge screen has its own configuration file,
`~/printer_data/config/KlipperScreen-lerdge.conf` (theme, font size, …,
see the [KlipperScreen documentation](https://klipperscreen.readthedocs.io/en/latest/Configuration/)).

The installer copies `lerdge_tft.cfg` and `KlipperScreen-lerdge.conf` only
if they do not exist yet, so your changes are kept when you run it again.

## Updating

Klipper runs on the local `lerdge` branch, so **do not update Klipper from
Mainsail/Fluidd** (Moonraker shows the Klipper repository as invalid or
diverged – that is expected). To update Klipper and this project:

```bash
cd ~/klipper-lerdge-tft
git pull
./install.sh --update
```

This fetches the latest upstream Klipper, re-applies the patches, updates
the Klipper python packages, rebuilds the firmware and writes it to the TF
card - then switch the printer off and on as in
[3c](#3c-switching-the-printer-off-and-on). The other components (Moonraker, Mainsail/Fluidd,
KlipperScreen) can be updated from the web interface as usual.

## Serial baud rate

A full KlipperScreen picture is about 30 KB after compression – about
0.2 s at 1500000 baud but 1.4 s at 250000 baud. 1500000 works without any
error on the exact clocks of the STM32F407 (84 MHz / 1.5 MHz = 56) and of
most host UARTs (for example 24 MHz on Allwinner SoCs) and USB serial chips.

The firmware has a safety net: until it receives the first valid message
it switches between 1500000 and 250000 baud every 20 seconds. If the host
can not connect at 1500000 (long or poor wiring), set `baud: 250000` in
the `[mcu]` section of `printer.cfg` and restart Klipper – the board will
connect at 250000. To use 250000 permanently, run
`./install.sh --update --baud 250000`.

## Load on the printer board

The screen shares the board's microcontroller and its serial link with
the printing, so the display is designed to always yield to Klipper:

- **Steps are not affected directly.** Klipper generates the step pulses
  in timer interrupts from step data that is queued ahead; the display
  commands run in the MCU's normal task loop.
- **Short commands.** Every display command writes at most 1024 pixels
  (about 0.1 ms) and a touch read runs one conversion (about 65 µs) at a
  time, within the limits Klipper's
  [code overview](https://www.klipper3d.org/Code_Overview.html) gives for
  MCU tasks.
- **Background priority.** Display messages are sent with the same
  background priority as Klipper's own displays, so any step data that is
  due soon goes first, and the mirror pauses while the serial queue is
  busy.
- **Only changes are sent.** The mirror sends the changed 16×16 tiles of
  the picture, RLE compressed; a static picture costs nothing. While
  printing, it updates at most twice per second and uses at most 20% of a
  UART link (`--print-share` of `lerdge_mirror.py`).

Measured on a Lerdge-K at 1500000 baud (link capacity about 150 KB/s):

| Situation | MCU link traffic | Share of the link |
| --- | --- | --- |
| No display traffic | 0.2–0.3 KB/s | 0.2% |
| KlipperScreen main screen (live temperature graph) | 3.3–3.8 KB/s | 2.5% |
| Switching KlipperScreen panels continuously | 6.2–6.6 KB/s | 4.4% |
| For comparison: one hour print (no display) | 0.8 KB/s median, 5.4 KB/s peak | 3.6% peak |

In these cases the MCU was busy 1–2% of the time (the difference is
within the measurement noise). While someone quickly switches panels by
touch it peaks at about 11% for a few seconds: redrawing the whole screen
is about 150,000 pixels or 15 ms of MCU work, split into pieces of at most
0.1 ms. Not a single byte had to be retransmitted. If you want the absolute
minimum of extra load, use the built-in Klipper menu mode
(`./install.sh --no-mirror`): it only redraws the text that changes.

## Uninstalling

```bash
~/klipper-lerdge-tft/uninstall.sh
```

This removes the KlipperScreen mirror services, removes the display from
`printer.cfg` (backups are kept) and switches Klipper back to its upstream
branch. The board keeps the Lerdge firmware until you flash another one
(build it with `make menuconfig` – STM32F407, 64KiB bootloader, 25 MHz
crystal, USART1 – and install it with a TF card).

## Troubleshooting

**The screen stays white or black**
Check `~/printer_data/logs/klippy.log` for `lerdge_tft: display id ...`.
If the id is `0000` or `ffff`, set `controller: st7796` in
`lerdge_tft.cfg`. Make sure the board runs the patched firmware (the
installer prints the version).

**Klipper can not connect to the board**
If you selected 1500000 baud, the wiring may not handle it: set
`baud: 250000` in `[mcu]` (see [Serial baud rate](#serial-baud-rate)).
If the firmware does not start at all, install the firmware file again
with a TF card (`./install.sh --flash file`).

**Touches are not detected or land in the wrong place**
Run `TOUCH_CALIBRATE` and `SAVE_CONFIG`. If light touches are missed,
lower `touch_pressure_threshold`. On Lerdge-X check `touch_cs_pin: PB6`.

**KlipperScreen does not appear on the Lerdge screen**
Check the services and their logs:

```bash
systemctl status lerdge-xvfb KlipperScreen-lerdge lerdge-mirror
journalctl -u lerdge-mirror -n 50
tail -50 ~/printer_data/logs/KlipperScreen-lerdge.log
```

**The firmware update fails**
"No usable TF card": insert a FAT32 formatted card into the board's TF
slot. "Could not connect to the board": the board does not run Klipper
(use `--flash file`) or the baud rate in `[mcu]` is wrong. If the board
still runs the old firmware after switching it off and on, check
`~/printer_data/logs/lerdge-firmware.log` and that the `Lerdge_K_system`
folder is in the root of the card.

**The knob turns the wrong way**
Swap the two pins in `encoder_pins` in `lerdge_tft.cfg`. To add the knob
later, run the installer again and answer `y` to the knob question (or
uncomment `encoder_pins`/`click_pin` and add `keyboard_navigation: True`
to the `[main]` section of `KlipperScreen-lerdge.conf`).

**The picture is upside down**
Set `rotate_180: True` in `lerdge_tft.cfg`.

**General advice:** always shut the host down (`sudo poweroff` or from
Mainsail/Fluidd) before switching the printer off. Cutting the power of a
running Linux host can corrupt its SD card.

## Technical details

See [docs/hardware.md](docs/hardware.md) for the pinout, the display and
touch details, the Lerdge bootloader behavior and how everything was found
(analysis of the stock Lerdge-K firmware V4.3.3 and bootloader V1.0.4).

## Development

The Klipper changes live in `patches/` as a `git format-patch` series. To
work on them, apply the patches with `./install.sh --build-only`, change
and commit on the `lerdge` branch of your Klipper checkout, then export
the series again:

```bash
tools/export-patches.sh ~/klipper <upstream base commit> lerdge
```

## Credits and license

- [Klipper](https://github.com/Klipper3d/klipper) by Kevin O'Connor and
  contributors – this project is a set of patches for it.
- [KlipperScreen](https://github.com/KlipperScreen/KlipperScreen).
- Pin information for Lerdge-X and Lerdge-S from
  [Marlin](https://github.com/MarlinFirmware/Marlin), the firmware
  encryption algorithm is the one used by Marlin's Lerdge build scripts.

Licensed under the GNU General Public License v3.0, like Klipper – see
[LICENSE](LICENSE).
