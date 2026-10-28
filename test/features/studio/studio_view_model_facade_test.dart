import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/features/actions/data/host_launcher_service.dart';
import 'package:wavectl_host/features/actions/domain/action_executor_use_case.dart';
import 'package:wavectl_host/features/device/data/device_repository.dart';
import 'package:wavectl_host/features/home_assistant/data/home_assistant_repository.dart';
import 'package:wavectl_host/features/profiles/data/profile_repository.dart';
import 'package:wavectl_host/features/studio/presentation/studio_view_model.dart';
import 'package:wavectl_host/core/models/sk18_geometry.dart';

void main() {
  test('StudioViewModel preserves its facade API and status messages', () async {
    final profileRepository = ProfileRepository();
    final deviceRepository = DeviceRepository(useBackgroundJpegIsolate: false);
    final homeAssistantRepository = HomeAssistantRepository();
    final actionExecutor = ActionExecutorUseCase(
      deviceRepository: deviceRepository,
      homeAssistantRepository: homeAssistantRepository,
      hostLauncherService: HostLauncherService(dryRun: true),
    );
    final viewModel = StudioViewModel(
      profileRepository: profileRepository,
      deviceRepository: deviceRepository,
      homeAssistantRepository: homeAssistantRepository,
      actionExecutor: actionExecutor,
      startClockTimer: false,
    );
    addTearDown(() {
      viewModel.dispose();
      homeAssistantRepository.dispose();
      deviceRepository.dispose();
    });

    expect(viewModel.profiles.length, 2);
    expect(viewModel.profileEditor.activeProfile, same(viewModel.activeProfile));
    expect(viewModel.keys.session, same(viewModel.ha.session));
    expect(viewModel.audio.session, same(viewModel.device.session));

    await viewModel.initialize(
      autoConnectSimulator: true,
      envFilePath: '/non/existent/.env',
    );
    expect(viewModel.isDeviceConnected, isTrue);
    expect(viewModel.statusMessage, 'Connected: Virtual SK18 (720x1280)');

    viewModel.selectProfile(1);
    expect(viewModel.activeProfile.deviceModel, WaveshareModel.mk10);
    expect(viewModel.statusMessage, 'Switched to profile "MK10 Master Studio"');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await viewModel.switchDeviceModel(WaveshareModel.sk18);
    expect(viewModel.activeProfile.deviceModel, WaveshareModel.sk18);
    expect(viewModel.statusMessage, 'Connected: Virtual SK18 (720x1280)');

    final log = await viewModel.triggerKeyByIndex(0);
    expect(log.success, isTrue);
    expect(
      viewModel.statusMessage,
      'HA ha_toggle -> light.office_main is OFF',
    );

    await viewModel.uploadGeneratedSampleWav('facade-test.wav');
    expect(
      viewModel.statusMessage,
      startsWith('Uploaded /data/sound/facade-test.wav (CRC32: '),
    );
    expect(viewModel.wavUploadProgress, isNull);
  });
}
