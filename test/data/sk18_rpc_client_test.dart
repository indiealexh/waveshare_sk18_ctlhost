import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/data/repositories/device_repository.dart';
import 'package:wavectl_host/data/services/jpeg_frame_streamer.dart';
import 'package:wavectl_host/data/services/protocol_v2_codec.dart';
import 'package:wavectl_host/data/services/serial_transport_service.dart';
import 'package:wavectl_host/data/services/sk18_rpc_client.dart';
import 'package:wavectl_host/domain/models/sk18_geometry.dart';
import 'package:wavectl_host/domain/models/sk18_profile.dart';

class _SilentHardwareTransport implements Sk18Transport {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  final List<Uint8List> writtenChunks = <Uint8List>[];
  void Function(Uint8List bytes)? onWrite;
  bool _connected = false;
  String _path = '';

  @override
  Stream<Uint8List> get incomingBytes => _controller.stream;

  @override
  bool get isConnected => _connected;

  @override
  bool get isSimulator => false;

  @override
  String get activePortPath => _path;

  @override
  Future<void> connect(String portPath) async {
    _connected = true;
    _path = portPath;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _path = '';
  }

  @override
  Future<void> writeBytes(Uint8List bytes) async {
    writtenChunks.add(Uint8List.fromList(bytes));
    onWrite?.call(bytes);
  }

