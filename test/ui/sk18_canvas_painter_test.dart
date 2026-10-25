import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wavectl_host/data/repositories/device_repository.dart';
import 'package:wavectl_host/data/repositories/home_assistant_repository.dart';
import 'package:wavectl_host/data/repositories/profile_repository.dart';
import 'package:wavectl_host/data/services/host_launcher_service.dart';
import 'package:wavectl_host/data/services/jpeg_frame_streamer.dart';
import 'package:wavectl_host/data/services/serial_transport_service.dart';
import 'package:wavectl_host/domain/models/ha_entity_state.dart';
import 'package:wavectl_host/domain/models/sk18_profile.dart';
import 'package:wavectl_host/domain/use_cases/action_executor_use_case.dart';
import 'package:wavectl_host/ui/features/studio/view_models/studio_view_model.dart';

void main() {
  testWidgets(
    'Sk18CanvasRenderer & JpegFrameStreamer produce exact 1280x720 landscape and GPU pre-rotated 720x1280 portrait JPEGs',
    (WidgetTester tester) async {
      final profile = Sk18Profile.createDefault();
      final page = profile.pages.first;
      final haEntities = <String, HaEntityState>{
        'light.office_main': const HaEntityState(
          entityId: 'light.office_main',
          domain: 'light',
          friendlyName: 'Office Light',
          state: 'on',
          attributes: {'brightness': 204},
        ),
        'climate.studio_hvac': const HaEntityState(
          entityId: 'climate.studio_hvac',
          domain: 'climate',
          friendlyName: 'Studio AC',
          state: 'cool',
          attributes: {'current_temperature': 21.5, 'temperature': 22.0},
        ),
      };

      await tester.runAsync(() async {
        // 1. Native Landscape 1280x720 JPEG
        final landscapeJpeg = await JpegFrameStreamer.renderPageToJpeg(
          page: page,
          authoringInLandscape: true,
          rotateForPortraitDevice: false,
          haEntities: haEntities,
          pressedKeyIndices: {0},
          useIsolate: false,
        );

        expect(landscapeJpeg.length, greaterThan(1000));
        expect(landscapeJpeg[0], equals(0xFF));
        expect(landscapeJpeg[1], equals(0xD8)); // SOI marker

        final decodedLandscape = img.decodeJpg(landscapeJpeg);
        expect(decodedLandscape, isNotNull);
        expect(decodedLandscape!.width, equals(1280));
        expect(decodedLandscape.height, equals(720));

        // 2. GPU Pre-Rotated Portrait 720x1280 JPEG for portrait-scanout SK18
        final rotatedPortraitJpeg = await JpegFrameStreamer.renderPageToJpeg(
          page: page,
          authoringInLandscape: true,
          rotateForPortraitDevice: true,
          haEntities: haEntities,
          useIsolate: false,
        );

        final decodedPortrait = img.decodeJpg(rotatedPortraitJpeg);
        expect(decodedPortrait, isNotNull);
        expect(decodedPortrait!.width, equals(720));
        expect(decodedPortrait.height, equals(1280));

        // 3. Verify StudioViewModel binds JpegFrameStreamer callback and streams JPEG on connect
        final profileRepo = ProfileRepository();
        final deviceRepo = DeviceRepository(useBackgroundJpegIsolate: false);
        final haRepo = HomeAssistantRepository();
        final executor = ActionExecutorUseCase(
          deviceRepository: deviceRepo,
          homeAssistantRepository: haRepo,
          hostLauncherService: HostLauncherService(dryRun: true),
        );
        final vm = StudioViewModel(
          profileRepository: profileRepo,
          deviceRepository: deviceRepo,
          homeAssistantRepository: haRepo,
          actionExecutor: executor,
          startClockTimer: false,
          streamFramesInSimulator: true,
        );

        await vm.connectToPort(SerialPortDiscovery.simulatorPortUri);
        // Allow async offscreen GPU rasterization and JPEG transmission to complete
        for (int i = 0; i < 20 && deviceRepo.frameStreamer.framesSentCount == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(deviceRepo.frameStreamer.framesSentCount, greaterThanOrEqualTo(1));
        expect(deviceRepo.simulatorTransport.framesReceivedCount, greaterThanOrEqualTo(1));
        expect(deviceRepo.simulatorTransport.lastFrameJpegBytes, isNotNull);

        vm.dispose();
        haRepo.dispose();
        deviceRepo.dispose();
      });
    },
  );
}
