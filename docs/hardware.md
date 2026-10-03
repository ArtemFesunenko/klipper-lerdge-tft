# Lerdge hardware notes

These notes describe what was found by analyzing the stock Lerdge-K
firmware V4.3.3 (application) and the Lerdge-K bootloader V1.0.4 read from a
board, and by comparing with the Marlin pin definitions for Lerdge boards.

## Microcontroller and clocks

- STM32F407ZGT6, 1 MiB flash, 192 KiB RAM (128 KiB main RAM used by Klipper)
- 25 MHz crystal (`PLLM = 25`, 168 MHz system clock, APB2 84 MHz)
- Stock bootloader in the first 64 KiB, application at `0x08010000`
- Host connection on USART1 (PA10 RX / PA9 TX)

## Display

| Signal | Pin |
| --- | --- |
| Controller | ST7796S, 480×320, RGB565, display inversion on |
| Bus | FSMC bank 1, 16 bit, NE1 = PD7 |
| RS (data/command) | A16 = PD11 → command register `0x60000000`, data `0x60020000` |
| Data bus | PD14, PD15, PD0, PD1, PE7–PE15, PD8–PD10 (D0–D15), NOE PD4, NWE PD5 |
| Reset | PD6 |
| Backlight | PD3 |

FSMC timing used by the stock firmware: write address setup 4 and data
setup 10 HCLK cycles (the StdPeriph structure contains an address setup of
20, which overflows the 4 bit field).

The ST7796S initialization sequence of the stock firmware is used
unchanged (`ST7796S_INIT` in `lerdge_tft.py`), with MADCTL `0x28`
(landscape) or `0xE8` (rotated 180°). The controller is detected by reading
command `0xD3` (`0x7796`; `0x9488` and `0x9341` are recognized too).

## Touch panel

| | Lerdge-K | Lerdge-X / Lerdge-S |
| --- | --- | --- |
| Controller | XPT2046 | XPT2046 |
| SCK / MISO / MOSI | PB3 / PB4 / PB5 (SPI3) | PB3 / PB4 / PB5 |
| CS | PG15 | PB6 |
| PENIRQ | PG12 | – |

The stock firmware takes 12 samples per axis with commands `0x90`/`0xD0`,
sorts them and averages the middle 8. Its default calibration is
`x = -0.2298·raw90 + 0.000275·rawD0 + 510.5`,
`y = 0.00034·raw90 - 0.1555·rawD0 + 336.25` (11 bit raw values); the
calibration measured on a real panel was within a few percent of this.

## TF card, beeper, other

| | Lerdge-K | Lerdge-X | Lerdge-S |
| --- | --- | --- | --- |
| TF card (SDIO) | PC8–PC12, PD2 | PC8–PC12, PD2 | PC8–PC12, PD2 |
| TF card detect | PA8 | PA8 | PG15 |
| Beeper | PC7 | PD12 | PD13 |
| Encoder (unused) | PG11, PG10, PG9 | PE4, PE3, PE2 | PC15, PC14, PC13 |

The board also has a 16 MiB SPI NOR flash (Winbond W25Q128, JEDEC
`ef4018`) on SPI1 (PA5/PA6/PA7) with CS on PC4, where the stock firmware
keeps its UI images and fonts.

## Firmware encryption

Firmware files for the bootloader are scrambled byte by byte:

```python
def encrypt_byte(b):
    b = 0xFF & ((b << 6) | (b >> 2))
    i = 0x58 + b
    j = 0x05 + b + (i >> 8)
    return (0xF8 & i) | (0x07 & j)
```

The mapping is a bijection; `scripts/update_lerdge.py -d` decrypts.

## Bootloader (Lerdge-K V1.0.4)

On every start the bootloader:

1. mounts the TF card in **SDIO** mode (`S:`) and a USB stick (`U:`),
2. opens `S:Lerdge_K_system/Firmware/Lerdge_K_firmware_force.bin`; if it
   exists, it is decrypted and written to `0x08010000` – **on every boot**,
   so the file must be removed after an update,
3. reads a flag byte at offset `0x500000` of the SPI flash: if it is not
   `0xAA` it also tries to update the logo (`Lerdge_K_system/UI/Lerdge_LOGO.logo`),
   UI icons (`Lerdge_K_UI.ui`) and fonts (`FONT/UNIGBK.FONT`,
   `FONT/FONT_LIB.DZK`) from the card or the USB stick,
4. starts the application if the word at `0x0800FFF0 + 0x14` points into
   flash.

The flag byte is used by the stock firmware's "update" menu.
`scripts/lerdge_bootflag.py` reads it and can clear it (it is not needed
for firmware updates).

Notes:

- A card that was accessed in SPI mode stays in SPI mode until it loses
  power, and the bootloader (SDIO) can then not read it. The `lerdge-k`/
  `lerdge-x` definitions write the card with software SPI (Klipper's SDIO
  writes failed on the tested board and left the card unresponsive), so
  the printer has to be switched off and on after an upload. The
  installer then verifies the firmware and removes the file at the next
  start of the host (`lerdge-firmware-finish.service`).
- Klipper must keep the last 16 bytes of RAM free
  (`STM32_LERDGE_RAM_RESERVE`, RAM size `0x1FFF0`), otherwise it does not
  start from the Lerdge bootloader.
- The Lerdge-X bootloader expects `Lerdge_X_system/Firmware/Lerdge_X_firmware_force.bin`
  (from Marlin, not verified). For Lerdge-S, Marlin names the file
  `Lerdge_firmware_force.bin`; its folder is unknown.

## Serial link

STM32F407 USART1 runs from APB2 (84 MHz): 1500000 baud is exact
(divider 56), as is 250000 (336). On Allwinner SoCs the UART clock is
24 MHz, giving exact 1500000 baud too.

With `SERIAL_BAUD_FALLBACK` the MCU alternates between the main and the
fallback baud rate every 20 seconds until it receives the first valid
message, so a host using either rate can connect.

## Mirror protocol

`lerdge_mirror.py` reads the Xvfb framebuffer (`-fbdir`, XWD format,
32 bpp), compares 16×16 tiles with the previous frame, merges changed tiles
into rectangles and encodes them as RGB565 PackBits RLE (a header byte with
the high bit set repeats the next color, otherwise literal colors follow),
split into chunks of at most 48 bytes. They are sent with the
`lerdge_tft/draw` API endpoint; the response reports the bytes waiting in
the serial queue for flow control. A typical KlipperScreen frame is about
30 KB (10–12× smaller than raw RGB565).