  void emitPacket(Uint8List bytes) {
    _controller.add(bytes);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  group('Sk18RpcClient, Simulator & JpegFrameStreamer', () {
    late SimulatorSerialTransport simulator;
    late Sk18RpcClient client;
    late JpegFrameStreamer streamer;

    setUp(() {
      simulator = SimulatorSerialTransport(simulatePortraitScanout: true);
      client = Sk18RpcClient(transport: simulator);
      streamer = JpegFrameStreamer(
        rpcClient: client,
        ackWatchdogDuration: const Duration(milliseconds: 80),
        useBackgroundIsolate: false,
      );
    });

    tearDown(() {
      streamer.dispose();
      client.dispose();
      simulator.dispose();
    });

    test('normalizes macOS /dev/tty.usbmodem* paths to /dev/cu.usbmodem*', () {
      expect(
        SerialPortDiscovery.normalizeDevicePath('/dev/tty.usbmodem1101'),
        equals('/dev/cu.usbmodem1101'),
      );
      expect(
        SerialPortDiscovery.normalizeDevicePath('/dev/cu.usbmodem1101'),
        equals('/dev/cu.usbmodem1101'),
      );
    });

    test('completes V1 abort -> V2 getInfo handshake and executes stock V2 RPCs', () async {
      final info = await client.connectAndHandshake(
        SerialPortDiscovery.simulatorPortUri,
      );
      expect(info.deviceModel, equals('SK18'));
      expect(info.isPortrait, isTrue);
      expect(info.rects.length, equals(18));

      await client.setBacklight(92);
      expect(simulator.simulatedBacklight, equals(92));

      await client.setVolume(6);
      expect(simulator.simulatedVolume, equals(6));

      await client.keyboardInput('git status');
      expect(simulator.typedStrings, contains('git status'));

      await client.playAudio('/data/sound/click.wav');
      expect(simulator.lastPlayedAudioPath, equals('/data/sound/click.wav'));
      expect(simulator.isAudioPlaying, isTrue);

      await client.stopAudio();
      expect(simulator.isAudioPlaying, isFalse);
    });

    test('uploads multi-chunk WAV file (saveToFile + setFileCRC) and lists via getFilesBySuffix', () async {
      await client.connectAndHandshake(SerialPortDiscovery.simulatorPortUri);

      // 140 KB payload -> 3 chunks of 64 KB (65536 + 65536 + 8928)
      final wavPayload = Uint8List.fromList(
        List<int>.generate(140000, (i) => i & 0xFF),
      );
      final expectedCrc = ProtocolV2Codec.crc32(wavPayload).toString();

      final progressSteps = <double>[];
      final uploadPausedStates = <bool>[];
      final sub = client.uploadStateChanges.listen(uploadPausedStates.add);

      final returnedCrc = await client.uploadWavFile(
        remoteFilePath: '/data/sound/custom_alert.wav',
        wavBytes: wavPayload,
        onProgress: progressSteps.add,
      );

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(returnedCrc, equals(expectedCrc));
      expect(progressSteps.length, equals(3));
      expect(progressSteps.last, closeTo(1.0, 0.001));
      expect(uploadPausedStates, containsAllInOrder([true, false]));

      final files = await client.getWavFiles();
      final uploaded = files.firstWhere(
        (f) => f.filePath == '/data/sound/custom_alert.wav',
      );
      expect(uploaded.crc, equals(expectedCrc));

      final deleted = await client.deleteFiles(['/data/sound/custom_alert.wav']);
      expect(deleted, contains('/data/sound/custom_alert.wav'));
    });

    test('gates CMD_VALUE_SHOW_JPG frames on ACK and recovers via watchdog timer', () async {
      await client.connectAndHandshake(SerialPortDiscovery.simulatorPortUri);

      final dummyJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
      final sentFirst = await streamer.sendEncodedJpegIfReady(dummyJpeg);
      expect(sentFirst, isTrue);
      // Wait microtask for simulator ACK
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(streamer.waitingForFrameAck, isFalse);

      // Now simulate a dropped ACK and verify the watchdog recovers
      simulator.dropFrameAcks = true;
      final sentSecond = await streamer.sendEncodedJpegIfReady(dummyJpeg);
      expect(sentSecond, isTrue);
      expect(streamer.waitingForFrameAck, isTrue);

      // Attempting to send while waiting for ACK should be gated
      final gatedAttempt = await streamer.sendEncodedJpegIfReady(dummyJpeg);
      expect(gatedAttempt, isFalse);

      // Wait for the 80ms watchdog timer to clear waitingForFrameAck
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(streamer.waitingForFrameAck, isFalse);
      expect(streamer.watchdogRecoveryCount, equals(1));
    });

    test('falls back to backlight/volume sync when stock V2.32 firmware rejects setLayoutConfig', () async {
      final repo = DeviceRepository(
        simulatorTransport: simulator,
        useBackgroundJpegIsolate: false,
      );
      addTearDown(repo.dispose);

      await repo.connect(SerialPortDiscovery.simulatorPortUri);
      simulator.simulateStockV232Only = true;

      final profile = Sk18Profile.createDefault().copyWith(
        backlight: 73,
        volume: 4,
      );

      final usedCustomRpc = await repo.syncProfileToFirmware(profile);
      expect(usedCustomRpc, isFalse);
      expect(simulator.simulatedBacklight, equals(73));
      expect(simulator.simulatedVolume, equals(4));
    });

    test('connects to simulator://mk10 and returns MK10 getInfo with status rect and 10 key rects', () async {
      final ports = await SerialPortDiscovery.discoverPorts();
      expect(ports, contains(SerialPortDiscovery.simulatorPortUri));
      expect(ports, contains(SerialPortDiscovery.mk10SimulatorPortUri));

      final info = await client.connectAndHandshake(
        SerialPortDiscovery.mk10SimulatorPortUri,
      );
      expect(info.deviceModel, equals('MK10'));
      expect(info.model, equals(WaveshareModel.mk10));
      expect(info.isPortrait, isTrue);
      expect(info.deviceWidth, equals(304));
      expect(info.deviceHeight, equals(896));
      expect(info.rectRows, equals(5));
      expect(info.rectCols, equals(2));
      expect(info.rects.length, equals(11)); // 1 status rect + 10 key rects
      expect(info.rects.first.isKey, isFalse);
      expect(info.rects.where((r) => r.isKey).length, equals(10));
    });

    test('disconnects transport cleanly when connectAndHandshake times out', () async {
      final silentTransport = _SilentHardwareTransport();
      addTearDown(silentTransport.dispose);
      final fastTimeoutClient = Sk18RpcClient(
        transport: silentTransport,
        requestTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(fastTimeoutClient.dispose);

      await expectLater(
        fastTimeoutClient.connectAndHandshake('/dev/cu.usbmodem1101'),
        throwsA(isA<TimeoutException>()),
      );
      expect(silentTransport.isConnected, isFalse);
      expect(fastTimeoutClient.isConnected, isFalse);
    });

    test('correlates id=-1 firmware error packets via requestId or pending queue', () async {
      final silentTransport = _SilentHardwareTransport();
      addTearDown(silentTransport.dispose);
      final rpc = Sk18RpcClient(
        transport: silentTransport,
        requestTimeout: const Duration(milliseconds: 500),
      );
      addTearDown(rpc.dispose);

      await silentTransport.connect('/dev/cu.usbmodem1101');
      final future = rpc.setLayoutConfig({'version': 1});

      final errPayload = utf8.encode(
        jsonEncode({
          'errorString': 'Unknown method: setLayoutConfig',
          'method': 'setLayoutConfig',
          'requestId': 1,
        }),
      );
      silentTransport.emitPacket(
        ProtocolV2Codec.encodePacket(
          id: -1,
          cmd: ProtocolV2Codec.cmdJson,
          payload: errPayload,
        ),
      );

      await expectLater(
        future,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Unknown method: setLayoutConfig'),
          ),
        ),
      );
    });

    test('gates isConnected and JpegFrameStreamer while connectAndHandshake is in flight', () async {
      final silentTransport = _SilentHardwareTransport();
      addTearDown(silentTransport.dispose);
      final rpc = Sk18RpcClient(
        transport: silentTransport,
        requestTimeout: const Duration(milliseconds: 120),
      );
      addTearDown(rpc.dispose);
      final gatedStreamer = JpegFrameStreamer(
        rpcClient: rpc,
        useBackgroundIsolate: false,
      );
      addTearDown(gatedStreamer.dispose);

      final handshakeFuture = rpc.connectAndHandshake('/dev/cu.usbmodem1101');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Transport is open, but handshake has not completed yet
      expect(silentTransport.isConnected, isTrue);
      expect(rpc.isConnected, isFalse);

      final sentMidHandshake = await gatedStreamer.sendEncodedJpegIfReady(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
      );
      expect(sentMidHandshake, isFalse);
      expect(gatedStreamer.framesSentCount, equals(0));

      await expectLater(handshakeFuture, throwsA(isA<TimeoutException>()));
      expect(rpc.isConnected, isFalse);
    });

    test('falls back to Protocol V1 for MK10 V2.29 hardware and decodes V1 keyStateChanged', () async {
      final v1Transport = _SilentHardwareTransport();
      addTearDown(v1Transport.dispose);

      v1Transport.onWrite = (bytes) {
        final packets = ProtocolV2StreamDecoder().addChunk(bytes);
        for (final pkt in packets) {
          if (pkt.isV1 && pkt.cmd == ProtocolV2Codec.v1CmdFindDevice) {
            final mapPayload = ProtocolV2Codec.encodeV1StringMap({
              'screen_model': 'MK10',
              'version': 'V2.29',
              'deviceBl': '50',
              'deviceVolume': '7',
              'deviceName': 'ScreenKey',
            });
            scheduleMicrotask(() {
              v1Transport.emitPacket(
                ProtocolV2Codec.encodeV1Packet(
                  type: ProtocolV2Codec.v1TypeData,
                  cmd: ProtocolV2Codec.v1CmdFindDevice,
                  payload: mapPayload,
                ),
              );
            });
          } else if (pkt.isV1 && pkt.cmd == ProtocolV2Codec.v1CmdSetBacklight) {
            scheduleMicrotask(() {
              v1Transport.emitPacket(
                ProtocolV2Codec.encodeV1Packet(
                  type: ProtocolV2Codec.v1TypeData,
                  cmd: ProtocolV2Codec.v1CmdSetBacklight,
                  payload: pkt.payload,
                ),
              );
            });
          }
        }
      };

      final rpc = Sk18RpcClient(
        transport: v1Transport,
        requestTimeout: const Duration(milliseconds: 600),
      );
      addTearDown(rpc.dispose);

      final info = await rpc.connectAndHandshake('/dev/cu.usbmodem1101');
      expect(rpc.isConnected, isTrue);
      expect(rpc.isV1Protocol, isTrue);
      expect(info.deviceModel, equals('MK10'));
      expect(info.deviceVersion, equals('V2.29'));
      expect(info.model, equals(WaveshareModel.mk10));

      await rpc.setBacklight(80);
      await rpc.keyboardInput('hello');

      // Emit a Protocol V1 cmd=13 keyState escalation packet (row=2, col=1, pressed=true)
      final escalationPayload = BytesBuilder();
      // List count = 1, Map count = 4
      escalationPayload.add([0, 0, 0, 1, 0, 0, 0, 4]);
      void writeKey(String k) {
        final units = k.codeUnits;
        final bd = ByteData(4 + units.length * 2);
        bd.setUint32(0, units.length * 2, Endian.big);
        for (int i = 0; i < units.length; i++) {
          bd.setUint16(4 + i * 2, units[i], Endian.big);
        }
        escalationPayload.add(bd.buffer.asUint8List());
      }

      // 1. col = 1 (QMetaType::Int = 2)
      writeKey('col');
      escalationPayload.add([0, 0, 0, 2, 0, 0, 0, 0, 1]);
      // 2. pressed = true (QMetaType::Bool = 1)
      writeKey('pressed');
      escalationPayload.add([0, 0, 0, 1, 0, 1]);
      // 3. row = 2 (QMetaType::Int = 2)
      writeKey('row');
      escalationPayload.add([0, 0, 0, 2, 0, 0, 0, 0, 2]);
      // 4. type = "keyState" (QMetaType::QString = 10)
      writeKey('type');
      escalationPayload.add([0, 0, 0, 10, 0]);
      writeKey('keyState');

      final eventFuture = rpc.deviceEvents.first;
      v1Transport.emitPacket(
        ProtocolV2Codec.encodeV1Packet(
          type: ProtocolV2Codec.v1TypeData,
          cmd: ProtocolV2Codec.v1CmdProactiveEscalation,
          payload: escalationPayload.toBytes(),
        ),
      );

      final event = await eventFuture;
      expect(event.method, equals('keyStateChanged'));
      expect(event.parameters['col'], equals(1));
      expect(event.parameters['row'], equals(2));
      expect(event.parameters['pressed'], isTrue);
    });
  });
}
