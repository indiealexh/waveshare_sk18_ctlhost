import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/features/device/data/device_repository.dart';
import 'package:wavectl_host/features/home_assistant/data/home_assistant_repository.dart';
import 'package:wavectl_host/features/actions/data/host_launcher_service.dart';
import 'package:wavectl_host/core/protocol/serial_transport_service.dart';
import 'package:wavectl_host/features/actions/domain/button_action.dart';
import 'package:wavectl_host/features/profiles/domain/sk18_profile.dart';
import 'package:wavectl_host/features/actions/domain/action_executor_use_case.dart';

void main() {
  group('ActionExecutorUseCase Hybrid Router', () {
    late DeviceRepository deviceRepo;
    late HomeAssistantRepository haRepo;
    late HostLauncherService launcherService;
    late ActionExecutorUseCase executor;

    setUp(() async {
      deviceRepo = DeviceRepository(useBackgroundJpegIsolate: false);
      await deviceRepo.connect(SerialPortDiscovery.simulatorPortUri);
      haRepo = HomeAssistantRepository();
      launcherService = HostLauncherService(dryRun: true);
      executor = ActionExecutorUseCase(
        deviceRepository: deviceRepo,
        homeAssistantRepository: haRepo,
        hostLauncherService: launcherService,
      );
    });

    tearDown(() {
      haRepo.dispose();
      deviceRepo.dispose();
    });

    test('executes all four button action categories and updates telemetry', () async {
      final profile = Sk18Profile.createDefault();
      final keys = profile.pages.first.keys;

      // 1. Home Assistant Toggle (Key 0: light.office_main starts ON -> toggles OFF)
      final haLog = await executor.executeKeyAction(keys[0]);
      expect(haLog.success, isTrue);
      expect(haRepo.entities['light.office_main']?.state, equals('off'));

      // 2. Host Launcher App (Key 6: Terminal)
      final hostLog = await executor.executeKeyAction(keys[6]);
      expect(hostLog.success, isTrue);
      expect(launcherService.history.length, equals(1));
      expect(launcherService.history.first.target, equals('Terminal'));
      expect(
        launcherService.history.first.launcherType,
        equals(HostLauncherType.app),
      );

      // 3. Macro Sequence (Key 11: flutter test + 50ms + ENTER)
      final macroLog = await executor.executeKeyAction(keys[11]);
      expect(macroLog.success, isTrue);
      expect(
        deviceRepo.simulatorTransport.typedStrings,
        containsAll(['flutter test', '<ENTER>']),
      );

      // 4. On-Device WAV Audio (Key 12: /data/sound/click.wav)
      final audioLog = await executor.executeKeyAction(keys[12]);
      expect(audioLog.success, isTrue);
      expect(
        deviceRepo.simulatorTransport.lastPlayedAudioPath,
        equals('/data/sound/click.wav'),
      );
    });

    test('handles unsolicited firmware macroTriggered event', () async {
      final log = await executor.handleFirmwareMacroTriggered({
        'index': 7,
        'col': 1,
        'row': 1,
        'label': 'Open Kitty',
        'launcherType': 'script',
        'target': 'echo hello',
        'args': ['world'],
      });

      expect(log.success, isTrue);
      expect(launcherService.history.last.launcherType, equals(HostLauncherType.script));
      expect(launcherService.history.last.target, equals('echo hello'));
    });
  });
}
