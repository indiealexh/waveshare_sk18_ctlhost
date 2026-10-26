import 'dart:convert';
import 'dart:typed_data';

class ProtocolV2Packet {
  final int id;
  final int cmd;
  final Uint8List payload;
  final bool isV1;
  final int v1Type;

  const ProtocolV2Packet({
    required this.id,
    required this.cmd,
    required this.payload,
    this.isV1 = false,
    this.v1Type = 0,
  });

  bool get isShowJpg => !isV1 && cmd == ProtocolV2Codec.cmdShowJpg;
  bool get isJson => !isV1 && cmd == ProtocolV2Codec.cmdJson;

  Map<String, dynamic>? decodeJson() {
    if (payload.isEmpty) return null;
    try {
      final text = utf8.decode(payload, allowMalformed: true);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, String> decodeV1StringMap() {
    return ProtocolV2Codec.decodeV1StringMap(payload);
  }

  List<Map<String, dynamic>> decodeV1ProactiveEscalation() {
    return ProtocolV2Codec.decodeV1ProactiveEscalationList(payload);
  }
}

/// Implements the Waveshare SK18 / MK10 Protocol V2 (`0xA1A55A5E`) and
/// Protocol V1 (`AA551234 FIXEDCMDHEAD `) binary packet framing,
/// IEEE 802.3 CRC32 calculation, 37-byte V1 abort handshake, and two-stage
/// stream resynchronization.
class ProtocolV2Codec {
  /// 37-byte ASCII abort sequence that exits any stale Protocol V1 transfer immediately.
  static const String v1AbortCommand = 'AA551234 Abort file transfer 123455AA';
  static const String v1AbortAck = 'AA551234 Abort file transfer ok';

  /// 22-byte ASCII magic header for Protocol V1 (`V2.29` / `ScreenKey`) frames.
  static const String v1FixedCmdHeader = 'AA551234 FIXEDCMDHEAD ';
  static const int v1MagicLength = 22;
  static const int v1HeaderSize = 38; // 22-byte magic + 16-byte LE [type, cmd, size, crc]

  static const int v1TypeCmd = 0;
  static const int v1TypeCmdAck = 1;
  static const int v1TypeData = 2;

  static const int v1CmdFindDevice = 0;
  static const int v1CmdSetSystemData = 1;
  static const int v1CmdSetReload = 2;
  static const int v1CmdGetThemes = 3;
  static const int v1CmdSetBacklight = 4;
  static const int v1CmdGetVersion = 8;
  static const int v1CmdSetCanvasFlip = 9;
  static const int v1CmdGetScreenMessage = 10;
  static const int v1CmdDeleteThemes = 11;
  static const int v1CmdSendPixmap = 12;
  static const int v1CmdProactiveEscalation = 13;
  static const int v1CmdRequestUploadKey = 14;
  static const int v1CmdSendJson = 15;

  static const int cmdShowJpg = 100;
  static const int cmdJson = 101;
  static const int cmdEnd = 102;

  static const int headerSize = 20;
  static const int trailerSize = 4;
  static const int envelopeOverhead = 24;
  static const int maxPayloadSize = 16 * 1024 * 1024; // 16 MB

  static const int emptySizeCrc32 = 0x2144DF1C;
  static const int emptyDataCrc32 = 0x00000000;

  static final List<int> _crcTable = _buildCrc32Table();

  const ProtocolV2Codec._();

  static List<int> _buildCrc32Table() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int bit = 0; bit < 8; bit++) {
        if ((crc & 1) != 0) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc = crc >>> 1;
        }
      }
      table[i] = crc & 0xFFFFFFFF;
    }
    return table;
  }

  /// Computes standard IEEE 802.3 CRC32 (`0xEDB88320` reflected polynomial).
  /// Returns `0x00000000` for an empty byte list.
  static int crc32(List<int> bytes) {
    if (bytes.isEmpty) return emptyDataCrc32;
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < bytes.length; i++) {
      final byte = bytes[i] & 0xFF;
      crc = (_crcTable[(crc ^ byte) & 0xFF] ^ (crc >>> 8)) & 0xFFFFFFFF;
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Computes CRC32 of a 4-byte little-endian `uint32` size value.
  /// When `size == 0`, returns `0x2144DF1C`.
  static int computeSizeCrc32(int size) {
    final sizeBytes = Uint8List(4);
    final bd = ByteData.sublistView(sizeBytes);
    bd.setUint32(0, size, Endian.little);
    return crc32(sizeBytes);
  }

  /// Returns the 37-byte V1 abort command bytes (`AA551234 Abort file transfer 123455AA`).
  static Uint8List encodeV1AbortCommand() {
    return Uint8List.fromList(ascii.encode(v1AbortCommand));
  }

  /// Encodes a Protocol V2 packet with the 24-byte envelope:
  /// - `0x00..0x03`: Magic header (`A1 A5 5A 5E` by default, or `5E 5A A5 A1` when `littleEndianMagic = true`)
  /// - `0x04..0x07`: `id` (`int32` little-endian)
  /// - `0x08..0x0B`: `cmd` (`uint32` little-endian, `100` or `101`)
  /// - `0x0C..0x0F`: `size` (`uint32` little-endian, payload length `N`)
  /// - `0x10..0x13`: `size_crc` (`uint32` little-endian, CRC32 of `0x0C..0x0F`)
  /// - `0x14..0x14+N`: `data` (`N` bytes)
  /// - `0x14+N..0x18+N`: `data_crc` (`uint32` little-endian, CRC32 of `data`)
  static Uint8List encodePacket({
    required int id,
    required int cmd,
    required List<int> payload,
    bool littleEndianMagic = false,
  }) {
    final payloadLength = payload.length;
    final frame = Uint8List(envelopeOverhead + payloadLength);
    final bd = ByteData.sublistView(frame);

    if (littleEndianMagic) {
      // 5E 5A A5 A1
      frame[0] = 0x5E;
      frame[1] = 0x5A;
      frame[2] = 0xA5;
      frame[3] = 0xA1;
    } else {
      // Always transmit A1 A5 5A 5E for stock V2.32 compatibility
      frame[0] = 0xA1;
      frame[1] = 0xA5;
      frame[2] = 0x5A;
      frame[3] = 0x5E;
    }

    bd.setInt32(4, id, Endian.little);
    bd.setUint32(8, cmd, Endian.little);
    bd.setUint32(12, payloadLength, Endian.little);

    final sizeCrc = crc32(Uint8List.sublistView(frame, 12, 16));
    bd.setUint32(16, sizeCrc, Endian.little);

    if (payloadLength > 0) {
      frame.setRange(20, 20 + payloadLength, payload);
    }

    final dataCrc = payloadLength == 0 ? emptyDataCrc32 : crc32(payload);
    bd.setUint32(20 + payloadLength, dataCrc, Endian.little);

    return frame;
  }

  static Uint8List encodeJsonRequest({
    required int id,
    required String method,
    Map<String, dynamic>? parameters,
  }) {
    final body = <String, dynamic>{
      'method': method,
      'parameters': ?parameters,
    };
    final jsonBytes = utf8.encode(jsonEncode(body));
    return encodePacket(id: id, cmd: cmdJson, payload: jsonBytes);
  }

  static Uint8List encodeJsonMap({
    required int id,
    required Map<String, dynamic> payloadMap,
  }) {
    final jsonBytes = utf8.encode(jsonEncode(payloadMap));
    return encodePacket(id: id, cmd: cmdJson, payload: jsonBytes);
  }

  static Uint8List encodeJpegFrame({
    required int id,
    required List<int> jpegBytes,
  }) {
    return encodePacket(id: id, cmd: cmdShowJpg, payload: jpegBytes);
  }

  /// Returns a 128 KB `'0'` padding burst followed by the 37-byte V1 abort sequence
  /// to flush any interrupted Protocol V2 frame payload left in `m_buffer_new`.
  static Uint8List encodeV2BufferFlushSequence({int paddingBytes = 131072}) {
    final abortBytes = encodeV1AbortCommand();
    final buf = Uint8List(paddingBytes + abortBytes.length);
    buf.fillRange(0, paddingBytes, 0x30); // '0'
    buf.setRange(paddingBytes, buf.length, abortBytes);
    return buf;
  }

  /// Encodes a Protocol V1 packet (`AA551234 FIXEDCMDHEAD ` + 16-byte LE header + payload).
  static Uint8List encodeV1Packet({
    int type = v1TypeCmd,
    required int cmd,
    List<int> payload = const [],
  }) {
    final payloadLength = payload.length;
    final frame = Uint8List(v1HeaderSize + payloadLength);
    final magicBytes = ascii.encode(v1FixedCmdHeader);
    frame.setRange(0, v1MagicLength, magicBytes);

    final bd = ByteData.sublistView(frame);
    bd.setUint32(22, type, Endian.little);
    bd.setUint32(26, cmd, Endian.little);
    bd.setUint32(30, payloadLength, Endian.little);
    final dataCrc = payloadLength == 0 ? emptyDataCrc32 : crc32(payload);
    bd.setUint32(34, dataCrc, Endian.little);

    if (payloadLength > 0) {
      frame.setRange(v1HeaderSize, v1HeaderSize + payloadLength, payload);
    }
    return frame;
  }

  /// Encodes a Qt `QDataStream` big-endian `QMap<QString, QString>`.
  static Uint8List encodeV1StringMap(Map<String, String> map) {
    final builder = BytesBuilder(copy: false);
    final countBytes = Uint8List(4);
    ByteData.sublistView(countBytes).setUint32(0, map.length, Endian.big);
    builder.add(countBytes);

    for (final entry in map.entries) {
      _writeV1QString(builder, entry.key);
      _writeV1QString(builder, entry.value);
    }
    return builder.toBytes();
  }

  static void _writeV1QString(BytesBuilder builder, String value) {
    final units = value.codeUnits;
    final byteLen = units.length * 2;
    final buf = Uint8List(4 + byteLen);
    final bd = ByteData.sublistView(buf);
    bd.setUint32(0, byteLen, Endian.big);
    for (int i = 0; i < units.length; i++) {
      bd.setUint16(4 + i * 2, units[i], Endian.big);
    }
    builder.add(buf);
  }

  /// Decodes a Qt `QDataStream` big-endian `QMap<QString, QString>` payload.
  static Map<String, String> decodeV1StringMap(Uint8List bytes) {
    if (bytes.length < 4) return const {};
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint32(0, Endian.big);
    if (count > 1024) return const {};

    int offset = 4;
    final result = <String, String>{};
    for (int i = 0; i < count; i++) {
      final keyPair = _readV1QString(bytes, bd, offset);
      if (keyPair == null) break;
      offset = keyPair.$2;

      final valPair = _readV1QString(bytes, bd, offset);
      if (valPair == null) break;
      offset = valPair.$2;

      result[keyPair.$1] = valPair.$1;
    }
    return result;
  }

  /// Decodes a Qt `QDataStream` big-endian `QList<QMap<QString, QVariant>>` payload
  /// emitted by `SerialPort::device_proactive_escalation_cmd_to_host` (`cmd = 13`).
  static List<Map<String, dynamic>> decodeV1ProactiveEscalationList(
    Uint8List bytes,
  ) {
    if (bytes.length < 4) return const [];
    final bd = ByteData.sublistView(bytes);
    final listCount = bd.getUint32(0, Endian.big);
    if (listCount > 256) return const [];

    int offset = 4;
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < listCount; i++) {
      if (offset + 4 > bytes.length) break;
      final mapCount = bd.getUint32(offset, Endian.big);
      offset += 4;
      if (mapCount > 256) break;

      final item = <String, dynamic>{};
      for (int j = 0; j < mapCount; j++) {
        final keyPair = _readV1QString(bytes, bd, offset);
        if (keyPair == null) return result;
        offset = keyPair.$2;

        final valPair = _readV1QVariant(bytes, bd, offset);
        if (valPair == null) return result;
        offset = valPair.$2;

        item[keyPair.$1] = valPair.$1;
      }
      result.add(item);
    }
    return result;
  }

  static (String, int)? _readV1QString(
    Uint8List bytes,
    ByteData bd,
    int offset,
  ) {
    if (offset + 4 > bytes.length) return null;
    final byteLen = bd.getUint32(offset, Endian.big);
    offset += 4;
    if (byteLen == 0xFFFFFFFF || byteLen == 0) {
      return ('', offset);
    }
    if ((byteLen & 1) != 0 || offset + byteLen > bytes.length) {
      return null;
    }
    final charCount = byteLen ~/ 2;
    final units = List<int>.generate(
      charCount,
      (idx) => bd.getUint16(offset + idx * 2, Endian.big),
      growable: false,
    );
    return (String.fromCharCodes(units), offset + byteLen);
  }

  static (dynamic, int)? _readV1QVariant(
    Uint8List bytes,
    ByteData bd,
    int offset,
  ) {
    if (offset + 5 > bytes.length) return null;
    final typeId = bd.getUint32(offset, Endian.big);
    final isNull = bd.getUint8(offset + 4) != 0;
    offset += 5;

    switch (typeId) {
      case 1: // QMetaType::Bool
        if (offset + 1 > bytes.length) return null;
        final v = bd.getUint8(offset) != 0;
        return (isNull ? false : v, offset + 1);
      case 2: // QMetaType::Int
      case 32: // QMetaType::Long
        if (offset + 4 > bytes.length) return null;
        final v = bd.getInt32(offset, Endian.big);
        return (isNull ? 0 : v, offset + 4);
      case 3: // QMetaType::UInt
      case 35: // QMetaType::ULong
        if (offset + 4 > bytes.length) return null;
        final v = bd.getUint32(offset, Endian.big);
        return (isNull ? 0 : v, offset + 4);
      case 6: // QMetaType::Double
        if (offset + 8 > bytes.length) return null;
        final v = bd.getFloat64(offset, Endian.big);
        return (isNull ? 0.0 : v, offset + 8);
      case 10: // QMetaType::QString
        return _readV1QString(bytes, bd, offset);
      case 33: // QMetaType::Short
        if (offset + 2 > bytes.length) return null;
        final v = bd.getInt16(offset, Endian.big);
        return (isNull ? 0 : v, offset + 2);
      case 36: // QMetaType::UShort
        if (offset + 2 > bytes.length) return null;
        final v = bd.getUint16(offset, Endian.big);
        return (isNull ? 0 : v, offset + 2);
      case 34: // QMetaType::Char
      case 37: // QMetaType::UChar
      case 40: // QMetaType::SChar
        if (offset + 1 > bytes.length) return null;
        final v = bd.getUint8(offset);
        return (isNull ? 0 : v, offset + 1);
      default:
        return null;
    }
  }
}

