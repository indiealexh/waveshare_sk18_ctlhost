# AGENTS.md — `wavectl_host` AI Agent Guide

Keep context lean: follow these rules directly and only read specific files in `docs/` when working on that subsystem.

---

## 1. Project Overview

`wavectl_host` is a cross-platform Flutter desktop host & companion application (macOS, Linux, Windows) for the **Waveshare SK18** (18-key mechanical macro pad with an integrated `1280×720` / `720×1280` IPS LCD).

### Core Capabilities
1. **Custom Button Designer & Live LCD Renderer**:
   - Configure 18 keys (`3 rows × 6 cols` in landscape, `6 rows × 3 cols` in portrait) with custom labels, icons, colors, and live telemetry overlays.
   - Stream full-screen baseline JPEG frames over USB Serial (Protocol V2) and synchronize layout configs (`sk18_config.json`).
2. **Keyboard Macros (`category: "macro"`)**:
   - **Hotkeys & Shortcuts (`macro_hotkey`)**: QMK 16-bit keycodes + modifiers (`LCTL`, `LSFT`, `LALT`, `LGUI`) and USB HID consumer/media keys.
   - **Keystroke Sequences (`macro_sequence`)**: Multi-step `text`, `key_tap`, and `delay_ms` macro execution or V2 `keyboardInput` string injection.
   - **Mouse & Scroll (`macro_mouse`)**: Hardware USB HID mouse clicks, cursor deltas `(dx, dy)`, and scroll wheel steps `(wheelV, wheelH)`.
3. **Application & Media Commands**:
   - **Host Launcher (`macro_host_launcher`)**: Execute desktop apps (`"app"`), shell scripts/commands (`"script"`), or open URLs (`"url"`) upon receiving `keyStateChanged` / `macroTriggered` events.
   - **On-Device Audio**: Upload `.wav` sound effects (`saveToFile` + `setFileCRC`), trigger speaker playback (`playAudio` / `stopAudio`), and control amplifier volume (`0–7`) and LCD backlight (`0–100`).
4. **Home Assistant Integration (`category: "ha"`)**:
   - Connect to Home Assistant via REST / WebSocket API to control entities and render real-time sensor/device state directly on keycaps:
     - `ha_toggle` (`light`, `switch`, `fan`, `input_boolean`, `scene`, `script`) → live `ON`/`OFF` pill + active glow border.
     - `ha_brightness_up` / `ha_brightness_down` (`light`) → live `0–100%` percentage + progress bar.
     - `ha_hvac_mode` / `ha_hvac_temp_up` / `ha_hvac_temp_down` (`climate`) → active HVAC mode badge + current & target temperatures.
   - **Environment Variables (`.env`)**:
     - Read `HOME_ASSISTANT_BASE_URL` and `HOME_ASSISTANT_TOKEN` from the root `.env` file.
     - **Never** hardcode tokens or commit `.env` credentials to version control.

---

## 2. Documentation Index (`docs/`)

Read only the file needed for your current task:

- `docs/architecture.md` — Feature-first module map, registry extension recipes, and zero-behavior-change contracts.
- `docs/pocflutter-lessons-and-production-guide.md` — **Must-read** for serial I/O, rendering, GPU rotation, JPEG encoding, and Flutter testing pitfalls.
- `docs/hardware-and-geometry.md` — Dual-SoC hardware architecture and exact 18-key pixel coordinates/margins in landscape and portrait.
- `docs/protocol-v2.md` — Stock Protocol V2 binary packet framing (`0xA1A55A5E`), CRC32, JPEG streaming (`cmd = 100`), and all 10 stock JSON-RPC methods (`cmd = 101`).
- `docs/custom-firmware-and-companion.md` — Custom firmware `/mnt/SDCARD/sk18_config.json` schema, STM32 `/dev/ttyS1` opcodes, Home Assistant actions, and extended USB/WebSocket JSON-RPC API.
- `docs/protocol-v1-and-internals.md` — Reverse-engineered Protocol V1 (`AA551234 FIXEDCMDHEAD`), `.Theme` format, and Tina Linux filesystem layout.
- `docs/linux-setup.md` — USB VID:PID enumeration, Linux `udev` rules (`ModemManager` bypass), and macOS `/dev/cu.usbmodem*` setup.

---

## 3. Hardware & Pixel Geometry Rules

### Dual-Processor Architecture
The SK18 sits behind an internal USB 2.0 Hub (`05e3:0610`) with two cooperating processors connected via internal UART `/dev/ttyS1` (`115200 8N1`):
1. **Allwinner T113-S3 (`1d6b:0104` or `1234:5678`, USB CDC-ACM Serial)**: Runs Tina Linux and `/data/KeyboardDevice` (`V2.32`). Drives the LCD (`/dev/fb0`), CedarX hardware JPEG decoder (`/dev/cedar_dev`), G2D blitter (`/dev/g2d`), and ALSA speaker.
2. **STM32 Microcontroller (`4250:426f`, USB HID)**: Runs QMK/VIA (`syk_keyboards_sk18_via.bin`), scans the 18 mechanical switches, emits USB HID keyboard/mouse/consumer reports to the host PC, and forwards switch events to the T113 over `/dev/ttyS1`.

