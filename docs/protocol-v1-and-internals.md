# Waveshare SK18 Protocol V1, `.Theme` Format & STM32 QMK Internals

This document covers the reverse-engineered internals of the SK18 that are **not** included in the vendor's open-source demo:
1. **Protocol V1 (`AA551234 FIXEDCMDHEAD`)** used by the closed-source Windows/macOS `ScreenKey` app to upload standalone themes, H.264 videos, and keymaps.
2. **The `.Theme` Container Format** extracted from `/defaultData/static/theme/SK18/defaultTheme.Theme`.
3. **The Internal `/dev/ttyS1` STM32 UART Protocol (`0xAA 0x55 ... 0xF5 0x5F`)** between the Allwinner T113 SoC and the STM32 QMK/VIA controller.
4. **The On-Device Tina Linux Filesystem Layout**.

---

## 1. Protocol V1 (`AA551234 FIXEDCMDHEAD`)

When `KeyboardDevice` boots, it defaults to `deviceProtocolVersion = "V1"` until a V2 `0xA1A55A5E` packet (`getInfo`) is received. In V1 mode, `SerialPort::readyRead()` (`0x10bbd8`) and `SerialPort::parse_cmd()` (`0x107ba0`) parse packets prefixed with the 21-byte ASCII magic header:

```text
AA551234 FIXEDCMDHEAD
```

### 1.1 V1 Packet Envelope (`SerialPort::packet_cmd` at `0x107960`)

```text
Offset  Size    Type               Field       Description
------  ------  -----------------  ----------  ---------------------------------------------------
0x00    21      char[21]           magic       ASCII "AA551234 FIXEDCMDHEAD"
0x15    1       uint8              type        DATA_PACKET_TYPE (0..3)
0x16    1       uint8              cmd         CMD_VALUE (0..15)
0x17    4       uint32 (LE)        size        Payload size in bytes (N)
0x1B    N       bytes              data        Payload (often Qt QDataStream serialized)
0x1B+N  4       uint32 (LE)        crc         IEEE CRC32 of the N-byte `data` payload
```

### 1.2 `DATA_PACKET_TYPE` Enum (`0..3`)
Verified from DWARF debug symbols in `KeyboardDevice`:

| Value | Enum Name | Description |
| :---: | :--- | :--- |
| `0` | `DATA_PACKET_TYPE_CMD` | Command request from host to device |
| `1` | `DATA_PACKET_TYPE_CMD_ACK` | Command acknowledgment / response from device to host |
| `2` | `DATA_PACKET_TYPE_FILE` | Bulk file transfer initiation |
| `3` | `DATA_PACKET_TYPE_FILE_ACK` | Bulk file transfer acknowledgment |

### 1.3 V1 `CMD_VALUE` Enum (`0..15`)
Verified from DWARF debug symbols and `SerialPort::processReceivedData()` (`0x10bf2c`):

| Value | Enum Name | Handler Behavior in `SerialPort::processReceivedData` |
| :---: | :--- | :--- |
| `0` | `CMD_VALUE_NONE` | No-op |
| `1` | `CMD_VALUE_FIRM` | Firmware update package transfer (`/mnt/SDCARD/...`) |
| `2` | `CMD_VALUE_IMAGE` | Static image / bootlogo transfer |
| `3` | `CMD_VALUE_VIDOE` *(sic)* | Video / `.Theme` bundle transfer; unpacks theme and updates `VideoPlayer` |
| `4` | `CMD_VALUE_DEFAULT_THEME` | Switches active theme in `ConfigManager` |
| `5` | `CMD_VALUE_READ` | Calls `getScreenMessage()` (`0xc703c`) and returns device JSON status (`model`, `ver`, `bl`, `vol`, `themeList`, etc.) |
| `6` | `CMD_VALUE_CONTRO` *(sic)* | Dynamic runtime data update (CPU/GPU/RAM telemetry, clock/weather strings for V1 widgets) |
| `7` | `CMD_VALUE_BL` | Sets backlight (`device_set_bl_value(int)`) |
| `8` | `CMD_VALUE_REST` | Resets device configuration (`device_rest()`) |
| `9` | `CMD_VALUE_KEY` | Programs STM32 QMK keymap (`STM32CommunicationObject::dynamic_keymap_set_keycode` / `request_upload_string`) |
| `10` | `CMD_VALUE_CAROUSEL` | Configures theme page carousel rotation interval |
| `11` | `CMD_VALUE_AI_URL` | Configures XiaoZhi AI WebSocket endpoint (`wss://api.tenclass.net/xiaozhi/v1/`) |
| `12` | `CMD_VALUE_VOL` | Sets speaker volume (`0–7`) |
| `13` | `CMD_VALUE_ DISPALY_DIRECTION` *(sic)* | Sets display orientation (`rotate` flag in `ConfigManager`) |
| `14` | `CMD_VALUE_ENABLE_XIAOZHIAI` | Enables/disables built-in XiaoZhi voice assistant integration |
| `15` | `CMD_VALUE_END` | End sentinel |

### 1.4 V1 File Transfer State Machine & Abort Sequence
When a V1 command transfers a file (`CMD_VALUE_FIRM`, `CMD_VALUE_IMAGE`, `CMD_VALUE_VIDOE`), the payload contains a `QDataStream` with `(QString fileName, quint32 fileSize, quint32 fileCrc)`.
- The device replies with `"AA551234 READY RECEIVE FILE"` and sets `m_receive_file_size = fileSize`.
- Subsequent raw serial bytes are appended directly to the file until `m_receive_file_size` reaches `0`, at which point the device verifies the CRC and sends `"AA551234 file receive ok"` or `"AA551234 file receive error"`.
- Sending `"AA551234 Abort file transfer 123455AA"` at any time immediately aborts the transfer and resets `m_receive_file_size = 0`.

