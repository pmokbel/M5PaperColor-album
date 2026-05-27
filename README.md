# M5PaperColor — Local Photo Album

A focused firmware for the [M5Stack PaperColor](https://docs.m5stack.com/en/products/sku/C151) (SKU: C151). One purpose: **a photo frame on your home network that you upload pictures to from any browser.**

This is a fork of [m5stack/M5PaperColor-UserDemo](https://github.com/m5stack/M5PaperColor-UserDemo) with the broken bits fixed, the cloud half removed, and the open-AP exposure tightened up.

---

## What it does

1. Boot — connect to your home Wi-Fi (STA).
2. Open `http://papercolor.local/` (or the device IP) from any device on the LAN.
3. Drag a photo in, hit **Upload & Display**. Done.

That's it. No app, no cloud account, no QR code binding flow.

## Hardware

- M5Stack PaperColor (ESP32-S3, 8 MB OPI PSRAM, 16 MB flash, 4" Spectra 6 color e-paper)
- USB-C cable for first-time flashing

## Build & flash

Requires [ESP-IDF v5.5.1](https://docs.espressif.com/projects/esp-idf/en/v5.5.1/esp32s3/index.html).

```bash
git clone https://github.com/pmokbel/M5PaperColor-album.git
cd M5PaperColor-album
git submodule update --init --recursive
. $IDF_PATH/export.sh
idf.py set-target esp32s3
idf.py build

./tools/flash.sh       # then power-cycle the device when prompted
```

Set `PAPERCOLOR_PORT` in your shell if `/dev/cu.usbmodem*` isn't right for you (Linux, multiple devices, etc.) — details in [the next section](#why-the-helper-script).

### Why the helper script?

The ESP32-S3's USB-Serial-JTAG (what `esptool` talks to) and USB-OTG (which TinyUSB MSC uses to expose the device as a USB drive) share the single USB-C wire. The boot ROM exposes USB-Serial-JTAG for ~1–2 seconds at every power-on, then the firmware initializes TinyUSB MSC and the CDC endpoint disappears. **`esptool` can only reach the chip during that boot window.**

`tools/flash.sh` polls for the configured port and dispatches `idf.py` the moment it appears. Power-cycle the device while the script is waiting and it just works.

Set the port once per shell so it's not repeated on every invocation:

```bash
export PAPERCOLOR_PORT=/dev/cu.usbmodem21101   # macOS, specific device
# or PAPERCOLOR_PORT='/dev/ttyACM*' on Linux

./tools/flash.sh           # app-flash — preserves NVS / saved photos (default)
./tools/flash.sh full      # bootloader + partition table + app + storage
./tools/flash.sh erase     # wipe everything, then full flash
./tools/flash.sh monitor   # open serial monitor (catches USB-CDC at boot)
```

If `PAPERCOLOR_PORT` is unset, the script falls back to `/dev/cu.usbmodem*` — fine for most macOS setups with a single device plugged in.

## First-run onboarding

1. After flashing, the device boots and broadcasts an **open** Wi-Fi network called `PaperColor-XXXXXX` (last 6 of the MAC).
2. Join that AP from a phone or laptop. A captive portal pops up.
3. Pick your home Wi-Fi, enter the password, hit Confirm.
4. Device connects to your home network. The AP is no longer broadcast (open-AP exposure is bounded to the initial onboarding window).
5. Open `http://papercolor.local/` from any device on your LAN.

If you ever need to re-onboard (changed router, etc.), **long-press the power button** on the device — that re-enables the AP and shows the join QR code on the e-paper.

## Differences from the upstream UserDemo

This fork is reduced to a single purpose. Three groups of changes:

### Bugs we fixed and pushed upstream

These would hit anyone building the original repo from a clean clone. Submitted as a PR to upstream ([m5stack/M5PaperColor-UserDemo#1](https://github.com/m5stack/M5PaperColor-UserDemo/pull/1)):

- **Builds against current dependencies.** Adds `CONFIG_TINYUSB_SUSPEND_CALLBACK` / `CONFIG_TINYUSB_RESUME_CALLBACK` — the source uses these enum values unconditionally, but `esp_tinyusb` ≥ 2.x gates them behind Kconfigs.
- **HTTP server actually starts.** Adds `CONFIG_LWIP_MAX_SOCKETS=16` — the source asks for `max_open_sockets=13`, but the IDF default `LWIP_MAX_SOCKETS=10` only allows 7, so `httpd_start` silently fails and port 80 never binds.
- **mDNS works in STA mode.** The original initializes mDNS only on `AP_STA_CONNECTED` (i.e. only after a phone joins the AP). This fork initializes it once at boot in `app_server_init`, so `papercolor.local` resolves on the LAN without anyone needing to join the AP first. Also adds an `_http._tcp` service so the device shows up in Bonjour browsers.

### Opinionated changes (the reason this is a separate fork, not just a PR)

- **No cloud.** The EzData / "cloud photo push" mode is removed — UI panel, JS, server routes, all gone. The upstream firmware has two modes (local AP + cloud); we keep only the local album.
- **STA-first boot.** The upstream firmware brings up an open APSTA every boot regardless of need. This fork only enables the AP when actually needed for onboarding (no saved creds, or STA connect failed). Open-AP exposure is bounded to a brief setup window per power cycle, not "always on."
- **LAN access to the upload UI.** The upstream firmware *deliberately* disconnects STA when running the local-album mode, which makes the upload UI reachable only via AP. This fork removes that disconnect — local album mode keeps STA up, so you upload from your laptop on the LAN like a normal networked appliance.
- **Single-mode UI.** The mode picker, mode-switch modal, and "Modes" bottom-bar button are gone. The page loads straight into the upload UI.

See [CHANGES.md](CHANGES.md) for a complete file-by-file accounting.

## Known caveats

- The AP, when it does come up for onboarding, is still **open** (no WPA password). This is the upstream's onboarding pattern. The exposure window is now bounded — boot before STA settles, or after an explicit long-press — but it's there. A future change could derive a per-device WPA password from the MAC and put it in the on-screen QR code.
- The EzData C++ source files (`main/apps/ezdata_photo_push/`, `main/hal/ezdata/`) are still compiled into the binary. They're unreachable from the UI but bloat the binary. A full cleanup is on the TODO.
- The first-ever boot after a chip erase shows a one-time factory-guide image and powers off — by design, inherited from upstream. Press the power button again to actually start the firmware.
- Runtime serial logs go to UART (GPIO 5/4), not USB-CDC — USB-CDC is occupied by TinyUSB MSC after boot (see [Build & flash](#build--flash)). Attach a UART probe to GPIO 5/4 if you need to read runtime logs.

## License

MIT, same as upstream. See [LICENSE](LICENSE).

## Credits

Forked from [m5stack/M5PaperColor-UserDemo](https://github.com/m5stack/M5PaperColor-UserDemo).

This project references the following open-source libraries:

- https://github.com/m5stack/M5GFX
- https://github.com/m5stack/M5Unified
- https://github.com/m5stack/M5PM1
- https://components.espressif.com/components?q=esp_tinyusb
- https://components.espressif.com/components/espressif/qrcode
- https://components.espressif.com/components/espressif/mdns