### Screen & Key Coordinates
- **Key Size**: `158 × 158 px` (`cornerRadius = 30 px`, `borderWidth = 2 px`), inter-key gutter `gapX = 60 px`, `gapY = 60 px` (pitch = `218 px`).
- **CRITICAL `+12 px` Stock Firmware Margin Bug**:
  - Along the `1280 px` axis, physical outer margins are asymmetric: **`22 px`** on one side and **`10 px`** on the other (`22 + 6×158 + 5×60 + 10 = 1280`).
  - Stock firmware `V2.32` returns unflipped `10` instead of `22` in `getInfo`. **Always auto-correct by adding `+12 px`**:
    - **Landscape (`1280 × 720`, `col ∈ 0..5`, `row ∈ 0..2`)**:
      - `x = 22 + 218 * col` (`{22, 240, 458, 676, 894, 1112}` — apply `+12` when `rects.first.x == 10`)
      - `y = 63 + 218 * row` (`{63, 281, 499}`)
    - **Portrait (`720 × 1280`, `col ∈ 0..2`, `row ∈ 0..5`)**:
      - `x = 63 + 218 * col` (`{63, 281, 499}`)
      - `y = 22 + 218 * row` (`{22, 240, 458, 676, 894, 1112}` — apply `+12` when `rects.first.y == 10`)
  - Support a persisted per-device user calibration offset (`offsetX`, `offsetY` in `-64..+64 px`).

### Physical-to-Logical Key Event Remapping
- The SK18 panel scanout is natively portrait (`720 × 1280`, `3 cols × 6 rows`). Even when displaying 90°-rotated landscape frames (`1280 × 720`, `6 cols × 3 rows`), the firmware emits `keyStateChanged` using native portrait coordinates (`physCol ∈ 0..2`, `physRow ∈ 0..5`).
- When operating in landscape mode on a portrait framebuffer, remap **physical** device events via:
  ```dart
  final int logicalCol = physRow; // 0..5
  final int logicalRow = (deviceInfo.rectCols - 1) - physCol; // 2 - physCol (0..2)
  ```
- **Never** apply this remapping to simulated button clicks from the desktop landscape UI preview (`fromPhysicalDevice: false`).

---

## 4. Protocol V2 & Transport Rules

### Handshake (V1 Abort → V2 `getInfo`)
1. On connect, immediately send the 37-byte ASCII abort sequence:
   `AA551234 Abort file transfer 123455AA`
   *(Do **not** send the legacy 1 MB `'0'` flood.)*
2. Discard any prefix bytes before the V2 magic header (including the ASCII response `AA551234 Abort file transfer ok`).
3. Send `{"method": "getInfo"}` (`cmd = 101`) to switch `KeyboardDevice` into Protocol V2 mode.

### V2 Binary Envelope (24 Bytes + Payload, Little-Endian)
| Offset | Size | Type | Field | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | `4` | `uint32` | `header` | Always transmit `A1 A5 5A 5E`; accept both `A1 A5 5A 5E` and `5E 5A A5 A1` on receive |
| `0x04` | `4` | `int32` | `id` | Monotonically increasing request ID (`-1` on device framing error) |
| `0x08` | `4` | `uint32` | `cmd` | `100` (`CMD_VALUE_SHOW_JPG`) or `101` (`CMD_VALUE_JSON`) |
| `0x0C` | `4` | `uint32` | `size` | Payload length `N` in bytes (`0 <= N <= 16 MB`) |
| `0x10` | `4` | `uint32` | `size_crc` | IEEE 802.3 CRC32 of the 4-byte `size` field (`0x2144DF1C` when `size == 0`) |
| `0x14` | `N` | `bytes` | `data` | Baseline JPEG bytes (`cmd = 100`) or UTF-8 JSON (`cmd = 101`) |
| `0x14+N` | `4` | `uint32` | `data_crc` | IEEE 802.3 CRC32 of `data` (`0x00000000` when `size == 0`) |

### Two-Stage CRC Stream Resynchronization
1. Verify `size_crc` and `size <= 16 MB` **before** waiting for `size` payload bytes. If invalid, drop only `4` bytes (`removeRange(0, 4)`) and rescan for magic bytes.
2. If `data_crc` fails after `size` bytes arrive, drop only the `24`-byte header (`removeRange(0, 24)`) so valid headers inside the payload buffer are not lost.

### JSON-RPC Methods (`cmd = 101`)
- **Stock V2 Methods**:
  - `getInfo`, `setBacklight` (`level: 0..100`), `setVolume` (`level: 0..7`), `keyboardInput` (`inputString`), `getFilesBySuffix` (**must** use exact typo key `"suffixs": ["wav"]`), `saveToFile` (`filePath`, `seek`, `data` in 64 KB raw / Base64 chunks), `setFileCRC` (`filePath`, `crc`), `deleteFiles` (`filePaths`), `playAudio` (`filePath`), `stopAudio`.
