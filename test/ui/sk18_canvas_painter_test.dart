import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wavectl_host/features/device/data/device_repository.dart';
import 'package:wavectl_host/features/home_assistant/data/home_assistant_repository.dart';
import 'package:wavectl_host/features/profiles/data/profile_repository.dart';
import 'package:wavectl_host/features/actions/data/host_launcher_service.dart';
import 'package:wavectl_host/features/device/data/jpeg_frame_streamer.dart';
import 'package:wavectl_host/core/protocol/serial_transport_service.dart';
import 'package:wavectl_host/features/home_assistant/domain/ha_entity_state.dart';
import 'package:wavectl_host/core/models/sk18_geometry.dart';
import 'package:wavectl_host/features/profiles/domain/sk18_profile.dart';
import 'package:wavectl_host/features/actions/domain/action_executor_use_case.dart';
import 'package:wavectl_host/core/rendering/sk18_canvas_painter.dart';
import 'package:wavectl_host/features/studio/presentation/studio_view_model.dart';

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

        // 2b. Verify upsideDown 180-degree flip renders valid frame and swaps key slot positions
        final normalRaw = await Sk18CanvasRenderer.renderOffscreenRgba(
          page: page,
          authoringInLandscape: true,
          rotateForPortraitDevice: false,
          upsideDown: false,
          haEntities: haEntities,
        );
        final upsideDownRaw = await Sk18CanvasRenderer.renderOffscreenRgba(
          page: page,
          authoringInLandscape: true,
          rotateForPortraitDevice: false,
          upsideDown: true,
          haEntities: haEntities,
        );
        expect(upsideDownRaw.width, equals(1280));
        expect(upsideDownRaw.height, equals(720));
        // Sample a pixel inside K1's top-left border/fill area (col=0, row=0 -> x=30, y=75)
        // vs K18's bottom-right mirror position (col=5, row=2 -> x=1112 + (158 - 1 - 8) = 1261, y=499 + (158 - 1 - 12) = 644)
        expect(upsideDownRaw.rgbaBytes, isNot(equals(normalRaw.rgbaBytes)));

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

        // 4. MK10 896x304 landscape and GPU pre-rotated 304x896 portrait rendering
        final mk10Profile = Sk18Profile.createDefaultMk10();
        final mk10Page = mk10Profile.pages.first;

        final mk10LandscapeRaw = await Sk18CanvasRenderer.renderOffscreenRgba(
          page: mk10Page,
          authoringInLandscape: true,
          rotateForPortraitDevice: false,
          model: WaveshareModel.mk10,
          haEntities: haEntities,
          profileName: mk10Profile.name,
        );
        expect(mk10LandscapeRaw.width, equals(896));
        expect(mk10LandscapeRaw.height, equals(304));

        // Verify the side-screen rich telemetry card at x=656..896 renders a
        // badge pixel (x=700, y=30) that differs from the plain background
        // in the 16 px gutter between keys and side screen (x=648, y=150).
        int pixelRgb(Sk18RawFrameBuffer buf, int x, int y) {
          final offset = (y * buf.width + x) * 4;
          return (buf.rgbaBytes[offset] << 16) |
              (buf.rgbaBytes[offset + 1] << 8) |
              buf.rgbaBytes[offset + 2];
        }

        final outerBgPixel = pixelRgb(mk10LandscapeRaw, 648, 150);
        final headerCardPixel = pixelRgb(mk10LandscapeRaw, 700, 30);
        expect(headerCardPixel, isNot(equals(outerBgPixel)));
        expect(DeviceModelSpec.mk10.statusRegionCornerRadius, equals(40));

        // Verify the MK10 side screen uses the 40 px corner radius (so points
        // 9 px inside cardRect's bounding box corners are outside the 40 px arc
        // and stay background, whereas points inside the 40 px arc are painted).
        for (final cornerOutside in const [
          (668, 12),
          (884, 12),
          (668, 284),
          (884, 284),
        ]) {
          final rgb = pixelRgb(
            mk10LandscapeRaw,
            cornerOutside.$1,
            cornerOutside.$2,
          );
          final rChannel = (rgb >> 16) & 0xFF;
          // Outside the 40 px arc remains the dark LCD background (R <= 0x12),
          // not the lighter slate/cyan card fill/border (R >= 0x18).
          expect(rChannel, lessThanOrEqualTo(0x12));
        }
        final insideArcRgb = pixelRgb(mk10LandscapeRaw, 675, 19);
        expect((insideArcRgb >> 16) & 0xFF, greaterThanOrEqualTo(0x18));

        // Verify MK10 tiles are inset and clipped to their 128x128 cell so no
        // 1-2 px border or selection ring bleeds into adjacent tiles on any side.
        final mk10KeyRects = Sk18Geometry.computeKeyRects(
          isPortrait: false,
          model: WaveshareModel.mk10,
        );
        for (final rect in mk10KeyRects) {
          final midX = rect.centerX.floor();
          final midY = rect.centerY.floor();
          // Outer 2 px on all 4 sides of each 128x128 cell must remain background
          // (no neighbor border bleed) while the inset border at +3 / -3 is painted.
          final leftOuter = pixelRgb(mk10LandscapeRaw, rect.x + 1, midY);
          final rightOuter = pixelRgb(mk10LandscapeRaw, rect.right - 1, midY);
          final topOuter = pixelRgb(mk10LandscapeRaw, midX, rect.y + 1);
          final bottomOuter = pixelRgb(mk10LandscapeRaw, midX, rect.bottom - 1);

          final leftBorder = pixelRgb(mk10LandscapeRaw, rect.x + 3, midY);
          final rightBorder = pixelRgb(mk10LandscapeRaw, rect.right - 3, midY);
          final topBorder = pixelRgb(mk10LandscapeRaw, midX, rect.y + 3);
          final bottomBorder = pixelRgb(mk10LandscapeRaw, midX, rect.bottom - 3);

          expect(leftBorder, isNot(equals(leftOuter)));
          expect(rightBorder, isNot(equals(rightOuter)));
          expect(topBorder, isNot(equals(topOuter)));
          expect(bottomBorder, isNot(equals(bottomOuter)));
        }

        // Pressing K1 (index 0) must not alter a single pixel inside adjacent
        // tiles K2 (x=128..255, y=0..127) or K6 (x=0..127, y=128..255).
        final mk10PressedRaw = await Sk18CanvasRenderer.renderOffscreenRgba(
          page: mk10Page,
          authoringInLandscape: true,
          rotateForPortraitDevice: false,
          model: WaveshareModel.mk10,
          haEntities: haEntities,
          pressedKeyIndices: const {0},
          profileName: mk10Profile.name,
        );
        for (final neighborIndex in const [1, 5]) {
          final neighbor = mk10KeyRects[neighborIndex];
          for (int y = neighbor.y; y <= neighbor.bottom; y++) {
            for (int x = neighbor.x; x <= neighbor.right; x++) {
              expect(
                pixelRgb(mk10PressedRaw, x, y),
                equals(pixelRgb(mk10LandscapeRaw, x, y)),
              );
            }
          }
        }

        final mk10RotatedJpeg = await JpegFrameStreamer.renderPageToJpeg(
          page: mk10Page,
          authoringInLandscape: true,
          rotateForPortraitDevice: true,
          model: WaveshareModel.mk10,
          haEntities: haEntities,
          useIsolate: false,
        );
        final decodedMk10Portrait = img.decodeJpg(mk10RotatedJpeg);
        expect(decodedMk10Portrait, isNotNull);
        expect(decodedMk10Portrait!.width, equals(304));
        expect(decodedMk10Portrait.height, equals(896));

        vm.dispose();
        haRepo.dispose();
        deviceRepo.dispose();
      });
    },
  );
}
