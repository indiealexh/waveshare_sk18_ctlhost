# wavectl_host

Cross-platform Flutter desktop host and studio companion application (**macOS**, **Linux**, **Windows**) for the **Waveshare SK18** — an 18-key mechanical macro pad with an integrated `1280×720` / `720×1280` IPS LCD.

AI Disclaimer: This project was created by using AI (LLM and Agents) to decode and breakdown the waveshare provided application and very limited documentation.
This was then used to inform this proof of concept application.

---

## Features

### 1. Interactive 18-Key Studio & Live LCD Renderer
- **Visual Key Designer**: Configure all 18 mechanical keys (`6 cols × 3 rows` in landscape `1280×720` or `3 cols × 6 rows` in portrait `720×1280`) with custom labels, subtitles, icons, accent colors, and live telemetry overlays.
- **Dual-Path 60 FPS Preview & Hardware Streaming**: Shares a single logical canvas between the desktop studio preview (`CustomPainter`) and offscreen GPU-rotated frame rasterization (`ui.PictureRecorder`), encoding baseline JPEG frames in a background `Isolate` and streaming them over USB Serial (Protocol V2 `cmd = 100`) with ACK backpressure and dirty-frame detection.
- **Pixel-Accurate Geometry & Calibration**: Automatically corrects the stock `V2.32` firmware's `+12 px` outer margin offset (`x = 22 + 218 * col`, `y = 63 + 218 * row` in landscape) and supports persisted per-device `offsetX` / `offsetY` (`-64..+64 px`) calibration.
- **Offline Simulator Mode**: Test key layouts, page switching, macro triggers, and Home Assistant states directly in the desktop UI without physical hardware attached.
- **Profile Persistence & Sync**: Import/export multi-page profiles and synchronize `sk18_config.json` directly with the device.

### 2. Keyboard & Mouse Macros (`category: "macro"`)
- **Hotkeys & Shortcuts (`macro_hotkey`)**: QMK 16-bit keycodes with modifier masks (`LCTL`, `LSFT`, `LALT`, `LGUI`) and USB HID consumer/media controls.
- **Keystroke Sequences (`macro_sequence`)**: Multi-step `text`, `key_tap`, and `delay_ms` macro sequences or stock Protocol V2 `keyboardInput` string injection.
- **Mouse & Scroll (`macro_mouse`)**: Hardware USB HID mouse clicks, cursor movement deltas `(dx, dy)`, and vertical/horizontal scroll wheel steps `(wheelV, wheelH)`.

### 3. Host Application Launcher & On-Device Audio
- **Host Launcher (`macro_host_launcher`)**: Launch desktop applications (`"app"`), execute shell scripts/commands (`"script"`), or open URLs (`"url"`) on the host PC in response to physical `keyStateChanged` / `macroTriggered` events.
- **Device Audio & Hardware Controls**: Upload `.wav` sound effects in 64 KB chunks (`saveToFile` + `setFileCRC`), manage on-device audio files (`getFilesBySuffix`, `deleteFiles`), trigger speaker playback (`playAudio` / `stopAudio`), and adjust amplifier volume (`0–7`) and LCD backlight brightness (`0–100`).

### 4. Home Assistant Integration (`category: "ha"`)
- Connect to Home Assistant via REST / WebSocket API to control smart-home entities and render live telemetry directly on SK18 keycaps:
  - **`ha_toggle`** (`light`, `switch`, `fan`, `input_boolean`, `scene`, `script`) — live `ON`/`OFF` status pill and active glow border.
  - **`ha_brightness_up` / `ha_brightness_down`** (`light`) — live `0–100%` brightness badge and progress bar.
  - **`ha_hvac_mode` / `ha_hvac_temp_up` / `ha_hvac_temp_down`** (`climate`) — active HVAC mode badge with current and target temperatures.

---

## Hardware Architecture Overview

The Waveshare SK18 sits behind an internal USB 2.0 Hub (`05e3:0610`) with two processors connected via an internal UART (`/dev/ttyS1` at `115200 8N1`):

| Processor | USB VID:PID | Interface | Role |
| :--- | :--- | :--- | :--- |
| **Allwinner T113-S3** | `1d6b:0104` / `1234:5678` | USB CDC-ACM Serial (`/dev/cu.usbmodem*` on macOS, `/dev/ttyACM*` on Linux) | Runs Tina Linux & `/data/KeyboardDevice` (`V2.32`). Drives the `720×1280` LCD (`/dev/fb0`), CedarX hardware JPEG decoder, G2D blitter, and ALSA speaker over Protocol V2 (`0xA1A55A5E`). |
| **STM32 MCU** | `4250:426f` | USB HID (`usbhid` / `IOUSBHostHIDDevice`) | Runs QMK/VIA firmware, scans the 18 mechanical switches, emits USB HID keyboard/mouse/consumer reports to the host, and forwards matrix events to the T113 over `/dev/ttyS1`. |