- **Custom Firmware / Companion Methods** (over USB Serial V2 and `ws://<sk18-ip>:8180/ws`):
  - `scanWifi`, `setWifiConfig`, `getNetworkStatus`, `setHaConfig`, `getHaStatus`, `getHaEntities`, `getLayoutConfig`, `setLayoutConfig`, `triggerKeyAction`, `upgradeFirmware`.
- **Async Device Events (`Device → Host`)**:
  - `keyStateChanged` (`col`, `row`, `pressed`), `macroTriggered` (`index`, `col`, `row`, `launcherType`, `target`, `args`), `haStateUpdated` (`entityId`, `state`, `attributes`).

---

## 5. Critical Engineering Guardrails (Lessons from `pocflutter`)

### Serial Port I/O (macOS `/dev/cu.usbmodem*` & Linux `/dev/ttyACM*`)
1. **Never use `FileMode.append`**: Dart's `File.open(mode: FileMode.append)` calls `lseek(SEEK_END)`, throwing `ESPIPE (errno = 29)` on character devices. Use `FileMode.write` or POSIX FFI `open(O_RDWR | O_NOCTTY | O_NONBLOCK)`.
2. **Open Descriptor BEFORE Configuring `termios` / `stty`**: On macOS (`AppleUSBCDCACMData`), closing the last fd resets baud/mode back to 9600 canonical. Open and hold the port handle first, then apply `115200 raw -echo clocal cread cs8 -cstopb -parenb min 0 time 0` (or `tcsetattr` via `dart:ffi`).
3. **Never use `File.openRead()` on Serial Nodes**: It opens a second fd that races handshakes and leaves uninterruptible blocked read threads in the Dart VM on disconnect. Use a single non-blocking handle (`VMIN=0, VTIME=0`) or a dedicated **Serial Worker `Isolate`** using POSIX `libc` FFI (`open`, `tcsetattr`, `tcflush`, `ioctl` for DTR/RTS).
4. **Device Discovery & Permissions**:
   - **macOS**: Always normalize `/dev/tty.usbmodem*` → `/dev/cu.usbmodem*` (opening `/dev/tty.*` blocks on DCD). Use `ioreg -p IOUSB -l -w 0` matching both hex (`0x1d6b`/`0x0104`) and decimal (`7531`/`260`) VID:PIDs. Ensure `com.apple.security.app-sandbox` is `false` (or `com.apple.security.device.serial` is enabled) in `macos/Runner/*.entitlements`.
   - **Linux**: Inspect `/sys/class/tty/ttyACM*/device` (`idVendor`/`idProduct`). Remind users to install the `udev` rule (`ENV{ID_MM_DEVICE_IGNORE}="1"`) so `ModemManager` does not inject AT commands.

### Rendering, GPU Rotation & JPEG Streaming
1. **Dual-Path Canvas**: Share one `paintLogicalCanvas(Canvas, Size)` between `CustomPainter` (60 FPS desktop preview without JPEG overhead) and `ui.PictureRecorder` (offscreen hardware frame generation).
2. **Pre-Rotate on the GPU, Not CPU**: When rendering a `1280×720` landscape canvas for a `720×1280` portrait framebuffer, rotate the `dart:ui` `Canvas` before rasterizing:
   ```dart
   canvas.translate(720, 0);
   canvas.rotate(math.pi / 2);
   paintLogicalCanvas(canvas, const Size(1280, 720));
   ```
   Never call CPU `copyRotate` on `1280×720` RGBA buffers.
3. **Background JPEG Encoding & Dirty-Flag Streaming**:
   - Offload JPEG encoding (`quality: 85`, baseline JPEG, exact `1280×720` or `720×1280` multiples of 16 for CedarX) from the UI isolate to a background **Encoder `Isolate`** (or native FFI).
   - Only encode and send frames when visual state is dirty (key press/release, HA state update, page switch, clock tick).
4. **ACK Backpressure & Upload Throttling**:
   - Gate outbound `CMD_VALUE_SHOW_JPG` frames on receiving the device's frame ACK (`_isEncodingFrame` + `_waitingForFrameAck`) with a `500 ms` watchdog timeout.
   - Pause/throttle JPEG frame streaming while a chunked `saveToFile` upload is active.

---

## 6. Development & Testing Conventions

- **Commands**:
  - Static analysis: `flutter analyze`
  - Unit & widget tests: `flutter test`
- **Widget Test Guardrails**:
  - Set a desktop viewport (`tester.view.physicalSize = const Size(1440, 960); tester.view.devicePixelRatio = 1.0;`) and wrap `Row` children in `Expanded`/`Flexible` so `flutter test`'s wide `Ahem` font does not overflow.
  - Wrap `Picture.toImage()` and real file I/O inside `await tester.runAsync(() async { ... })` to prevent `FakeAsync` deadlocks.
  - Cancel all `Timer` instances (serial poll, ACK watchdog, frame stream, clock, HA reconnect) in `dispose()` / `disconnect()`.
