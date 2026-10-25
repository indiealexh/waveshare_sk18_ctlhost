# Waveshare SK18 Custom Firmware, Rootfs Image Builder & Flutter Companion Specification

This document specifies the architecture, data models, extended communication protocols, internal `/dev/ttyS1` STM32 UART bridge, Home Assistant two-way WebSocket integration, and Allwinner Tina Linux `IMAGEWTY` rootfs image builder for the custom **Waveshare SK18** firmware (`firmware/`) and cross-platform **Flutter Companion App** (`companion_app/`).

---

## 1. System Architecture Overview

The Waveshare SK18 contains two cooperating processors inside the keypad enclosure:
1. **Allwinner T113-S3 (`sun8iw20p1`, Dual-Core ARM Cortex-A7, 128 MB DDR3, Tina Linux)**:
   - Drives the `1280×720` (`720×1280` native portrait scanout) IPS LCD via `/dev/fb0`.
   - Controls LCD backlight brightness via `/sys/kernel/debug/dispdbg` (`lcd0` / `setbl`).
   - Controls the onboard speaker amplifier via ALSA (`amixer` / `tinyplay`).
   - Manages the onboard 2.4 GHz `wlan0` Wi-Fi interface (`wpa_supplicant`, `wpa_cli`, `udhcpc`).
   - Exposes a USB 2.0 High-Speed CDC-ACM serial port at `/dev/ttyGS0` (`1d6b:0104`).
   - Runs `/data/KeyboardDevice` (launched by `/etc/init.d/rcS` → `/data/appLunch.sh`).
2. **STM32 QMK/VIA Microcontroller (`syk_keyboards_sk18_via.bin`)**:
   - Scans the 18 mechanical switches (`3 rows × 6 columns` in landscape).
   - Exposes a native USB Full-Speed HID Keyboard / Mouse / Consumer interface (`4250:426f`) to the connected host computer.
   - Communicates with the Allwinner T113-S3 over internal UART `/dev/ttyS1` (`115200 8N1`).

### 1.1 T113-Orchestrated Key Dispatch (`KC_NO` Initialization)
By default, the STM32's QMK EEPROM maps physical switches to default HID keycodes. To prevent Home Assistant or host-script buttons from typing unwanted characters on the host computer:
1. On startup, the custom firmware's `Sk18Stm32Bridge` sends opcode `0x05` (`dynamic_keymap_set_keycode`) over `/dev/ttyS1` to set all 18 switch positions (`layer = 0, row = 0..2, col = 0..5`) to **`KC_NO` (`0x0000`)**.
2. Pressing or releasing any physical switch still causes the STM32 to emit an opcode `0x16` (`keyStateChanged`) frame over `/dev/ttyS1` to the T113-S3.
3. The T113-S3 firmware inspects `/mnt/SDCARD/sk18_config.json` for that key's `(col, row)` slot and dispatches:
   - **Home Assistant Action**: Calls the configured Home Assistant WebSocket service (`light`, `switch`, `climate`, `scene`, `script`) directly over `wlan0`.
   - **Hardware HID Hotkey / Media Key (`macro_hotkey`)**: Sends opcode `0x17` (`request_upload_key`) over `/dev/ttyS1` to the STM32.
   - **Text / Keystroke Sequence (`macro_sequence`)**: Steps through `text`, `key_tap`, and `delay_ms` items, emitting opcode `0x17` frames over `/dev/ttyS1`.
   - **Hardware HID Mouse / Scroll (`macro_mouse`)**: Sends opcode `0x18` (`request_mouse_control`) over `/dev/ttyS1` to the STM32.
   - **Host App / Script / URL Launcher (`macro_host_launcher`)**: Broadcasts an asynchronous `macroTriggered` JSON-RPC event over `/dev/ttyGS0` (USB Serial V2) and `:8180/ws` (Wi-Fi WebSocket) to the Flutter companion app.

---

