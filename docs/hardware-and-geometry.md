# Waveshare SK18 Hardware Architecture & Display/Key Geometry

This document details the internal dual-microcontroller architecture of the **Waveshare SK18**, how it enumerates and communicates over USB, and the exact pixel geometry for all 18 mechanical key regions and surrounding screen margins/gutters.

All constants and formulas in this document were verified directly against:
- The on-device ARM Linux daemon `/data/KeyboardDevice` (`V2.32`, extracted from `ScreenKeyMacOS_v1_1.dmg` at `/defaultData/static/deviceResources/data/KeyboardDevice`)
- The host application binary `ScreenKeyMacOS` (`0x100503190`–`0x100503210`)
- The vendor firmware image `MK10_V1.0.img`

---

## 1. Dual-System Hardware Architecture

The SK18 contains **two separate processors** inside the enclosure that cooperate over an internal UART bridge and a built-in USB hub/composite connection:

### 1.1 Allwinner T113-S3 (`sun8iw20p1`) — Display, Audio & Serial Daemon SoC
- **Architecture**: Dual-core 32-bit ARM Cortex-A7 (`armv7l`, `ELF32-littlearm`)
- **Memory**: 128 MB integrated DDR3 RAM
- **Operating System**: Allwinner Tina Linux (`Linux sun8iw20p1`)
- **Primary Application**: `/data/KeyboardDevice` (`V2.32`, Qt 5 embedded application running on Linux framebuffer/G2D)
- **Hardware Acceleration**:
  - **JPEG / H.264 Decoding**: Uses Allwinner CedarX hardware video engine (`libvdecoder.so`, `libVE.so`, `libMemAdapter.so`, `/dev/cedar_dev`) via `JpegDecoderSingleton::decode`.
  - **2D Blitting & Rotation**: Uses Allwinner `/dev/g2d` (`CreateVideoOutport`) to scale, rotate, and blit decoded frames directly to the LCD panel without CPU pixel-copy bottlenecks.
- **Audio Output**: Uses ALSA (`tinyplay -D 0 -d 0 <wav>`) for speaker playback and `volumeAdjuster()` (`0–7`) for hardware amplifier gain.
- **Backlight Control**: Uses `backlightAdjuster()` (`0–100`) to control LCD PWM brightness.
- **Device Identification**: Reads `/sys/firmware/devicetree/base/model` (`get_screen_model()` at `0xc6e1c`), returning `"SK18"` (or `"MK10"`, `"MK20"` on sibling models).
- **USB Gadget Serial Interface**: Exposes `/dev/ttyGS0` via Linux USB Gadget (`g_serial` / `usb_f_acm`, USB 2.0 High-Speed 480 Mbps, USB VID:PID `1d6b:0104` `"Allwinner Technology Inc."` `"Serial"` or `1234:5678`), which appears on Linux as `/dev/ttyACM0` and on macOS as `/dev/cu.usbmodem*`.

### 1.2 STM32 Microcontroller — QMK / VIA Mechanical Key Matrix & USB HID
- **Firmware**: `syk_keyboards_sk18_via.bin` (QMK with VIA protocol support)
- **Key Matrix Scanning**: Scans the physical 18 mechanical switches (`3×6` / `6×3`) with hardware debouncing.
- **External USB Interface**: Exposes a standard **USB HID Keyboard / Mouse / Consumer Control** interface (`USB VID:PID = 4250:426f`, Vendor `"SYK"`, Product `"syk_keyboards"`, USB Full-Speed 12 Mbps) directly to the host PC, plus a VIA raw HID interface. Both the Allwinner T113 (`1d6b:0104`) and the STM32 (`4250:426f`) sit behind an internal **Genesys Logic USB 2.0 Hub (`05e3:0610`)** inside the SK18 enclosure.
- **Internal UART Bridge (`/dev/ttyS1`)**: Connected to the Allwinner T113's `/dev/ttyS1` UART (`STM32CommunicationObject` in `KeyboardDevice`).
  - When a physical key is pressed or released, the STM32 sends a key-state frame over `/dev/ttyS1` to `KeyboardDevice`.
  - In **Protocol V2 mode**, `KeyboardDevice` forwards that key press/release over `/dev/ttyGS0` (`/dev/ttyACM0` on Linux, `/dev/cu.usbmodem*` on macOS) to the host PC as a `keyStateChanged` JSON event.
  - Conversely, when the host PC sends a `keyboardInput` JSON-RPC command over USB serial, `KeyboardDevice` calls `STM32CommunicationObject::request_upload_string`, which commands the STM32 over `/dev/ttyS1` to type the string over its real USB HID keyboard endpoint.