---

## 2. The `.Theme` File Format (`defaultTheme.Theme`)

In standalone V1 mode, the SK18 plays `.Theme` packages stored on `/mnt/SDCARD/theme/`. Inspecting `/defaultData/static/theme/SK18/defaultTheme.Theme` from `ScreenKeyMacOS` shows how themes are structured:

1. **Binary Header + Embedded Media Assets**:
   - Contains packed H.264 `.mp4` background loops (decoded by CedarX `VideoPlayer`), `.wav` key-click sound effects, and `.png` icon overlays.
2. **Theme Layout JSON Descriptor**:
   - Defines `screenWidth: 1280`, `screenHeight: 720`, `rotate: true/false`, and a `pages` array.
   - Each page defines items bound to the 18 key slots (`index: 0..17`), specifying:
     - `keyCode` / QMK macro binding (`basic`, `shortcut`, `string`, `multimedia`, `mouse`, `pageSwitch`, `sound`, `website`, `program`)
     - Text overlay properties (`font`, `fontSize`, `color`, `position`)
     - Audio feedback `.wav` filename

---

## 3. Internal `/dev/ttyS1` STM32 QMK/VIA UART Protocol

The Allwinner T113 SoC communicates with the STM32 QMK/VIA microcontroller over internal UART `/dev/ttyS1` (`STM32CommunicationObject` at `0x5d808`–`0x5fef8`).

### 3.1 UART Frame Format (`STM32CommunicationObject::packFrame` at `0x5d808`)

```text
Offset  Size    Value        Field       Description
------  ------  -----------  ----------  --------------------------------------------------------
0x00    1       0xAA         head0       Start-of-frame byte 0
0x01    1       0x55         head1       Start-of-frame byte 1
0x02    1       L (uint8)    length      Payload length in bytes
0x03    L       bytes        payload     Command ID + arguments (VIA / custom QMK command bytes)
0x03+L  2       uint16       crc16       16-bit checksum (`calculateCRC`) over payload
0x05+L  1       0xF5         tail0       End-of-frame byte 0
0x06+L  1       0x5F         tail1       End-of-frame byte 1
```

### 3.2 Key Methods in `STM32CommunicationObject`
| Symbol in `KeyboardDevice` | Address | Description |
| :--- | :---: | :--- |
| `dynamic_keymap_set_keycode(u8 layer, u8 row, u8 col, u16 keycode)` | `0x5dd88` | Writes a QMK 16-bit keycode to `(layer, row, col)` in STM32 EEPROM via VIA command `0x05` (`id_dynamic_keymap_set_keycode`). |
| `dynamic_keymap_get_keycode(u8 layer, u8 row, u8 col)` | `0x5de44` | Reads current keycode at `(layer, row, col)` via VIA command `0x04`. |
| `dynamic_keymap_reset()` | `0x5dee4` | Resets STM32 EEPROM keymap to factory defaults (`0x06`). |
| `request_upload_key(u16 keycode)` | `0x5df90` | Commands the STM32 to immediately tap a 16-bit QMK keycode over USB HID. |
| `request_mouse_control(u8 btn, s8 x, s8 y, s8 wheel)` | `0x5e040` | Commands the STM32 to emit a USB HID mouse report. |
| `request_bootloader_jump()` | `0x5e0f4` | Jumps the STM32 into DFU/bootloader mode for flashing `syk_keyboards_sk18_via.bin`. |
| `request_upload_string(QString const&)` | `0x5f014` | Converts an ASCII string into a sequence of QMK HID keycode frames and transmits them to the STM32 (invoked by V2 `keyboardInput`). |
| `processData()` | `0x5f7b4` | Parses incoming `0xAA 0x55 ... 0xF5 0x5F` frames from `/dev/ttyS1` and emits `keyStateChanged(int col, int row, bool pressed)`. |

---

## 4. On-Device Tina Linux Filesystem Layout

From inspecting `MK10_V1.0.img` and path references in `KeyboardDevice`:

| On-Device Path | Purpose |
| :--- | :--- |
| `/sys/firmware/devicetree/base/model` | Hardware model string (`"SK18"`, `"MK10"`, `"MK20"`) read by `get_screen_model()`. |
| `/data/KeyboardDevice` | Main Qt5 ARM32 application daemon (`V2.32`) launched at boot. |
| `/dev/ttyGS0` | USB Gadget CDC-ACM serial port connected to the host PC (`/dev/ttyACM*`). |
| `/dev/ttyS1` | Internal hardware UART connected to the STM32 QMK/VIA controller. |
| `/dev/cedar_dev` | Allwinner CedarX hardware JPEG / H.264 video decoder device node. |
| `/dev/g2d` | Allwinner G2D 2D hardware graphics blitter and rotator. |
| `/mnt/SDCARD/config.json` | Persistent JSON configuration (`deviceProtocolVersion`, backlight, volume, active theme, rotate flag). |
| `/mnt/SDCARD/customData/` | Storage directory for V2 uploaded `.wav` files and `fileCRC.json`. |
| `/mnt/SDCARD/theme/` | Storage directory for V1 `.Theme` packages (`defaultTheme`). |
