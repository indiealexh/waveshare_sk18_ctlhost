import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/core/models/device_model_registry.dart';
import 'package:wavectl_host/core/models/sk18_device_info.dart';
import 'package:wavectl_host/core/models/sk18_geometry.dart';
import 'package:wavectl_host/core/protocol/serial_transport_service.dart';
import 'package:wavectl_host/features/device/data/device_repository.dart';
import 'package:wavectl_host/features/profiles/data/profile_repository.dart';
import 'package:wavectl_host/features/profiles/domain/sk18_profile.dart';

void main() {
  group('DeviceModelRegistry', () {
    final registry = DeviceModelRegistry.instance;

    test('provides one descriptor per supported model in enum order', () {
      expect(
        registry.all.map((descriptor) => descriptor.model).toList(),
        WaveshareModel.values,
      );
      expect(registry.of(WaveshareModel.sk18).spec, same(DeviceModelSpec.sk18));
      expect(registry.of(WaveshareModel.mk10).spec, same(DeviceModelSpec.mk10));
    });

    test('resolves model codes with trimming and SK18 fallback', () {
      expect(registry.fromCode('mk10 '), WaveshareModel.mk10);
      expect(registry.fromCode(' sk18 '), WaveshareModel.sk18);
      expect(registry.fromCode('unknown'), WaveshareModel.sk18);
      expect(WaveshareModel.fromString('MK10'), WaveshareModel.mk10);
    });

    test('maps simulator ports and port hints to their model descriptors', () {
      expect(
        registry.fromSimulatorPort('simulator://mk10'),
        WaveshareModel.mk10,
      );
      expect(
        registry.fromSimulatorPort('SIMULATOR://MK10'),
        WaveshareModel.mk10,
      );
      expect(registry.fromSimulatorPort('unknown://device'), isNull);
      expect(
        SerialPortDiscovery.simulatorPortForModel(WaveshareModel.mk10),
        registry.of(WaveshareModel.mk10).simulatorPortUri,
      );
    });

    test(
      'descriptors provide each model default profile and simulated info',
      () {
        for (final descriptor in registry.all) {
          final profile = descriptor.defaultProfile();
          expect(profile.deviceModel, descriptor.model);
          expect(profile.pages.first.keys.length, descriptor.spec.totalKeys);

          final portraitInfo = descriptor.simulatedDeviceInfo(portrait: true);
          final landscapeInfo = descriptor.simulatedDeviceInfo(portrait: false);
          expect(portraitInfo.model, descriptor.model);
          expect(landscapeInfo.model, descriptor.model);
          expect(
            portraitInfo.deviceHeight,
            greaterThan(portraitInfo.deviceWidth),
          );
          expect(
            landscapeInfo.deviceWidth,
            greaterThan(landscapeInfo.deviceHeight),
          );
        }
      },
    );

    test(
      'discovery and repository defaults include every registered simulator',
      () async {
        final ports = await SerialPortDiscovery.discoverPorts();
        for (final descriptor in registry.all) {
          expect(ports, contains(descriptor.simulatorPortUri));
        }

        final repository = DeviceRepository(useBackgroundJpegIsolate: false);
        addTearDown(repository.dispose);
        expect(
          repository.availablePorts,
          registry.all.map((descriptor) => descriptor.simulatorPortUri),
        );
      },
    );

    test('profile repository creates the descriptor default when absent', () {
      final repository = ProfileRepository(
        initialProfiles: [Sk18Profile.createDefault()],
      );
      addTearDown(repository.dispose);

      final profile = repository.selectOrCreateProfileForModel(
        WaveshareModel.mk10,
      );
      expect(profile.deviceModel, WaveshareModel.mk10);
      expect(profile.pages.first.keys.length, DeviceModelSpec.mk10.totalKeys);
    });

    test(
      'simulated info factories return the existing device info formats',
      () {
        final sk18Portrait = registry
            .of(WaveshareModel.sk18)
            .simulatedDeviceInfo(portrait: true);
        final mk10Portrait = registry
            .of(WaveshareModel.mk10)
            .simulatedDeviceInfo(portrait: true);
        expect(sk18Portrait.deviceModel, 'SK18');
        expect(mk10Portrait.deviceModel, 'MK10');
        expect(sk18Portrait.rects.length, 18);
        expect(mk10Portrait.rects.length, 11);
        expect(mk10Portrait.rects.first.isKey, isFalse);
      },
    );

    test(
      'V1 screen-message fallback uses the matching portrait descriptor',
      () {
        final sk18Info = Sk18DeviceInfo.fromV1ScreenMessage({
          'screen_model': 'SK18',
        });
        final mk10Info = Sk18DeviceInfo.fromV1ScreenMessage({
          'screen_model': 'MK10',
        });

        expect(sk18Info.deviceModel, 'SK18');
        expect(sk18Info.rects.length, 18);
        expect(mk10Info.deviceModel, 'MK10');
        expect(mk10Info.rects.length, 11);
        expect(mk10Info.rects.first.isKey, isFalse);
      },
    );
  });
}