/// Stateful stream parser that accepts Protocol V2 (`A1 A5 5A 5E` / `5E 5A A5 A1`)
/// and Protocol V1 (`AA551234 FIXEDCMDHEAD `) magic headers, strips V1 abort ACK
/// prefixes, and performs two-stage CRC resynchronization.
class ProtocolV2StreamDecoder {
  static final List<int> _v1MagicCodeUnits =
      ProtocolV2Codec.v1FixedCmdHeader.codeUnits;

  final List<int> _buffer = <int>[];
  bool _abortAckReceived = false;
  int _sizeCrcResyncCount = 0;
  int _dataCrcResyncCount = 0;

  bool get abortAckReceived => _abortAckReceived;
  int get sizeCrcResyncCount => _sizeCrcResyncCount;
  int get dataCrcResyncCount => _dataCrcResyncCount;
  int get bufferedByteCount => _buffer.length;

  void reset() {
    _buffer.clear();
    _abortAckReceived = false;
  }

  /// Appends incoming chunk bytes and returns all complete, CRC-verified V2 or V1 packets.
  List<ProtocolV2Packet> addChunk(List<int> chunk) {
    if (chunk.isNotEmpty) {
      _buffer.addAll(chunk);
    }
    final packets = <ProtocolV2Packet>[];

    while (_buffer.isNotEmpty) {
      final (headerOffset, isV1Header) = _findNextHeader();
      if (headerOffset < 0) {
        _inspectPrefixAndTrim(
          _buffer.length > 64 ? _buffer.length - 36 : 0,
        );
        break;
      }

      if (headerOffset > 0) {
        _inspectPrefixAndTrim(headerOffset);
      }

      if (isV1Header) {
        if (_buffer.length < ProtocolV2Codec.v1HeaderSize) {
          break;
        }
        final headerBytes = Uint8List.fromList(
          _buffer.sublist(0, ProtocolV2Codec.v1HeaderSize),
        );
        final headerData = ByteData.sublistView(headerBytes);
        final v1Type = headerData.getUint32(22, Endian.little);
        final cmd = headerData.getUint32(26, Endian.little);
        final size = headerData.getUint32(30, Endian.little);
        final receivedCrc = headerData.getUint32(34, Endian.little);

        if (v1Type > 3 || cmd > 15 || size > ProtocolV2Codec.maxPayloadSize) {
          _buffer.removeRange(0, ProtocolV2Codec.v1MagicLength);
          _sizeCrcResyncCount++;
          continue;
        }

        final totalV1Size = ProtocolV2Codec.v1HeaderSize + size;
        if (_buffer.length < totalV1Size) {
          break;
        }

        final payload = Uint8List.fromList(
          _buffer.sublist(ProtocolV2Codec.v1HeaderSize, totalV1Size),
        );
        final expectedCrc = size == 0
            ? ProtocolV2Codec.emptyDataCrc32
            : ProtocolV2Codec.crc32(payload);

        if (size > 0 && receivedCrc != 0 && receivedCrc != expectedCrc) {
          _buffer.removeRange(0, ProtocolV2Codec.v1HeaderSize);
          _dataCrcResyncCount++;
          continue;
        }

        _buffer.removeRange(0, totalV1Size);
        packets.add(
          ProtocolV2Packet(
            id: -2,
            cmd: cmd,
            payload: payload,
            isV1: true,
            v1Type: v1Type,
          ),
        );
        continue;
      }

      // Need at least the 20-byte header to validate size and size_crc
      if (_buffer.length < ProtocolV2Codec.headerSize) {
        break;
      }

      final headerBytes = Uint8List.fromList(
        _buffer.sublist(0, ProtocolV2Codec.headerSize),
      );
      final headerData = ByteData.sublistView(headerBytes);
      final id = headerData.getInt32(4, Endian.little);
      final cmd = headerData.getUint32(8, Endian.little);
      final size = headerData.getUint32(12, Endian.little);
      final receivedSizeCrc = headerData.getUint32(16, Endian.little);

      final expectedSizeCrc = ProtocolV2Codec.crc32(
        Uint8List.sublistView(headerBytes, 12, 16),
      );

      // Stage 1: Verify size_crc and size <= 16 MB BEFORE waiting for payload
      final isCmdValid =
          cmd == ProtocolV2Codec.cmdShowJpg || cmd == ProtocolV2Codec.cmdJson;
      if (!isCmdValid ||
          size > ProtocolV2Codec.maxPayloadSize ||
          receivedSizeCrc != expectedSizeCrc) {
        // Drop only 4 bytes (false magic header) and rescan
        _buffer.removeRange(0, 4);
        _sizeCrcResyncCount++;
        continue;
      }

      final totalPacketSize = ProtocolV2Codec.envelopeOverhead + size;
      if (_buffer.length < totalPacketSize) {
        // Wait for remaining payload + 4-byte data_crc trailer
        break;
      }

      final payload = Uint8List.fromList(
        _buffer.sublist(
          ProtocolV2Codec.headerSize,
          ProtocolV2Codec.headerSize + size,
        ),
      );
      final trailerBytes = Uint8List.fromList(
        _buffer.sublist(
          ProtocolV2Codec.headerSize + size,
          totalPacketSize,
        ),
      );
      final receivedDataCrc = ByteData.sublistView(
        trailerBytes,
      ).getUint32(0, Endian.little);
      final expectedDataCrc = size == 0
          ? ProtocolV2Codec.emptyDataCrc32
          : ProtocolV2Codec.crc32(payload);

      // Stage 2: If data_crc fails after size bytes arrive, drop only 24 bytes
      // so any valid header inside the payload buffer is not lost.
      if (receivedDataCrc != expectedDataCrc) {
        final dropLen = _buffer.length >= ProtocolV2Codec.envelopeOverhead
            ? ProtocolV2Codec.envelopeOverhead
            : _buffer.length;
        _buffer.removeRange(0, dropLen);
        _dataCrcResyncCount++;
        continue;
      }

      _buffer.removeRange(0, totalPacketSize);
      packets.add(ProtocolV2Packet(id: id, cmd: cmd, payload: payload));
    }

    return packets;
  }

