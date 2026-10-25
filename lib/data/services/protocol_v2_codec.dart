import 'dart:convert';
import 'dart:typed_data';

class ProtocolV2Packet {
  final int id;
  final int cmd;
  final Uint8List payload;

  const ProtocolV2Packet({
    required this.id,
    required this.cmd,
    required this.payload,
  });

  bool get isShowJpg => cmd == ProtocolV2Codec.cmdShowJpg;
  bool get isJson => cmd == ProtocolV2Codec.cmdJson;

  Map<String, dynamic>? decodeJson() {
    if (payload.isEmpty) return null;
    final text = utf8.decode(payload, allowMalformed: true);
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }
}

/// Implements the Waveshare SK18 Protocol V2 binary packet framing,
/// IEEE 802.3 CRC32 calculation, 37-byte V1 abort handshake, and two-stage
/// stream resynchronization.
class ProtocolV2Codec {
  /// 37-byte ASCII abort sequence that exits any stale Protocol V1 transfer immediately.
  static const String v1AbortCommand = 'AA551234 Abort file transfer 123455AA';
  static const String v1AbortAck = 'AA551234 Abort file transfer ok';

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
}

/// Stateful stream parser that accepts both `A1 A5 5A 5E` and `5E 5A A5 A1`
/// magic headers, strips V1 abort ACK prefixes, and performs two-stage CRC
/// resynchronization.
class ProtocolV2StreamDecoder {
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

  /// Appends incoming chunk bytes and returns all complete, CRC-verified V2 packets.
  List<ProtocolV2Packet> addChunk(List<int> chunk) {
    if (chunk.isNotEmpty) {
      _buffer.addAll(chunk);
    }
    final packets = <ProtocolV2Packet>[];

    while (_buffer.isNotEmpty) {
      final headerOffset = _findNextHeaderOffset();
      if (headerOffset < 0) {
        _inspectPrefixAndTrim(
          _buffer.length > 64 ? _buffer.length - 36 : 0,
        );
        break;
      }

      if (headerOffset > 0) {
        _inspectPrefixAndTrim(headerOffset);
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

  int _findNextHeaderOffset() {
    final limit = _buffer.length - 4;
    for (int i = 0; i <= limit; i++) {
      final b0 = _buffer[i];
      final b1 = _buffer[i + 1];
      final b2 = _buffer[i + 2];
      final b3 = _buffer[i + 3];
      // Accept both A1 A5 5A 5E and 5E 5A A5 A1
      if ((b0 == 0xA1 && b1 == 0xA5 && b2 == 0x5A && b3 == 0x5E) ||
          (b0 == 0x5E && b1 == 0x5A && b2 == 0xA5 && b3 == 0xA1)) {
        return i;
      }
    }
    return -1;
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