## 2. Internal `/dev/ttyS1` STM32 UART Protocol (`115200 8N1`)

All communication between the Allwinner T113-S3 (`/dev/ttyS1`) and the internal STM32 microcontroller uses a 7-byte framing wrapper around a variable-length payload (`STM32CommunicationObject` at `0x5d808`–`0x5fa58` in stock firmware):

```text
Offset  Size    Value / Formula             Description
------  ------  --------------------------  ------------------------------------------------
0x00    1       0xAA                        Start byte 1
0x01    1       0x55                        Start byte 2
0x02    1       sum(payload) & 0xFF         8-bit unsigned sum of all payload bytes
0x03    1       len(payload) & 0xFF         Payload length N (1..248)
0x04    1       (~len(payload)) & 0xFF      Bitwise one's complement of payload length
0x05    N       payload[0..N-1]             Command opcode (payload[0]) + opcode arguments
0x05+N  1       0xF5                        End byte 1
0x06+N  1       0x5F                        End byte 2
```

### 2.1 STM32 UART Opcodes

| Opcode | Direction | Name | Payload Layout | Description |
| :---: | :---: | :--- | :--- | :--- |
| `0x05` | `T113 → STM32` | `dynamic_keymap_set_keycode` | `[0x05, layer, row, col, kc_hi, kc_lo]` | Sets the QMK keycode in STM32 keymap (`0x0000` = `KC_NO`). |
| `0x0F` | `T113 → STM32` | `macro_set_buffer` | `[0x0F, off_hi, off_lo, len, ...bytes]` | Writes raw QMK macro buffer bytes at offset. |
| `0x16` | `STM32 → T113` | `keyStateChanged` | `[0x16, pressed, row, col, kc_hi, kc_lo]` | Physical switch event (`pressed`: `1` = down, `0` = up). |
| `0x17` | `T113 → STM32` | `request_upload_key` | `[0x17, mode, kc_hi, kc_lo]` | Injects USB HID keycode (`mode`: `1` = press, `0` = release, `2` = tap). |
| `0x18` | `T113 → STM32` | `request_mouse_control` | `[0x18, buttons, dx, dy, wheel_v, wheel_h]` | Injects USB HID mouse button mask, signed `(dx, dy)` movement, and signed `(v, h)` scroll wheel steps. |
| `0x19` | `T113 → STM32` | `bootloader_jump` | `[0x19]` | Jumps STM32 into DFU/bootloader mode. |

---

## 3. Shared Configuration Schema (`/mnt/SDCARD/sk18_config.json`)

The custom firmware persists its full state in `/mnt/SDCARD/sk18_config.json` (with fallback to `/data/sk18_config.json` when running in host simulation or before `/mnt/SDCARD` is mounted).

### 3.1 Top-Level Structure
```json
{
  "version": 1,
  "device": {
    "backlight": 80,
    "volume": 5,
    "landscapeMode": true
  },
  "wifi": {
    "enabled": true,
    "ssid": "HomeNetwork",
    "psk": "wpa2-passphrase"
  },
  "homeAssistant": {
    "enabled": true,
    "url": "ws://homeassistant.local:8123/api/websocket",
    "token": "LONG_LIVED_ACCESS_TOKEN"
  },
  "keys": [
    {
      "index": 0,
      "col": 0,
      "row": 0,
      "label": "Office Light",
      "icon": "lightbulb",
      "color": "#FFB300",
      "action": {
        "category": "ha",
        "haType": "ha_toggle",
        "entityId": "light.office_main"
      }
    }
  ]
}
```

### 3.2 Supported Home Assistant Action Types (`category: "ha"`)

