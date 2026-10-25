# Linux & macOS Setup, USB Permissions & Build Guide for Waveshare SK18

This guide explains how the Waveshare SK18 enumerates on **Linux** and **macOS**, how to configure Linux `udev` rules so `/dev/ttyACM*` works reliably without root privileges or `ModemManager` interference, how macOS enumerates `/dev/cu.usbmodem*`, and how to build and run the C++/Qt Proof-of-Concept (`poc/`) on both operating systems.

---

## 1. How the SK18 Enumerates Over USB (Linux & macOS)

When plugged into a Linux PC or Mac via its USB Type-C port, the SK18 exposes an internal **USB 2.0 Hub (`05e3:0610`)** with two downstream USB devices:

1. **Allwinner T113 USB Gadget Serial (`CDC-ACM`, USB 2.0 High-Speed 480 Mbps)**:
   - **USB VID:PID**: `1d6b:0104` (*Allwinner Technology Inc. — Serial* / *Linux Foundation Multifunction Composite Gadget*) or `1234:5678`.
   - **Linux Kernel Driver & Node**: `cdc_acm` → `/dev/ttyACM0` (or `/dev/sk18` with our `udev` rule).
   - **macOS Driver & Node**: `AppleUSBCDCACMData` → `/dev/cu.usbmodem*` (e.g., `/dev/cu.usbmodem1101`, call-out device) and `/dev/tty.usbmodem*` (dial-in device).
     - **Important macOS Note**: Always open the call-out node `/dev/cu.usbmodem*` (not `/dev/tty.usbmodem*`, which blocks in `open()` waiting for carrier detect) and assert `DTR` + `RTS` (`setDataTerminalReady(true)` / `setRequestToSend(true)`). `Sk18Client` handles both automatically on macOS.
   - **Role**: Carries Protocol V2 (`0xA1A55A5E` JPEG streaming, `keyStateChanged` events, audio/backlight/volume/file JSON-RPC commands) and Protocol V1.
2. **STM32 QMK/VIA USB HID Interface (USB Full-Speed 12 Mbps)**:
   - **USB VID:PID**: `4250:426f` (*SYK — syk_keyboards*)
   - **Kernel Driver**: `usbhid` (Linux) / `IOUSBHostHIDDevice` (macOS)
   - **Role**: Standard USB HID keyboard/mouse plus QMK/VIA raw HID configuration.

You can verify enumeration on **Linux** using `lsusb`:
```bash
lsusb | grep -E "1d6b:0104|4250:426f|05e3:0610"
ls -l /dev/ttyACM*
```

Or on **macOS** using `ioreg`:
```bash
ls -l /dev/cu.usbmodem*
ioreg -r -c IOSerialBSDClient -l -w 0 | grep -E "IOTTYDevice|IOCalloutDevice"
```

---

## 2. Installing the Linux `udev` Rule (Crucial for `ModemManager` & Permissions)

On many Linux desktop distributions (Ubuntu, Fedora, Debian, Arch with NetworkManager), the background `ModemManager` daemon automatically opens any newly connected `/dev/ttyACM*` port and sends Hayes `AT` modem commands for 10–15 seconds. This causes two problems:
- `EBUSY` / port lock errors when your application tries to open `/dev/ttyACM0` right after plugging in the SK18.
- Unexpected garbage bytes in the SK18's serial receive buffer.

Additionally, `/dev/ttyACM0` is owned by root and the `dialout` (Debian/Ubuntu/Fedora) or `uucp` (Arch) group by default.

### 2.1 Install `poc/udev/99-waveshare-sk18.rules`
The repository includes a ready-to-use `udev` rule at `poc/udev/99-waveshare-sk18.rules` that:
1. Tells `ModemManager` to ignore the SK18 (`ENV{ID_MM_DEVICE_IGNORE}="1"`, `ENV{ID_MM_PORT_IGNORE}="1"`).
2. Grants user permissions via `TAG+="uaccess"` and `MODE="0666"`.
3. Creates a predictable `/dev/sk18` symlink pointing to the correct `/dev/ttyACM*` node.

Run the following commands to install and activate it:

```bash
sudo cp poc/udev/99-waveshare-sk18.rules /etc/udev/rules.d/99-waveshare-sk18.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 2.2 (Optional) Add Your User to `dialout` / `uucp`
```bash
# Ubuntu / Debian / Fedora:
sudo usermod -aG dialout "$USER"

# Arch Linux:
sudo usermod -aG uucp "$USER"
```

---

## 3. Installing Qt Build Dependencies on Linux

The Proof-of-Concept (`poc/`) supports **both Qt5 (`>= 5.12`) and Qt6 (`>= 6.2`)** and builds with either **CMake** or **qmake**.

### Ubuntu / Debian
```bash
# Using Qt6 (recommended on Ubuntu 22.04+ / Debian 12+):
sudo apt update
sudo apt install build-essential cmake qt6-base-dev libqt6serialport6-dev

# Or using Qt5:
sudo apt install build-essential cmake qtbase5-dev libqt5serialport5-dev qt5-qmake
```

### Fedora
```bash
# Using Qt6:
sudo dnf install gcc-c++ cmake qt6-qtbase-devel qt6-qtserialport-devel

# Or using Qt5:
sudo dnf install gcc-c++ cmake qt5-qtbase-devel qt5-qtserialport-devel
```

### Arch Linux
```bash
# Using Qt6:
sudo pacman -S base-devel cmake qt6-base qt6-serialport

# Or using Qt5:
sudo pacman -S base-devel cmake qt5-base qt5-serialport
```

### macOS (Apple Silicon & Intel via Homebrew)
You only need the lightweight `qtbase` and `qtserialport` formulas (not the full multi-gigabyte `qt` bundle):
```bash
brew install cmake qtbase qtserialport
```
> `poc/CMakeLists.txt` automatically detects Homebrew's Qt paths (`/opt/homebrew` and `/usr/local`), so no manual `CMAKE_PREFIX_PATH` flags are required.

---

## 4. Building & Running the Proof-of-Concept (`poc/`)

### Option A: Build with CMake (Linux & macOS)
```bash
cmake -S poc -B poc/build -DCMAKE_BUILD_TYPE=Release
cmake --build poc/build -j
```

### Option B: Build with qmake (Linux & macOS)
```bash
mkdir -p poc/build
cd poc/build
qmake ../sk18_poc.pro
make -j
```

### Running the Application

1. **Automated Self-Test Suite** (verifies CRC32, V2 packet framing, macOS/Linux port normalization, fragmented/corrupted stream recovery, SK18 `1280×720` & `720×1280` geometry, and JPEG canvas rendering):
   ```bash
   ./poc/build/sk18_poc --self-test
   ```
2. **Live Hardware CLI Probe** (auto-detects the connected SK18 on `/dev/ttyACM*` or `/dev/cu.usbmodem*`, sends the V1 abort handshake + `getInfo`, prints the device's layout JSON, and streams an initial `720×1280` / `1280×720` 18-key frame to the physical LCD):
   ```bash
   ./poc/build/sk18_poc --probe
   ```
3. **Interactive Desktop GUI** (works on **Linux Wayland/X11** and **macOS**, with live hardware connection or **Offline Simulator Mode**):
   ```bash
   ./poc/build/sk18_poc
   ```