---

## 2. Screen & Button Pixel Geometry

The SK18 uses a single continuous **1280×720** IPS LCD panel positioned beneath an acrylic/metal top plate with 18 square keycap cutouts. Because the bezel and grid ribs between the 18 switches cover part of the panel—or have transparent bevels depending on viewing angle—knowing the exact pixel coordinates of both the **18 key regions (`isKey = true`)** and the **surrounding margins/gutters (`isKey = false`)** is critical.

### 2.1 Internal `foregroundParam` Geometry Struct

Inside `KeyboardDevice`, `_GLOBAL__sub_I_main.cpp` (`0x356bc`–`0x35860`) initializes an array of 6 `foregroundParam` structures (`foregroundParamArray` at `0x250470`, 68 bytes per entry), one for each model (`MK10`, `MK20`, `SK18`) in both landscape (`rotate = false`) and portrait (`rotate = true`) orientations.

From DWARF debug info (`dwarfdump --name=foregroundParam`) and disassembly of `calculateRectangles(foregroundParam const&)` (`0x873d0`), the struct layout is:

```cpp
struct foregroundParam {
    QString model;        // +0x00: "SK18"
    bool    rotate;       // +0x04: false (1280x720 landscape) or true (720x1280 portrait)
    int     screenWidth;  // +0x08: 1280 (landscape) or 720 (portrait)
    int     screenHeight; // +0x0c: 720  (landscape) or 1280 (portrait)
    int     rectRows;     // +0x10: 3    (landscape) or 6 (portrait)
    int     rectCols;     // +0x14: 6    (landscape) or 3 (portrait)
    int     keyWidth;     // +0x18: 158
    int     keyHeight;    // +0x1c: 158
    int     startX;       // +0x20: 10   (landscape) or 63 (portrait)
    int     gapX;         // +0x24: 60
    int     startY;       // +0x28: 63   (landscape) or 10 (portrait)
    int     gapY;         // +0x2c: 60
    int     borderWidth;  // +0x30: 2
    int     cornerRadius; // +0x34: 30
    int     extraFlag1;   // +0x38: 0
    int     extraParam1;  // +0x3c: 20
    int     extraParam2;  // +0x40: 95
};
```

### 2.2 Comparison Across Device Models in Firmware

| Model | `rotate` | `screenWidth × screenHeight` | Grid (`rectRows × rectCols`) | Key Size (`W × H`) | `startX` | `gapX` | `startY` | `gapY` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **SK18 (Landscape)** | `false` (`0`) | `1280 × 720` | `3 rows × 6 cols` (18 keys) | `158 × 158` | `10` | `60` | `63` | `60` |
| **SK18 (Portrait)** | `true` (`1`) | `720 × 1280` | `6 rows × 3 cols` (18 keys) | `158 × 158` | `63` | `60` | `10` | `60` |
| MK10 (Landscape) | `false` (`0`) | `1024 × 600` | `2 rows × 5 cols` (10 keys) | `140 × 140` | `40` | `60` | `220` | `60` |
| MK10 (Portrait) | `true` (`1`) | `600 × 1024` | `5 rows × 2 cols` (10 keys) | `140 × 140` | `220` | `60` | `40` | `60` |
| MK20 (Landscape) | `false` (`0`) | `1280 × 720` | `4 rows × 5 cols` (20 keys) | `138 × 138` | `322` | `60` | `6` | `52` |
| MK20 (Portrait) | `true` (`1`) | `720 × 1280` | `5 rows × 4 cols` (20 keys) | `138 × 138` | `6` | `52` | `322` | `60` |

> **Important Note on SK18 vs MK10/MK20**: Unlike the MK10 (which has a dedicated `220px` top status touchscreen area where `isKey = false`) and the MK20 (which has a `322px` side status panel where `isKey = false`), the **SK18's 18 keys span the entire panel** with `63px` top/bottom margins, `22px`/`10px` side margins, and `60px` gutters between keys. Consequently, `calculateRectangles` only emits the 18 key rectangles (`isKey = true`) in `getInfo`'s `rects` array for the SK18. However, the full `1280×720` (or `720×1280`) JPEG image is blitted to the LCD, so any graphics drawn in the margins or `60px` gutters are rendered directly onto the physical LCD pixels around and between the keys.