| `haType` | Target Domains | Service Dispatched | Parameters | On-Keycap Live Telemetry |
| :--- | :--- | :--- | :--- | :--- |
| `ha_toggle` | `light`, `switch`, `fan`, `input_boolean`, `scene`, `script` | `homeassistant.toggle` (or `scene.turn_on` / `script.turn_on`) | `entityId` | Live `ON` / `OFF` status pill + glowing border when active |
| `ha_brightness_up` | `light` | `light.turn_on` with `brightness_step_pct: +step` | `entityId`, `step` (default `10`) | Live brightness `%` (`0–100%`) + horizontal progress bar |
| `ha_brightness_down` | `light` | `light.turn_on` with `brightness_step_pct: -step` | `entityId`, `step` (default `10`) | Live brightness `%` (`0–100%`) + horizontal progress bar |
| `ha_hvac_mode` | `climate` | `climate.set_hvac_mode` (cycles `hvacModes` or sets `targetHvacMode`) | `entityId`, `targetHvacMode` (optional), `hvacModes` | Active HVAC mode badge (`heat`, `cool`, `auto`, `off`) + room temp |
| `ha_hvac_temp_up` | `climate` | `climate.set_temperature` (`temperature = current_target + step`, clamped to `max_temp`) | `entityId`, `step` (default `0.5`) | Target temp (`→ 22.0°`) and current room temp (`21.5°`) |
| `ha_hvac_temp_down` | `climate` | `climate.set_temperature` (`temperature = current_target - step`, clamped to `min_temp`) | `entityId`, `step` (default `0.5`) | Target temp (`→ 21.0°`) and current room temp (`21.5°`) |

### 3.3 Supported Computer Macro Action Types (`category: "macro"`)

| `macroType` | Execution Target | Parameters | Description |
| :--- | :--- | :--- | :--- |
| `macro_hotkey` | STM32 `/dev/ttyS1` (`0x17`) | `keycode` (QMK 16-bit code), `modifiers` (`["LCTL", "LSFT", "LALT", "LGUI"]`), `consumerCode` | Emits hardware USB HID shortcut or media control key. |
| `macro_sequence` | STM32 `/dev/ttyS1` (`0x17`) | `steps`: `[{"type": "text\|key_tap\|delay_ms", "value": "..."}]` | Types strings and multi-key macro sequences with configurable delays. |
| `macro_mouse` | STM32 `/dev/ttyS1` (`0x18`) | `buttons` (`1`=Left, `2`=Right, `4`=Middle), `dx`, `dy`, `wheelV`, `wheelH` | Emits hardware USB HID mouse click, cursor delta, or scroll wheel report. |
| `macro_host_launcher` | Flutter Companion App (`macroTriggered` event) | `launcherType` (`"app"` \| `"script"` \| `"url"`), `target`, `args` (`string[]`) | Triggers the connected computer's Flutter companion app to launch an app, run a shell command/script, or open a URL. |

---

## 4. Dual Companion Transport & Extended JSON-RPC API

The custom firmware exposes the exact same JSON-RPC method registry over two transports simultaneously:
1. **USB Serial (`/dev/ttyGS0`)**: Uses the 24-byte Protocol V2 binary envelope (`header = 0xA1A55A5E`, `cmd = 100` for JPEG frames, `cmd = 101` for UTF-8 JSON-RPC, IEEE 802.3 CRC32).
2. **Wi-Fi WebSocket (`ws://<sk18-ip>:8180/ws`)**: Exchanges raw UTF-8 JSON-RPC request/response/event objects over WebSocket text frames.

### 4.1 Extended JSON-RPC Methods (`Host → Device`)

All responses follow the standard V2 envelope:
```json
{
  "ack_method": "<methodName>",
  "success": true,
  "result": { ... }
}
```

#### `scanWifi`
Triggers `wpa_cli -i wlan0 scan` and parses `wpa_cli -i wlan0 scan_results`.
- **Request**: `{"method": "scanWifi"}`
- **Response (`result`)**:
  ```json
  {
    "networks": [
      { "ssid": "HomeWiFi", "bssid": "aa:bb:cc:dd:ee:ff", "rssi": -46, "secure": true }
    ]
  }
  ```

