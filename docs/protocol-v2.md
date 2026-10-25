# Waveshare SK18 Protocol V2 Specification (Open Serial & JSON-RPC Protocol)

Protocol V2 is the packet-framed binary + JSON-RPC protocol implemented in `KeyboardDevice` (`V2.32`) and used by `OpenSourceLicenseDemo_V1.0`. It operates over the USB CDC-ACM virtual serial port (`/dev/ttyACM*` on Linux, mapped to `/dev/ttyGS0` on the SK18's Allwinner T113 SoC).

All details below were verified against `SerialPort::readyRead()` (`0x10bbd8`), `SerialPort::parse_cmd_new()` (`0x108090`), `SerialPort::parse_cmd_new_t()` (`0x108978`), `initRemoteAPI()` (`0x6283c`), and the 10 command handlers (`0x60b44`–`0x66328`) inside `KeyboardDevice`.

---

## 1. Serial Transport Settings

- **Interface**: USB CDC-ACM (`/dev/ttyACM0` on Linux)
- **Baud Rate**: `115200` (Virtual USB CDC-ACM runs at full USB High-Speed bulk transfer rates regardless of nominal baud rate, sustaining ~3–8 MB/s)
- **Data Bits**: `8`
- **Parity**: `None`
- **Stop Bits**: `1`
- **Flow Control**: `None` (`NoFlowControl`)

---

## 2. Connection Initialization & Switching from V1 to V2 Mode

When `KeyboardDevice` boots on the SK18, `ConfigManager` sets `deviceProtocolVersion = "V1"` by default (`main` at `0x32054`). Furthermore, if a previous host session was interrupted mid-file-transfer in V1 mode, `SerialPort::m_receive_file_size` (`0x10bc50`) may be non-zero, causing `readyRead()` to divert incoming bytes into `receive_file_data()`.

### 2.1 Fast V1 Abort Sequence (Recommended)
Disassembly of `SerialPort::readyRead()` (`0x10bc0c`) reveals an explicit built-in abort command:

```text
AA551234 Abort file transfer 123455AA
```

When `readyRead()` receives a buffer starting with those exact 37 ASCII bytes:
1. It logs `"Abort file transfer"`,
2. Resets `m_receive_file_size = 0` and clears the partial file buffer immediately, and
3. Replies with `"AA551234 Abort file transfer ok"`.

*(Note: `OpenSourceLicenseDemo_V1.0` instead sends `1 MB` of `'0'` bytes `QByteArray(1048576, '0')` on connect to brute-force exhaust `m_receive_file_size`. Sending `"AA551234 Abort file transfer 123455AA"` achieves the exact same reset instantaneously without a 1 MB write delay.)*

### 2.2 Activating Protocol V2 (`getInfo`)
In `SerialPort::readyRead()` (`0x10bd5c`), as soon as `m_receive_file_size == 0`, the daemon inspects the first 4 bytes of incoming data:
- If the data starts with `0x5E, 0x5A, 0xA5, 0xA1` (the little-endian representation of `0xA1A55A5E`), it routes the buffer to `SerialPort::parse_cmd_new()`.
- Sending the `getInfo` JSON-RPC command sets `deviceProtocolVersion = "V2"` (`handleGetInfo` at `0x63d90`), stops the on-device standalone V1 theme player (`VideoPlayer`), and enables live `CMD_VALUE_SHOW_JPG` streaming and `keyStateChanged` reporting.

---

## 3. V2 Binary Frame Format

Every V2 packet—in both directions (Host → Device and Device → Host)—uses a **24-byte overhead envelope** (`20-byte header + N-byte payload + 4-byte trailer`). All multi-byte integers are **32-bit little-endian (`<I` / `quint32` / `qint32`)**.

```text
Offset  Size    Type      Field       Description
------  ------  --------  ----------  --------------------------------------------------------
0x00    4       uint32    header      Magic constant: 0xA1A55A5E (bytes: 5E 5A A5 A1)
0x04    4       int32     id          Monotonically increasing packet ID (or -1 on error)
0x08    4       uint32    cmd         Command type: 100 (SHOW_JPG) or 101 (JSON)
0x0C    4       uint32    size        Payload length in bytes (N)
0x10    4       uint32    size_crc    CRC32 of the 4-byte little-endian `size` field (0x0C..0x0F)
0x14    N       bytes     data        Payload bytes (JPEG binary or UTF-8 JSON object)
0x14+N  4       uint32    data_crc    CRC32 of the N-byte `data` field (0x14..0x14+N-1)
```

### 3.1 Command Values (`Sk18CmdValue`)
| Enum Name | Value (`uint32`) | Payload Format | Description |
| :--- | :---: | :--- | :--- |
| `CMD_VALUE_SHOW_JPG` | `100` (`0x64`) | Raw JPEG image bytes (`Host → Device`) or empty `0`-byte ACK (`Device → Host`) | Hardware-decoded full-screen JPEG frame |
| `CMD_VALUE_JSON` | `101` (`0x65`) | UTF-8 JSON object (`{...}`) | JSON-RPC command request, response, error, or async event |
| `CMD_VALUE_END` | `102` (`0x66`) | Sentinel | End-of-enum sentinel (rejected if `cmd >= 102`) |

### 3.2 CRC32 Algorithm
Both `size_crc` and `data_crc` use the standard **IEEE 802.3 CRC32** polynomial (`0xEDB88320` reflected / `0x04C11DB7` normal, initial value `0xFFFFFFFF`, final XOR `0xFFFFFFFF`):
- Matches Python's `zlib.crc32(data) & 0xFFFFFFFF`.
- For an empty payload (`size == 0`, such as the device's `CMD_VALUE_SHOW_JPG` ACK packet):
  - `size` bytes are `00 00 00 00` → `size_crc = 0x2144DF1C` (`558161692`)
  - `data` is `""` (0 bytes) → `data_crc = 0x00000000` (`0`)

---

## 4. Full-Screen JPEG Streaming (`CMD_VALUE_SHOW_JPG = 100`)

To display graphics on the SK18 LCD, send a V2 packet with `cmd = 100` (`CMD_VALUE_SHOW_JPG`) where `data` contains a complete baseline JPEG file (`FF D8 ... FF D9`).

### 4.1 Resolution Constraints
Inside `SerialPort::parse_cmd_new_t()` (`0x108d00`–`0x108f80`), the device validates the JPEG dimensions before decoding:
1. Both width and height must match the device's active framebuffer dimensions (`deviceWidth × deviceHeight` reported in `getInfo`, i.e., `1280×720` or `720×1280`, both of which are multiples of 16 for the CedarX hardware decoder). If they do not match, the device returns an error packet (`cmd = 101`, `id = -1`):
   `"Incorrect resolution, the device requires the resolution to be <W>x<H>"`.
2. If hardware JPEG decoding fails, the device returns:
   `"Image decoding failed, the image size may be larger than <W>x<H>"`.

### 4.2 Hardware Decode & ACK Flow Control
1. When the JPEG passes validation, `SerialPort::parse_cmd_new_t()` decodes it via `JpegDecoderSingleton::decode` (CedarX hardware engine) and blits it to the screen via `/dev/g2d` (`CreateVideoOutport`).
2. Once the frame is displayed, the device sends back an **ACK packet**:
   - `header = 0xA1A55A5E`
   - `id = <request_id>` (echoes the exact `id` of the frame that finished rendering)
   - `cmd = 100` (`CMD_VALUE_SHOW_JPG`)
   - `size = 0`
   - `size_crc = 0x2144DF1C`
   - `data = ""` (0 bytes)
   - `data_crc = 0x00000000`
3. **Best Practice for Host Applications**:
   - Gate continuous frame transmission on receiving the `CMD_VALUE_SHOW_JPG` ACK for the in-flight frame (with a ~500 ms watchdog timeout in case a serial byte was dropped).
   - For static macro pads where the screen only changes on button presses or status updates, only send a `CMD_VALUE_SHOW_JPG` frame when the canvas is marked dirty.

---

## 5. JSON-RPC Commands & Events (`CMD_VALUE_JSON = 101`)

All JSON-RPC requests (`Host → Device`) use `cmd = 101` (`CMD_VALUE_JSON`) with a UTF-8 JSON object containing `"method"` and (when arguments are needed) `"parameters"`.

### 5.1 Standard Response & Error Envelopes

#### Command Acknowledgment Response (`Device → Host`, `cmd = 101`, `id = <request_id>`)
When `RemoteCommandExecutor::execute` processes a request, it returns a JSON object containing `"ack_method"` and `"success"`:
```json
{
  "ack_method": "<methodName>",
  "success": true,
  "result": {
    ...
  }
}
```
If validation inside a command handler fails, `"success"` is `false` and `"errorString"` describes the error:
```json
{
  "ack_method": "<methodName>",
  "success": false,
  "errorString": "<human-readable reason>"
}
```

#### Transport / Framing Error Response (`Device → Host`, `cmd = 101`, `id = -1`)
If `SerialPort::parse_cmd_new_t()` encounters a framing/JSON error or JPEG resolution mismatch, it sends a packet with `id = -1` (`0xFFFFFFFF`):
```json
{
  "errorString": "<human-readable reason>",
  "method": "<methodName>",
  "requestId": 42
}
```

---

### 5.2 All 10 Registered JSON-RPC Methods

The following 10 methods are registered in `initRemoteAPI()` (`0x6283c` in `KeyboardDevice`):

---

#### 1. `getInfo`
Switches the device into Protocol V2 mode (`deviceProtocolVersion = "V2"`) and returns the firmware version, model name, screen dimensions, key grid dimensions, and rectangle coordinates.

- **Request**:
  ```json
  {
    "method": "getInfo"
  }
  ```
- **Response**:
  ```json
  {
    "ack_method": "getInfo",
    "success": true,
    "result": {
      "deviceVersion": "V2.32",
      "deviceModel": "SK18",
      "deviceWidth": 1280,
      "deviceHeight": 720,
      "devicePanel": {
        "screenWidth": 1280,
        "screenHeight": 720,
        "rectRows": 3,
        "rectCols": 6,
        "rects": [
          { "col": 0, "row": 0, "x": 10, "y": 63, "width": 158, "height": 158, "isKey": true },
          { "col": 1, "row": 0, "x": 228, "y": 63, "width": 158, "height": 158, "isKey": true }
        ]
      }
    }
  }
  ```
  *(Note: If the SK18's Linux framebuffer is running in native portrait mode, `deviceWidth` / `screenWidth` is `720`, `deviceHeight` / `screenHeight` is `1280`, `rectRows` is `6`, and `rectCols` is `3`. Additionally, `getInfo` returns the unflipped `foregroundParamArray` offset `10` along the `1280 px` axis (`y = 10, 228, ...` in portrait or `x = 10, 228, ...` in landscape); add `+12 px` (`22, 240, 458, 676, 894, 1112`) so the `22 px` margin is on the physical left and `10 px` is on the physical right.)*

---

#### 2. `setBacklight`
Sets the LCD backlight brightness (`0–100`).

- **Request**:
  ```json
  {
    "method": "setBacklight",
    "parameters": {
      "level": 80
    }
  }
  ```
- **Validation (`handleSetBacklight` at `0x60eb0`)**:
  - `"level"` must be an integer in `[0, 100]`.
  - Errors: `"Missing 'level' parameter"`, `"'level' must be a number"`, `"Backlight level must be between 0 and 100, got %1"`.

---

#### 3. `setVolume`
Sets the built-in speaker amplifier volume (`0–7`).

- **Request**:
  ```json
  {
    "method": "setVolume",
    "parameters": {
      "level": 5
    }
  }
  ```
- **Validation (`handleSetVolume` at `0x613a8`)**:
  - `"level"` must be an integer in `[0, 7]`.
  - Errors: `"Missing 'level' parameter"`, `"'level' must be a number"`, `"Volume level must be between 0 and 7, got %1"`.

---

#### 4. `keyboardInput`
Sends an ASCII text string from the T113 SoC over `/dev/ttyS1` to the STM32 QMK controller (`STM32CommunicationObject::request_upload_string`), which types it to the host PC as genuine USB HID keyboard keystrokes.

- **Request**:
  ```json
  {
    "method": "keyboardInput",
    "parameters": {
      "inputString": "Hello! 7895123"
    }
  }
  ```
- **Response (`result`)**:
  ```json
  {
    "inputLength": 14,
    "inputString": "Hello! 7895123"
  }
  ```
- **Validation (`handleKeyboardInput` at `0x62134`)**:
  - `"inputString"` must be a non-empty string.
  - Errors: `"Missing 'inputString' parameter"`, `"'inputString' must be a string"`, `"'inputString' cannot be empty"`.

---

#### 5. `getFilesBySuffix`
Lists files stored on the device matching one or more file extensions, along with their stored CRC32 values.

- **Request**:
  ```json
  {
    "method": "getFilesBySuffix",
    "parameters": {
      "suffixs": ["wav"]
    }
  }
  ```
  *(Note the firmware's exact parameter spelling: `"suffixs"`).*
- **Response**:
  ```json
  {
    "ack_method": "getFilesBySuffix",
    "success": true,
    "result": {
      "filePaths": [
        {
          "filePath": "/data/sound/temp.wav",
          "crc": "2713489012"
        }
      ]
    }
  }
  ```
- **Validation (`handleGetFilesBySuffix` at `0x62db4`)**:
  - `"suffixs"` must be an array of strings (`"Missing 'suffixs' parameter"`, `"'suffixs' must be an array"`, `"All elements in 'suffixs' must be strings. Element at index %1 is not a string"`).

---

#### 6. `saveToFile`
Writes a Base64-encoded chunk of data at byte offset `seek` to `filePath` (e.g., `/data/sound/temp.wav`). Used to upload `.wav` audio files in 64 KB (`65536`-byte) raw chunks.

- **Request**:
  ```json
  {
    "method": "saveToFile",
    "parameters": {
      "filePath": "/data/sound/temp.wav",
      "seek": 0,
      "data": "<base64-encoded-bytes>"
    }
  }
  ```
- **Response (`result`)**:
  ```json
  {
    "filePath": "/data/sound/temp.wav",
    "seek": 0
  }
  ```
  - Upon receiving the `saveToFile` ACK for `seek = N`, advance by `65536` (`seek = N + 65536`) and send the next chunk until all bytes are written, then call `setFileCRC`.
- **Validation (`handleSaveToFile` at `0x64460`)**:
  - Requires `"filePath"` (string), `"seek"` (non-negative integer), and `"data"` (Base64 string).

---

#### 7. `setFileCRC`
Records the expected CRC32 checksum string (`QString::number(crc32)`) for an uploaded file in the device's file manager.

- **Request**:
  ```json
  {
    "method": "setFileCRC",
    "parameters": {
      "filePath": "/data/sound/temp.wav",
      "crc": "2713489012"
    }
  }
  ```

---

#### 8. `deleteFiles`
Deletes one or more files from the device.

- **Request**:
  ```json
  {
    "method": "deleteFiles",
    "parameters": {
      "filePaths": ["/data/sound/temp.wav"]
    }
  }
  ```
- **Response (`result`)**:
  Contains `"deletedFiles"` and `"failedFiles"`.

---

#### 9. `playAudio`
Plays a `.wav` file on the device through the SK18's internal speaker using ALSA `tinyplay`.

- **Request**:
  ```json
  {
    "method": "playAudio",
    "parameters": {
      "filePath": "/data/sound/temp.wav"
    }
  }
  ```
- **Validation (`handlePlayAudio` at `0x65bd0`)**:
  - File must exist and have a `.wav` extension (`"File does not exist: %1"`, `"File is not a WAV file: %1"`).

---

#### 10. `stopAudio`
Immediately stops any currently playing `.wav` audio process (`tinyplay`).

- **Request**:
  ```json
  {
    "method": "stopAudio"
  }
  ```

---

## 6. Asynchronous Device Events (`Device → Host`)

### 6.1 `keyStateChanged`
Whenever a physical switch on the SK18 is pressed or released while `deviceProtocolVersion == "V2"`, `SerialPort::device_keyState_Changed(int col, int row, bool state)` (`0x1093e8`) sends an unsolicited V2 packet (`cmd = 101`) to the host:

```json
{
  "method": "keyStateChanged",
  "parameters": {
    "col": 2,
    "row": 1,
    "pressed": true
  }
}
```

- `col`: Zero-based column index (`0..5` in landscape `3×6`, or `0..2` in portrait `6×3`).
- `row`: Zero-based row index (`0..2` in landscape `3×6`, or `0..5` in portrait `6×3`).
- `pressed`: `true` when the key is pressed down, `false` when the key is released.
