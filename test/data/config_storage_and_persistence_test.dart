// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavectl_host/data/repositories/device_repository.dart';
import 'package:wavectl_host/data/repositories/home_assistant_repository.dart';
import 'package:wavectl_host/data/repositories/profile_repository.dart';
import 'package:wavectl_host/data/services/config_storage_service.dart';
import 'package:wavectl_host/data/services/host_launcher_service.dart';
import 'package:wavectl_host/data/services/serial_transport_service.dart';
import 'package:wavectl_host/domain/models/button_action.dart';
import 'package:wavectl_host/domain/use_cases/action_executor_use_case.dart';
import 'package:wavectl_host/ui/features/studio/view_models/studio_view_model.dart';

class _TestDeviceRepository extends DeviceRepository {
  final List<String> _discoveredPorts;

  _TestDeviceRepository({
    required List<String> discoveredPorts,
  }) : _discoveredPorts = discoveredPorts,
       super(useBackgroundJpegIsolate: false);

  @override
  List<String> get availablePorts => List.unmodifiable(_discoveredPorts);

  @override
  Future<List<String>> refreshPorts() async => availablePorts;
}

void main() {
  group('ConfigStorageService', () {
    test('resolves OS config file paths across macOS, Linux, and Windows', () {
      const macService = ConfigStorageService(
        operatingSystemOverride: 'macos',
        environmentOverride: {'HOME': '/Users/alice'},
      );
      expect(
        macService.resolveConfigFilePath(),
        equals(
          '/Users/alice/Library/Application Support/wavectl_host/studio_config.json',
        ),
      );

      const linuxXdgService = ConfigStorageService(
        operatingSystemOverride: 'linux',
        environmentOverride: {
          'HOME': '/home/alice',
          'XDG_CONFIG_HOME': '/home/alice/.custom_cfg',
        },
      );
      expect(
        linuxXdgService.resolveConfigFilePath(),
        equals('/home/alice/.custom_cfg/wavectl_host/studio_config.json'),
      );

      const linuxFallbackService = ConfigStorageService(
        operatingSystemOverride: 'linux',
        environmentOverride: {'HOME': '/home/alice'},
      );
      expect(
        linuxFallbackService.resolveConfigFilePath(),
        equals('/home/alice/.config/wavectl_host/studio_config.json'),
      );

      const windowsService = ConfigStorageService(
        operatingSystemOverride: 'windows',
        environmentOverride: {'APPDATA': r'C:\Users\Alice\AppData\Roaming'},
      );
      expect(
        windowsService.resolveConfigFilePath(),
        equals(
          r'C:\Users\Alice\AppData\Roaming\wavectl_host\studio_config.json',
        ),
      );

      const overrideService = ConfigStorageService(
        configFilePath: '/tmp/custom/studio_config.json',
      );
      expect(
        overrideService.resolveConfigFilePath(),
        equals('/tmp/custom/studio_config.json'),
      );
    });

    test('atomically writes and reads JSON and handles missing or malformed files', () async {
      final tempDir = await Directory.systemTemp.createTemp('wavectl_cfg_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final configPath = p.join(tempDir.path, 'nested', 'studio_config.json');
      final service = ConfigStorageService(configFilePath: configPath);

      // Missing file returns null
      expect(await service.readConfigJson(), isNull);

      // Atomic write creates parent directories and removes temporary sibling
      await service.writeConfigJson({'version': 1, 'selectedPort': 'simulator://sk18'});
      expect(await File(configPath).exists(), isTrue);
      expect(await File('$configPath.tmp').exists(), isFalse);

      final loaded = await service.readConfigJson();
      expect(loaded, isNotNull);
      expect(loaded!['selectedPort'], equals('simulator://sk18'));

      // Malformed JSON returns null instead of throwing
      await File(configPath).writeAsString('{broken_json:');
      expect(await service.readConfigJson(), isNull);
    });
  });

  group('ProfileRepository & StudioViewModel Persistence', () {
    late Directory tempDir;
    late String configPath;
    late ConfigStorageService storageService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wavectl_repo_test_');
      configPath = p.join(tempDir.path, 'studio_config.json');
      storageService = ConfigStorageService(configFilePath: configPath);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('debounced auto-save persists full studio state and restores on next launch', () async {
      final repo1 = ProfileRepository(
        storageService: storageService,
        autoSaveDebounce: const Duration(milliseconds: 25),
      );

      // Customize first profile and add a page
      repo1.updateKeyConfig(
        0,
        repo1.activePage.keys[0].copyWith(
          label: 'Custom Key 1',
          iconName: 'bolt',
          colorHex: 0xFFEC4899,
          action: const ButtonAction(
            category: ActionCategory.hostLauncher,
            launcherType: HostLauncherType.script,
            target: 'echo persistent',
          ),
        ),
      );
      repo1.updateActiveProfile(
        repo1.activeProfile.copyWith(
          landscapeMode: false,
          upsideDown: true,
          backlight: 42,
          volume: 3,
          offsetX: -8,
          offsetY: 14,
        ),
      );
      repo1.addPage('Streaming Controls');
      repo1.setSelectedPort('simulator://custom-unit');
      repo1.setInteractiveTriggerOnTap(true);

      // Create a second profile and switch back to the first profile, page 2
      repo1.createProfile('Gaming Profile');
      repo1.selectProfile(0);
      repo1.selectPage(2);

      // Wait for debounce timer to flush to disk
      await Future<void>.delayed(const Duration(milliseconds: 80));
      repo1.dispose();

      expect(await File(configPath).exists(), isTrue);

      // Launch a new repository & StudioViewModel backed by the same storage
      final repo2 = ProfileRepository(storageService: storageService);
      final deviceRepo2 = _TestDeviceRepository(
        discoveredPorts: const [
          SerialPortDiscovery.simulatorPortUri,
          'simulator://custom-unit',
        ],
      );
      final haRepo2 = HomeAssistantRepository();
      final executor2 = ActionExecutorUseCase(
        deviceRepository: deviceRepo2,
        homeAssistantRepository: haRepo2,
        hostLauncherService: HostLauncherService(dryRun: true),
      );
      final vm2 = StudioViewModel(
        profileRepository: repo2,
        deviceRepository: deviceRepo2,
        homeAssistantRepository: haRepo2,
        actionExecutor: executor2,
        startClockTimer: false,
      );

      await vm2.initialize(
        autoConnectSimulator: true,
        envFilePath: '/non/existent/.env',
      );

      expect(vm2.profiles.length, equals(2));
      expect(vm2.profiles[1].name, equals('Gaming Profile'));
      expect(vm2.activeProfileIndex, equals(0));
      expect(vm2.activePageIndex, equals(2));
      expect(vm2.activePage.name, equals('Streaming Controls'));
      expect(vm2.activeProfile.landscapeMode, isFalse);
      expect(vm2.activeProfile.upsideDown, isTrue);
      expect(vm2.activeProfile.backlight, equals(42));
      expect(vm2.activeProfile.volume, equals(3));
      expect(vm2.activeProfile.offsetX, equals(-8));
      expect(vm2.activeProfile.offsetY, equals(14));
      expect(vm2.interactiveTriggerOnTap, isTrue);
      expect(vm2.selectedPort, equals('simulator://custom-unit'));
      expect(deviceRepo2.activePortPath, equals('simulator://custom-unit'));

      vm2.selectPage(0);
      expect(vm2.activePage.keys[0].label, equals('Custom Key 1'));
      expect(vm2.activePage.keys[0].iconName, equals('bolt'));
      expect(vm2.activePage.keys[0].colorHex, equals(0xFFEC4899));
      expect(
        vm2.activePage.keys[0].action.target,
        equals('echo persistent'),
      );

      vm2.dispose();
      haRepo2.dispose();
      deviceRepo2.dispose();
    });

    test('falls back to simulator when saved physical port is unplugged and supports single-profile sk18_config.json', () async {
      // Write a single-profile sk18_config.json with an unplugged physical port
      final singleProfileRepo = ProfileRepository();
      final singleProfileMap = singleProfileRepo.activeProfile.toSk18ConfigJson(
        pageIndex: 1,
      );
      singleProfileMap['profileName'] = 'Imported Single Profile';
      singleProfileMap['selectedPort'] = '/dev/cu.usbmodem_unplugged';
      await storageService.writeConfigJson(singleProfileMap);

      final repo = ProfileRepository(storageService: storageService);
      final deviceRepo = _TestDeviceRepository(
        discoveredPorts: const [SerialPortDiscovery.simulatorPortUri],
      );
      final haRepo = HomeAssistantRepository();
      final executor = ActionExecutorUseCase(
        deviceRepository: deviceRepo,
        homeAssistantRepository: haRepo,
        hostLauncherService: HostLauncherService(dryRun: true),
      );
      final vm = StudioViewModel(
        profileRepository: repo,
        deviceRepository: deviceRepo,
        homeAssistantRepository: haRepo,
        actionExecutor: executor,
        startClockTimer: false,
      );

      await vm.initialize(
        autoConnectSimulator: true,
        envFilePath: '/non/existent/.env',
      );

      expect(vm.activeProfile.name, equals('Imported Single Profile'));
      expect(vm.activePageIndex, equals(1));
      expect(vm.isDeviceConnected, isTrue);
      expect(vm.selectedPort, equals(SerialPortDiscovery.simulatorPortUri));

      vm.dispose();
      haRepo.dispose();
      deviceRepo.dispose();
    });
  });
}