#### `setWifiConfig`
Updates Wi-Fi credentials in `/mnt/SDCARD/sk18_config.json`, writes `/etc/wpa_supplicant.conf`, runs `wpa_cli -i wlan0 reconfigure`, and obtains a DHCP lease via `udhcpc -i wlan0 -n -q`.
- **Request**:
  ```json
  {
    "method": "setWifiConfig",
    "parameters": {
      "enabled": true,
      "ssid": "HomeWiFi",
      "psk": "secret-password",
      "connectNow": true
    }
  }
  ```
- **Response (`result`)**: Returns the updated network status object (same structure as `getNetworkStatus`).

#### `getNetworkStatus`
Queries current `wlan0` association, IPv4 address, WebSocket server port, and Home Assistant connection state.
- **Request**: `{"method": "getNetworkStatus"}`
- **Response (`result`)**:
  ```json
  {
    "wifiEnabled": true,
    "state": "connected",
    "ssid": "HomeWiFi",
    "ip": "192.168.1.50",
    "wsPort": 8180,
    "haConnected": true,
    "haUrl": "ws://homeassistant.local:8123/api/websocket"
  }
  ```

#### `setHaConfig`
Updates the Home Assistant WebSocket URL (`http://`, `https://`, `ws://`, or `wss://`), Long-Lived Access Token, and `enabled` flag, then reconnects `Sk18HomeAssistantClient`.
- **Request**:
  ```json
  {
    "method": "setHaConfig",
    "parameters": {
      "enabled": true,
      "url": "ws://homeassistant.local:8123/api/websocket",
      "token": "eyJ..."
    }
  }
  ```

#### `getHaStatus` & `getHaEntities`
Returns the Home Assistant connection status and cached entity states (`light.*`, `switch.*`, `climate.*`, `fan.*`, `scene.*`, `script.*`, `input_boolean.*`).
- **Request**: `{"method": "getHaStatus"}` or `{"method": "getHaEntities"}`
- **Response (`result`)**:
  ```json
  {
    "connected": true,
    "authenticated": true,
    "url": "ws://homeassistant.local:8123/api/websocket",
    "entityCount": 2,
    "entities": [
      {
        "entityId": "light.office_main",
        "domain": "light",
        "friendlyName": "Office Light",
        "state": "on",
        "attributes": {
          "brightness": 178,
          "friendly_name": "Office Light"
        }
      }
    ]
  }
  ```

#### `getLayoutConfig` & `setLayoutConfig`
Reads or writes the complete `sk18_config.json` configuration (including all 18 key slots) and immediately re-renders the `/dev/fb0` LCD screen.
- **Request (`getLayoutConfig`)**: `{"method": "getLayoutConfig"}`
- **Request (`setLayoutConfig`)**:
  ```json
  {
    "method": "setLayoutConfig",
    "parameters": {
      "config": { ... }
    }
  }
  ```

#### `triggerKeyAction`
Simulates pressing or releasing key `(col, row)` (or `index` `0..17`), executing its configured Home Assistant or macro action and updating the key's visual highlight on `/dev/fb0`.
- **Request**:
  ```json
  {
    "method": "triggerKeyAction",
    "parameters": {
      "col": 0,
      "row": 0,
      "pressed": true
    }
  }
  ```

#### `upgradeFirmware`
Atomically installs a newly uploaded binary (uploaded via `saveToFile` to e.g. `/data/KeyboardDevice.new`) into `/data/KeyboardDevice` (backing up the prior binary to `/data/DeviceUpgradeFirmware`), calls `sync`, and optionally restarts the daemon.
- **Request**:
  ```json
  {
    "method": "upgradeFirmware",
    "parameters": {
      "filePath": "/data/KeyboardDevice.new",
      "restart": true
    }
  }
  ```

### 4.2 Asynchronous Events (`Device → Host`)

- **`keyStateChanged`**:
  ```json
  {
    "method": "keyStateChanged",
    "parameters": { "index": 0, "col": 0, "row": 0, "pressed": true }
  }
  ```
