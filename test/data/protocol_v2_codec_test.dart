import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/data/services/protocol_v2_codec.dart';

void main() {
  group('ProtocolV2Codec & StreamDecoder', () {
    test('computes IEEE 802.3 CRC32 vectors accurately', () {
      // Empty payload CRC32 == 0x00000000
      expect(ProtocolV2Codec.crc32(const []), equals(0x00000000));
      // 4 zero bytes (size == 0) CRC32 == 0x2144DF1C
      expect(ProtocolV2Codec.computeSizeCrc32(0), equals(0x2144DF1C));
      // Standard ASCII '123456789' check value == 0xCBF43926
      expect(
        ProtocolV2Codec.crc32(ascii.encode('123456789')),
        equals(0xCBF43926),
      );
    });

    test('encodes 37-byte V1 abort command', () {
      final abortBytes = ProtocolV2Codec.encodeV1AbortCommand();
      expect(abortBytes.length, equals(37));
      expect(
        ascii.decode(abortBytes),
        equals('AA551234 Abort file transfer 123455AA'),
      );
    });

    test('strips V1 abort ACK prefix and decodes both A1A55A5E and 5E5AA5A1 magic headers', () {
      final decoder = ProtocolV2StreamDecoder();

      final prefix = ascii.encode('junk AA551234 Abort file transfer ok\r\n');
      final pkt1 = ProtocolV2Codec.encodeJsonRequest(
        id: 1,
        method: 'getInfo',
      );
      final pkt2 = ProtocolV2Codec.encodePacket(
        id: 2,
        cmd: ProtocolV2Codec.cmdShowJpg,
        payload: const [],
        littleEndianMagic: true, // 5E 5A A5 A1
      );

      final combined = Uint8List.fromList([...prefix, ...pkt1, ...pkt2]);
      // Feed in small fragmented chunks to test stream reassembly
      final decoded = <ProtocolV2Packet>[];
      for (int i = 0; i < combined.length; i += 7) {
        final end = (i + 7 < combined.length) ? i + 7 : combined.length;
        decoded.addAll(decoder.addChunk(combined.sublist(i, end)));
      }

      expect(decoder.abortAckReceived, isTrue);
      expect(decoded.length, equals(2));
      expect(decoded[0].id, equals(1));
      expect(decoded[0].isJson, isTrue);
      expect(decoded[0].decodeJson()?['method'], equals('getInfo'));

      expect(decoded[1].id, equals(2));
      expect(decoded[1].isShowJpg, isTrue);
      expect(decoded[1].payload, isEmpty);
    });

    test('performs two-stage resynchronization on corrupted size_crc and data_crc', () {
      final decoder = ProtocolV2StreamDecoder();

      // Stage 1 corruption: false magic header followed by huge/invalid size_crc
      final corruptedSizeHeader = Uint8List.fromList([
        0xA1, 0xA5, 0x5A, 0x5E, // magic
        0x01, 0x00, 0x00, 0x00, // id = 1
        0x65, 0x00, 0x00, 0x00, // cmd = 101
        0xFF, 0xFF, 0xFF, 0x7F, // huge size
        0xDE, 0xAD, 0xBE, 0xEF, // invalid size_crc
      ]);

      final validPacket = ProtocolV2Codec.encodeJsonRequest(
        id: 42,
        method: 'stopAudio',
      );

      // Stage 2 corruption: valid header + size_crc, but corrupted payload byte inside which
      // a valid packet follows immediately after the 24-byte header
      final badDataPacket = Uint8List.fromList(
        ProtocolV2Codec.encodeJsonRequest(id: 99, method: 'getInfo'),
      );
      // Corrupt the last trailer byte (data_crc)
      badDataPacket[badDataPacket.length - 1] ^= 0xFF;

      final streamBytes = Uint8List.fromList([
        ...corruptedSizeHeader,
        ...validPacket,
        ...badDataPacket,
        ...validPacket,
      ]);

      final packets = decoder.addChunk(streamBytes);
      expect(decoder.sizeCrcResyncCount, greaterThanOrEqualTo(1));
      expect(decoder.dataCrcResyncCount, greaterThanOrEqualTo(1));
      expect(packets.length, equals(2));
      expect(packets[0].id, equals(42));
      expect(packets[1].id, equals(42));
    });
  });
}