> **Critical Hardware Alignment Note (`22px` Left Margin vs `10px` Right Margin — `+12px` Offset)**:
> Across the `1280 px` axis, the 6 keys (`6 × 158 = 948 px`) and 5 inter-key gutters (`5 × 60 = 300 px`) occupy `1248 px`, leaving `32 px` of outer margin split asymmetrically into **`22 px`** on one side and **`10 px`** on the other (`22 + 1248 + 10 = 1280`).
> - In `KeyboardDevice`'s static `foregroundParamArray` (returned by `getInfo`), the firmware developer wrote `startX = 10` (`startY = 10` in portrait) *before* applying the SK18's `"canvas_flip": true` transformation (`rotateRect` at `0xe44cc`: `1280 - x - width`).
> - When `1280 - x - width` is applied to `x ∈ {10, 228, 446, 664, 882, 1100}` (`width = 158`), the physical keycap windows on the panel actually start at **`22 px` (`x ∈ {22, 240, 458, 676, 894, 1112}`)** with a **`22 px` left margin** (`0..21`) and **`10 px` right margin** (`1270..1279`).
> - If you render using the raw `startX = 10` values from `getInfo` without adding `+12 px` (`22 - 10`), every tile will appear **12 pixels off-screen to the left** under its keycap bezel with **12 pixels of empty space on the right**.

---

## 3. Landscape Orientation (`1280 × 720`, 3 Rows × 6 Columns)

In landscape orientation (`1280 × 720`), the 18 keys are arranged in **3 rows (`row = 0..2`)** by **6 columns (`col = 0..5`)**.

### 3.1 Physical Key Coordinate Formula (Landscape)
For any key at `(col, row)` where `col ∈ [0, 5]` and `row ∈ [0, 2]`:

$$\begin{aligned}
x &= 22 + \text{col} \times (158 + 60) = 22 + 218 \times \text{col} \quad (\text{raw } \texttt{getInfo} \text{ reports } 10 + 218 \times \text{col}) \\
y &= 63 + \text{row} \times (158 + 60) = 63 + 218 \times \text{row} \\
\text{width} &= 158 \\
\text{height} &= 158
\end{aligned}$$

### 3.2 Complete 18-Key Physical Coordinate Table (`1280 × 720`)

| Key # | `(col, row)` | Physical Top-Left `(x, y)` | Bottom-Right `(x2, y2)` (inclusive) | Size (`w × h`) | Center `(cx, cy)` | Raw `getInfo` `(x, y)` |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **K1** | `(0, 0)` | `(22, 63)` | `(179, 220)` | `158 × 158` | `(101, 142)` | `(10, 63)` |
| **K2** | `(1, 0)` | `(240, 63)` | `(397, 220)` | `158 × 158` | `(319, 142)` | `(228, 63)` |
| **K3** | `(2, 0)` | `(458, 63)` | `(615, 220)` | `158 × 158` | `(537, 142)` | `(446, 63)` |
| **K4** | `(3, 0)` | `(676, 63)` | `(833, 220)` | `158 × 158` | `(755, 142)` | `(664, 63)` |
| **K5** | `(4, 0)` | `(894, 63)` | `(1051, 220)` | `158 × 158` | `(973, 142)` | `(882, 63)` |
| **K6** | `(5, 0)` | `(1112, 63)` | `(1269, 220)` | `158 × 158` | `(1191, 142)` | `(1100, 63)` |
| **K7** | `(0, 1)` | `(22, 281)` | `(179, 438)` | `158 × 158` | `(101, 360)` | `(10, 281)` |
| **K8** | `(1, 1)` | `(240, 281)` | `(397, 438)` | `158 × 158` | `(319, 360)` | `(228, 281)` |
| **K9** | `(2, 1)` | `(458, 281)` | `(615, 438)` | `158 × 158` | `(537, 360)` | `(446, 281)` |
| **K10** | `(3, 1)` | `(676, 281)` | `(833, 438)` | `158 × 158` | `(755, 360)` | `(664, 281)` |
| **K11** | `(4, 1)` | `(894, 281)` | `(1051, 438)` | `158 × 158` | `(973, 360)` | `(882, 281)` |
| **K12** | `(5, 1)` | `(1112, 281)` | `(1269, 438)` | `158 × 158` | `(1191, 360)` | `(1100, 281)` |
| **K13** | `(0, 2)` | `(22, 499)` | `(179, 656)` | `158 × 158` | `(101, 578)` | `(10, 499)` |
| **K14** | `(1, 2)` | `(240, 499)` | `(397, 656)` | `158 × 158` | `(319, 578)` | `(228, 499)` |
| **K15** | `(2, 2)` | `(458, 499)` | `(615, 656)` | `158 × 158` | `(537, 578)` | `(446, 499)` |
| **K16** | `(3, 2)` | `(676, 499)` | `(833, 656)` | `158 × 158` | `(755, 578)` | `(664, 499)` |
| **K17** | `(4, 2)` | `(894, 499)` | `(1051, 656)` | `158 × 158` | `(973, 578)` | `(882, 499)` |
| **K18** | `(5, 2)` | `(1112, 499)` | `(1269, 656)` | `158 × 158` | `(1191, 578)` | `(1100, 499)` |