- **`macroTriggered`**:
  ```json
  {
    "method": "macroTriggered",
    "parameters": {
      "index": 7,
      "col": 1,
      "row": 1,
      "label": "Open Terminal",
      "launcherType": "app",
      "target": "kitty",
      "args": []
    }
  }
  ```
- **`haStateUpdated`**:
  ```json
  {
    "method": "haStateUpdated",
    "parameters": {
      "entityId": "climate.living_room",
      "state": "cool",
      "attributes": {
        "current_temperature": 22.5,
        "temperature": 21.0,
        "hvac_modes": ["off", "heat", "cool", "auto"]
      }
    }
  }
  ```

---

## 5. Allwinner Tina Linux `IMAGEWTY` Rootfs Image Builder (`firmware/image/`)

The vendor firmware images (`MK20_V1.0.img` and `MK10_V1.0.img`) use the Allwinner **`IMAGEWTY`** (`v0x0300`, `1024`-byte main header followed by thirty-six `1024`-byte file headers) container format.

### 5.1 Key Partitions in `MK20_V1.0.img` (`720×1280` LCD Panel)
- **Entry `[5]` (`sunxi.fex`, offset `58368`, size `59392`)**: Standalone Flattened Device Tree (`0xd00dfeed`). Root node property `model` is at DTB offset `+92` (`"MK20\0"`), while `lcd_driver_name` (`"MK20\0"`) configures the `720×1280` MIPI/RGB panel.
- **Entry `[13]` (`boot_package.fex`, offset `1287168`, size `1392640`)**: Allwinner `sunxi-package` container holding `u-boot`, `monitor`, and an embedded copy of `sunxi.fex` (at image offset `2614272`, `model` at `2614364`). Uses a 32-bit additive checksum at header offset `+20` seeded with `STAMP_VALUE = 0x5F0A6C39`.
- **Entry `[32]` (`boot.fex`) & Entry `[33]` (`Vboot.fex`)**: Kernel `boot.img` partition and its 4-byte little-endian `FileAddSum` checksum.
- **Entry `[34]` (`rootfs.fex`, offset `9589760` in `MK20_V1.0.img` / `9584640` in `MK10_V1.0.img`, size `838,860,800` bytes)**: Unencrypted `ext4` root filesystem (`block_size = 4096`, `inodes_per_group = 8576`, `inode_size = 256`, extents enabled, `GDT_CSUM` CRC16) containing `/data/KeyboardDevice` (inode `11374`, 561 contiguous blocks starting at block `50304`) and `/data/appLunch.sh` (inode `11375`, block `50865`).
- **Entry `[35]` (`Vrootfs.fex`)**: 4-byte little-endian 32-bit unsigned word sum (`sum(uint32_le_words) & 0xFFFFFFFF`) of `rootfs.fex`.

### 5.2 Building a Custom Flashable Image
`firmware/image/sk18_image_tool.py` and `firmware/image/build_rootfs_image.sh` perform the complete rootfs image customization without requiring root privileges or loop mounts:
1. Parse the input `IMAGEWTY` image (`MK20_V1.0.img`).
2. Patch the root `model` property in both `sunxi.fex` and the DTB embedded inside `boot_package.fex` from `"MK20"` to `"SK18"` (preserving `lcd_driver_name = "MK20"` so the `720×1280` LCD timings remain intact) and recompute the `boot_package.fex` header checksum (`seed = 0x5F0A6C39`).
3. Inject the custom `/data/KeyboardDevice` binary, `/data/appLunch.sh` startup script, and default `/mnt/SDCARD/sk18_config.json` directly into the `ext4` `rootfs.fex` partition.
4. Recalculate the 32-bit `Vrootfs.fex` checksum (`FileAddSum`) in Entry `[35]`.
5. Output the ready-to-flash `SK18_Custom_V1.0.img` (for PhoenixSuit / LiveSuit) plus an over-the-wire updater script for live USB/Wi-Fi daemon upgrades.