  (int, bool) _findNextHeader() {
    final v2Limit = _buffer.length - 4;
    final v1Limit = _buffer.length - ProtocolV2Codec.v1MagicLength;
    for (int i = 0; i <= v2Limit; i++) {
      final b0 = _buffer[i];
      final b1 = _buffer[i + 1];
      final b2 = _buffer[i + 2];
      final b3 = _buffer[i + 3];
      // Accept both A1 A5 5A 5E and 5E 5A A5 A1
      if ((b0 == 0xA1 && b1 == 0xA5 && b2 == 0x5A && b3 == 0x5E) ||
          (b0 == 0x5E && b1 == 0x5A && b2 == 0xA5 && b3 == 0xA1)) {
        return (i, false);
      }
      if (i <= v1Limit && b0 == 0x41 && b1 == 0x41 && b2 == 0x35 && b3 == 0x35) {
        bool match = true;
        for (int j = 4; j < ProtocolV2Codec.v1MagicLength; j++) {
          if (_buffer[i + j] != _v1MagicCodeUnits[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          return (i, true);
        }
      }
    }
    return (-1, false);
  }

  void _inspectPrefixAndTrim(int count) {
    if (count <= 0) return;
    final prefix = _buffer.sublist(0, count);
    final text = latin1.decode(prefix, allowInvalid: true);
    if (text.contains(ProtocolV2Codec.v1AbortAck) ||
        text.contains('Abort file transfer')) {
      _abortAckReceived = true;
    }
    _buffer.removeRange(0, count);
  }
}