### 3.3 Non-Key Margin & Gutter Regions (`1280 × 720`)

Horizontal pixel budget (`1280 px` total):
$$\underbrace{22\text{ px}}_{\text{Left Margin}} + 6 \times \underbrace{158\text{ px}}_{\text{Key Width}} + 5 \times \underbrace{60\text{ px}}_{\text{Gap X}} + \underbrace{10\text{ px}}_{\text{Right Margin}} = 22 + 948 + 300 + 10 = 1280\text{ px}$$

Vertical pixel budget (`720 px` total):
$$\underbrace{63\text{ px}}_{\text{Top Margin}} + 3 \times \underbrace{158\text{ px}}_{\text{Key Height}} + 2 \times \underbrace{60\text{ px}}_{\text{Gap Y}} + \underbrace{63\text{ px}}_{\text{Bottom Margin}} = 63 + 474 + 120 + 63 = 720\text{ px}$$

| Region Name | Pixel Range `(x, y, width, height)` | Dimensions | Notes |
| :--- | :---: | :---: | :--- |
| **Top Margin Band** | `(0, 0, 1280, 63)` | `1280 × 63 px` | Above Row 0 (`y = 0..62`) |
| **Bottom Margin Band** | `(0, 657, 1280, 63)` | `1280 × 63 px` | Below Row 2 (`y = 657..719`) |
| **Left Outer Margin** | `(0, 0, 22, 720)` | `22 × 720 px` | Left of Column 0 (`x = 0..21`) |
| **Right Outer Margin** | `(1270, 0, 10, 720)` | `10 × 720 px` | Right of Column 5 (`x = 1270..1279`) |
| **Vertical Gutter 0–1** | `(180, 63, 60, 594)` | `60 × 594 px` | Between Col 0 and Col 1 (`x = 180..239`) |
| **Vertical Gutter 1–2** | `(398, 63, 60, 594)` | `60 × 594 px` | Between Col 1 and Col 2 (`x = 398..457`) |
| **Vertical Gutter 2–3** | `(616, 63, 60, 594)` | `60 × 594 px` | Between Col 2 and Col 3 (`x = 616..675`) |
| **Vertical Gutter 3–4** | `(834, 63, 60, 594)` | `60 × 594 px` | Between Col 3 and Col 4 (`x = 834..893`) |
| **Vertical Gutter 4–5** | `(1052, 63, 60, 594)` | `60 × 594 px` | Between Col 4 and Col 5 (`x = 1052..1111`) |
| **Horizontal Gutter 0–1** | `(22, 221, 1248, 60)` | `1248 × 60 px` | Between Row 0 and Row 1 (`y = 221..280`) |
| **Horizontal Gutter 1–2** | `(22, 439, 1248, 60)` | `1248 × 60 px` | Between Row 1 and Row 2 (`y = 439..498`) |

---

## 4. Portrait Orientation (`720 × 1280`, 6 Rows × 3 Columns)

The LCD panel inside the SK18 has a native portrait scanout (`720 × 1280`). When `KeyboardDevice` starts up, `get_screen_width()` (`0xc4558`) and `get_screen_height()` (`0xc45ac`) query `QApplication::desktop()->screenGeometry()`. When the Linux framebuffer is in its default unrotated `720 × 1280` mode, `processModel("SK18")` (`0x87c10`) selects the `rotate = true` `foregroundParam` entry (`720 × 1280`, `rectRows = 6`, `rectCols = 3`).

