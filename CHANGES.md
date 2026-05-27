# Changes from upstream M5PaperColor-UserDemo

Complete file-by-file accounting of how this fork diverges from [m5stack/M5PaperColor-UserDemo](https://github.com/m5stack/M5PaperColor-UserDemo) at `0b3d5ef` (release v1.0.1).

The history is structured so that the first three commits are pure bug fixes
suitable for upstream consumption (see [PR #1](https://github.com/m5stack/M5PaperColor-UserDemo/pull/1)),
and the rest are opinionated changes that make this fork a single-purpose
local photo album.

## Commit topology

```
upstream/main (0b3d5ef "update firmware v1.0.1")
  │
  ├─ fix: enable TinyUSB suspend/resume callback Kconfigs
  ├─ fix: bump LWIP_MAX_SOCKETS so the HTTP server can actually start
  ├─ fix: initialize mDNS once at app_server_init instead of on first AP client
  │                                                  ↑
  │                              branch fix/upstream-bugs ends here (PR target)
  │
  ├─ feat(server): remove EzData / cloud-push mode and consolidate to single-purpose UI
  ├─ feat(wifi): STA-first boot, drop the always-on open AP
  └─ docs: README, CHANGES, sdkconfig commentary
                                                     ↑
                                            branch main (this fork) ends here
```

## Upstream-targeted bug fixes

### 1. TinyUSB suspend/resume Kconfigs

**File:** `sdkconfig.defaults`

**Symptom:** Fresh `idf.py build` on a clean clone fails with:

```
error: 'TINYUSB_EVENT_SUSPENDED' was not declared in this scope
error: 'TINYUSB_EVENT_RESUMED'   was not declared in this scope
```

**Cause:** `main/hal/storage/hal_storage.cpp:151,156` uses those enum values
unconditionally. `espressif/esp_tinyusb` ≥ 2.x gates them behind Kconfigs.
`dependencies.lock` doesn't pin `esp_tinyusb`, so the component manager
resolves the latest available version and the symbol references break.

**Fix:** Add `CONFIG_TINYUSB_SUSPEND_CALLBACK=y` and
`CONFIG_TINYUSB_RESUME_CALLBACK=y` to `sdkconfig.defaults`.

### 2. LWIP socket budget too small for httpd

**File:** `sdkconfig.defaults`

**Symptom:** Device boots, AP comes up, DHCP hands out leases — but nothing
answers on port 80. Captive portal and LAN UI both unreachable. Error logs
only to UART (invisible to anyone debugging over USB):

```
E httpd: Config option max_open_sockets is too large
        (max allowed 7, 3 sockets used by HTTP server internally)
        Either decrease this or configure LWIP_MAX_SOCKETS to a larger value
E app_server: httpd start fail
```

**Cause:** `main/apps/app_server/app_server.cpp:1418` sets
`hc.max_open_sockets = 13`. The IDF default `LWIP_MAX_SOCKETS=10` minus 3
reserved internally = 7 available, so `httpd_start()` returns
`ESP_ERR_INVALID_ARG` and never binds port 80.

**Fix:** Set `CONFIG_LWIP_MAX_SOCKETS=16` so 13 + 3 fits.

### 3. mDNS initialized only on first AP client

**File:** `main/apps/app_server/app_server.cpp`

**Symptom:** `papercolor.local` doesn't resolve on the LAN. Intermittent: starts
working as soon as any phone briefly associates with the device's softAP, then
stays working — making the bug easy to miss in development.

**Cause:** `mdns_init()` / `mdns_hostname_set()` / `mdns_instance_name_set()`
lived inside the `WiFiEvent::AP_STA_CONNECTED` event handler. Until a station
joined the softAP, mDNS was never started.

**Fix:** Move the init to `app_server_init`, immediately after URI handlers are
registered. The mdns component watches netif up/down events itself, so a single
init at boot covers both STA and AP transitions cleanly. Also added an
`_http._tcp` service advertisement so the device is discoverable in Bonjour
browsers (Finder Network sidebar, `dns-sd -B _http._tcp`, etc.). The
`AP_STA_CONNECTED` handler now only logs.

## Fork-specific opinionated changes

### 4. Remove EzData / cloud-push mode

**Files:**

- `main/apps/app_server/app_server.cpp`
  - Removed `#include "apps/ezdata_photo_push/ezdata_photo_push.h"` and
    `#include "hal/ezdata/hal_ezdata.h"`
  - Removed the `MODE_ID_EZDATA` entry from `k_supported_modes`, so
    `/api/modes` now returns only the photo album
  - Removed the two `/api/mode/mode_2/config` route entries
    (GET / POST)
  - Removed `h_mode2_cfg_get()` (which called `ezdata_is_connected()` and
    exposed `hal.device_token` over HTTP)
  - Simplified `h_device_ready()` since `can_enter_mode` no longer depends on
    a STA-connectivity check (only LOCAL exists, and LOCAL doesn't require
    network for "ready")

- `main/apps/app_server/index.html`
  - Removed the landing page (mode picker), the mode_2 config panel
    (EzData token / dashboard URL / QR code), the mode_3 "Coming Soon"
    placeholder, the mode-switch modal, and the "Modes" button on the
    bottom bar
  - Removed all EzData JavaScript: the `EZDATA_*` URL/token constants, the
    QR-generator helpers (`loadEzdataQrLibrary`, `buildQrSvgPath`,
    `renderQrSvg`, `renderEzdataQrCode`), the `loadMode2Config` /
    `startEzdataPolling` / `stopEzdataPolling` polling loop, and the
    `.ezdata-dot` CSS
  - Rewrote `init()` to enter mode_1 directly, nudging the backend with
    `POST /api/mode/switch { mode: "mode_1" }` if the stored mode disagrees
  - Removed the unreachable `goToLanding()`, `selectLandingMode()`,
    `showModeSwitch()`, `hideModeSwitch()`, `switchMode()` functions
  - Removed the `updateStatusBar()` branch that hid the Wi-Fi indicator
    whenever `currentMode === "mode_1"` (made sense when mode_1 meant
    "AP-only", doesn't anymore)
  - Made the settings modal's Wi-Fi section always visible (was hidden in
    mode_1 under the AP-only assumption)
  - Marked `#mode-page` as the initial active page (`#landing-page` is gone)

The EzData C++ source files (`main/apps/ezdata_photo_push/*`,
`main/hal/ezdata/*`) and the `APP_MODE_EZDATA` enum value are still in the
tree and compiled into the binary. They're unreachable from the UI but bloat
the binary by a few KB; a future cleanup can delete them. This was an
intentional "Layer B" change to minimize blast radius.

### 5. STA-first boot policy

**Files:**

- `main/apps/app_manager/app_manager.cpp`
  - **Boot path** (`app_manager_start`): if `wifi_ssid` is saved, set
    `WiFiMode::STA` and call `WiFi.connect(ssid, pass, 15s)` directly. If
    that succeeds, never bring up the AP (`need_ap = false`). If it fails
    (or no creds saved), call `ensure_apsta_started()` as a fallback for
    onboarding.
  - **Boot-time migration**: if `hal.settings.current_mode` is left as
    `"mode_2"` in NVS from a prior factory-firmware install, coerce it to
    `"mode_1"` and persist, so the device boots into the only remaining mode
    instead of trying to start the removed EzData mode controller.
  - **`switch_app_mode`**: removed the `else { disconnect_sta_keep_ap_internal(); }`
    branch that fired when switching to LOCAL. That was the mechanism in
    the upstream firmware that made "local mode" and "LAN-reachable" mutually
    exclusive by design.
  - **`mode_requires_sta`**: changed from `mode == APP_MODE_EZDATA` to
    `mode != APP_MODE_NONE`. With EzData gone, the prior implementation made
    the helper false in every reachable code path, silently disabling the
    boot-time STA connect, the periodic STA reconnect loop, and the QR-code
    fallback decision.
  - **QR-code display**: the `need_qrcode` decision now mirrors `need_ap`, so
    the join-AP QR code only appears on the e-paper when the AP is actually
    serving onboarding.

- `main/apps/app_manager/app_manager.h`
  - Flipped `WIFI_AP_AUTO_OFF_ENABLE` from `0` to `1` as a belt-and-suspenders
    safety net. In the common case STA succeeds at boot and the AP is never
    started, so the auto-off path never runs; but if STA initially fails and
    recovers later (network flap during boot), the AP brought up as fallback
    gets cleaned up automatically.
  - Reduced `WIFI_AP_AUTO_OFF_TIMEOUT_MIN` from `10` to `1`.

### 6. Documentation

**Files:**

- `README.md`: rewritten to describe the fork's purpose (single-mode LAN
  photo frame), the difference from upstream, the build/flash flow including
  the TinyUSB-MSC flashing quirk, the first-run onboarding flow, and the
  known caveats (open AP during onboarding, EzData source files still
  linked, console on UART).
- `CHANGES.md`: this file.
- `sdkconfig.defaults`: added an inline comment to the Console UART section
  explaining the TinyUSB MSC interaction with USB-Serial-JTAG, since the
  flashing workflow depends on understanding that.