---

## Getting Started

### Prerequisites
- **Flutter SDK** (Dart SDK `^3.13.7`) with desktop support enabled for macOS, Linux, or Windows.

### Platform USB Serial Setup

#### macOS (`/dev/cu.usbmodem*`)
- `wavectl_host` automatically discovers the SK18 via `ioreg` and normalizes `/dev/tty.usbmodem*` nodes to call-out devices (`/dev/cu.usbmodem*`) with non-blocking POSIX I/O and `115200 raw` termios configuration.

#### Linux (`/dev/ttyACM*`)
On Linux distributions running `ModemManager`, configure a `udev` rule so `ModemManager` does not probe `/dev/ttyACM*` with AT commands and so your user has non-root serial permissions:

```bash
sudo tee /etc/udev/rules.d/99-waveshare-sk18.rules >/dev/null <<'EOF'
SUBSYSTEM=="tty", ATTRS{idVendor}=="1d6b", ATTRS{idProduct}=="0104", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1", MODE="0666", TAG+="uaccess", SYMLINK+="sk18"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1234", ATTRS{idProduct}=="5678", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1", MODE="0666", TAG+="uaccess", SYMLINK+="sk18"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Home Assistant Configuration (`.env`)
To pre-configure Home Assistant credentials, create a `.env` file in the project root (ignored by Git):

```dotenv
HOME_ASSISTANT_BASE_URL=http://homeassistant.local:8123
HOME_ASSISTANT_TOKEN=your_long_lived_access_token
```

You can also configure or override the Home Assistant URL and token at runtime from the Studio sidebar.

### Build & Run

```bash
# Install dependencies
flutter pub get

# Run on desktop (macOS / Linux / Windows)
flutter run -d macos
# flutter run -d linux
# flutter run -d windows
```

### Static Analysis & Tests

```bash
# Run Dart static analyzer
flutter analyze

# Run unit & widget test suites
flutter test
```

---

## Project Structure

```text
lib/
├── main.dart                                  # Application entry point & dependency wiring
├── data/
│   ├── repositories/                          # Device, Home Assistant & Profile repositories
│   └── services/                              # Serial transport, Protocol V2 codec, RPC client,
│                                              # Isolate JPEG frame streamer, HA client, host launcher
├── domain/
│   ├── models/                                # Key configs, actions, SK18 geometry, device info, HA state
│   └── use_cases/                             # ActionExecutorUseCase (macros, HA actions, host launcher)
└── ui/
    ├── core/
    │   ├── rendering/sk18_canvas_painter.dart # Shared 1280×720 / 720×1280 canvas renderer
    │   └── theme/app_theme.dart               # Dark studio theme
    └── features/studio/                       # Studio ViewModel, sidebar, center canvas & right inspector
```

---

## Documentation (`docs/`)

Detailed hardware, protocol, and engineering documentation is available in the [`docs/`](docs/) directory:

- [`docs/pocflutter-lessons-and-production-guide.md`](docs/pocflutter-lessons-and-production-guide.md) — Serial I/O guardrails, dual-path GPU canvas rendering, background Isolate JPEG encoding, and Flutter test guidelines.
- [`docs/hardware-and-geometry.md`](docs/hardware-and-geometry.md) — Dual-SoC hardware architecture, exact 18-key pixel coordinates, `+12 px` margin auto-correction, and physical-to-logical key remapping.
- [`docs/protocol-v2.md`](docs/protocol-v2.md) — Stock Protocol V2 binary framing (`0xA1A55A5E`), two-stage CRC32 resynchronization, JPEG streaming (`cmd = 100`), and JSON-RPC (`cmd = 101`).
- [`docs/custom-firmware-and-companion.md`](docs/custom-firmware-and-companion.md) — Custom firmware `/mnt/SDCARD/sk18_config.json` schema, `/dev/ttyS1` STM32 opcodes, Home Assistant integration, and extended JSON-RPC methods.
- [`docs/protocol-v1-and-internals.md`](docs/protocol-v1-and-internals.md) — Reverse-engineered Protocol V1 (`AA551234 FIXEDCMDHEAD`), `.Theme` archive format, and Tina Linux internals.
- [`docs/linux-setup.md`](docs/linux-setup.md) — USB VID:PID enumeration, Linux `udev` rules, and macOS `/dev/cu.usbmodem*` setup.