### 4.1 Physical Key Coordinate Formula (Portrait)
For any key at `(col, row)` where `col ∈ [0, 2]` and `row ∈ [0, 5]`:

$$\begin{aligned}
x &= 63 + \text{col} \times (158 + 60) = 63 + 218 \times \text{col} \\
y &= 22 + \text{row} \times (158 + 60) = 22 + 218 \times \text{row} \quad (\text{raw } \texttt{getInfo} \text{ reports } 10 + 218 \times \text{row}) \\
\text{width} &= 158 \\
\text{height} &= 158
\end{aligned}$$

### 4.2 Complete 18-Key Physical Coordinate Table (`720 × 1280`)

| Portrait `(col, row)` | Physical Top-Left `(x, y)` | Bottom-Right `(x2, y2)` (inclusive) | Size (`w × h`) | Raw `getInfo` `(x, y)` |
| :---: | :---: | :---: | :---: | :---: |
| `(0, 0)` | `(63, 22)` | `(220, 179)` | `158 × 158` | `(63, 10)` |
| `(1, 0)` | `(281, 22)` | `(438, 179)` | `158 × 158` | `(281, 10)` |
| `(2, 0)` | `(499, 22)` | `(656, 179)` | `158 × 158` | `(499, 10)` |
| `(0, 1)` | `(63, 240)` | `(220, 397)` | `158 × 158` | `(63, 228)` |
| `(1, 1)` | `(281, 240)` | `(438, 397)` | `158 × 158` | `(281, 228)` |
| `(2, 1)` | `(499, 240)` | `(656, 397)` | `158 × 158` | `(499, 228)` |
| `(0, 2)` | `(63, 458)` | `(220, 615)` | `158 × 158` | `(63, 446)` |
| `(1, 2)` | `(281, 458)` | `(438, 615)` | `158 × 158` | `(281, 446)` |
| `(2, 2)` | `(499, 458)` | `(656, 615)` | `158 × 158` | `(499, 446)` |
| `(0, 3)` | `(63, 676)` | `(220, 833)` | `158 × 158` | `(63, 664)` |
| `(1, 3)` | `(281, 676)` | `(438, 833)` | `158 × 158` | `(281, 664)` |
| `(2, 3)` | `(499, 676)` | `(656, 833)` | `158 × 158` | `(499, 664)` |
| `(0, 4)` | `(63, 894)` | `(220, 1051)` | `158 × 158` | `(63, 882)` |
| `(1, 4)` | `(281, 894)` | `(438, 1051)` | `158 × 158` | `(281, 882)` |
| `(2, 4)` | `(499, 894)` | `(656, 1051)` | `158 × 158` | `(499, 882)` |
| `(0, 5)` | `(63, 1112)` | `(220, 1269)` | `158 × 158` | `(63, 1100)` |
| `(1, 5)` | `(281, 1112)` | `(438, 1269)` | `158 × 158` | `(281, 1100)` |
| `(2, 5)` | `(499, 1112)` | `(656, 1269)` | `158 × 158` | `(499, 1100)` |

### 4.3 Transforming Between Landscape (`1280×720`) and Portrait (`720×1280`)
Notice that the portrait geometry (`startX = 63, startY = 10`) is an exact transpose / 90-degree rotation of the landscape geometry (`startX = 10, startY = 63`):
- If a device reports `deviceWidth = 720, deviceHeight = 1280` in `getInfo`, its hardware JPEG decoder (`SerialPort::parse_cmd_new_t` at `0x108d8c`) requires incoming `CMD_VALUE_SHOW_JPG` frames to have dimensions **`720 × 1280`** (multiples of 16: `720 = 45 × 16`, `1280 = 80 × 16`).
- You can either:
  1. Render directly onto a `720 × 1280` `QImage` using the portrait key rects `(col ∈ [0..2], row ∈ [0..5])`, or
  2. Author your UI in `1280 × 720` landscape `(col ∈ [0..5], row ∈ [0..2])` and rotate the image by 90° (`QTransform().rotate(90)` or `rotate(-90)`) before JPEG encoding, mapping incoming portrait `keyStateChanged(pCol, pRow)` events to landscape `(col, row)`. Both modes are supported in the PoC's `Sk18CanvasRenderer`.
