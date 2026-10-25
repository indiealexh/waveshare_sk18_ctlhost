import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/data/repositories/device_repository.dart';
import 'package:wavectl_host/data/services/jpeg_frame_streamer.dart';
import 'package:wavectl_host/data/services/protocol_v2_codec.dart';
import 'package:wavectl_host/data/services/serial_transport_service.dart';
import 'package:wavectl_host/data/services/sk18_rpc_client.dart';
import 'package:wavectl_host/domain/models/sk18_profile.dart';

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
  });
}
