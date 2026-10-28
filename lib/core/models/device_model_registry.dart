import '../../features/profiles/domain/sk18_profile.dart';
import 'sk18_device_info.dart';
import 'sk18_geometry.dart';

class DeviceModelDescriptor {
  final WaveshareModel model;
  final DeviceModelSpec spec;
  final String simulatorPortUri;
  final Sk18Profile Function() defaultProfile;
  final Sk18DeviceInfo Function({required bool portrait}) simulatedDeviceInfo;
  final List<String> portHints;

  DeviceModelDescriptor({
    required this.model,
    required this.spec,
    required this.simulatorPortUri,
    required this.defaultProfile,
    required this.simulatedDeviceInfo,
    required List<String> portHints,
  }) : portHints = List.unmodifiable(portHints);
}

class DeviceModelRegistry {
  static DeviceModelRegistry instance = DeviceModelRegistry.defaults();

  final List<DeviceModelDescriptor> all;
  final Map<WaveshareModel, DeviceModelDescriptor> _byModel;
  final Map<String, WaveshareModel> _byCode;

  DeviceModelRegistry({required List<DeviceModelDescriptor> all})
    : all = List.unmodifiable(all),
      _byModel = Map.unmodifiable({
        for (final descriptor in all) descriptor.model: descriptor,
      }),
      _byCode = Map.unmodifiable({
        for (final descriptor in all)
          descriptor.model.code.toUpperCase(): descriptor.model,
      });

  factory DeviceModelRegistry.defaults() {
    return DeviceModelRegistry(
      all: [
        DeviceModelDescriptor(
          model: WaveshareModel.sk18,
          spec: DeviceModelSpec.sk18,
          simulatorPortUri: 'simulator://sk18',
          defaultProfile: Sk18Profile.createDefault,
          simulatedDeviceInfo: ({required bool portrait}) => portrait
              ? Sk18DeviceInfo.defaultPortrait()
              : Sk18DeviceInfo.defaultLandscape(),
          portHints: const ['sk18'],
        ),
        DeviceModelDescriptor(
          model: WaveshareModel.mk10,
          spec: DeviceModelSpec.mk10,
          simulatorPortUri: 'simulator://mk10',
          defaultProfile: Sk18Profile.createDefaultMk10,
          simulatedDeviceInfo: ({required bool portrait}) => portrait
              ? Sk18DeviceInfo.defaultMk10Portrait()
              : Sk18DeviceInfo.defaultMk10Landscape(),
          portHints: const ['mk10'],
        ),
      ],
    );
  }

  DeviceModelDescriptor of(WaveshareModel model) {
    final descriptor = _byModel[model];
    if (descriptor == null) {
      throw StateError('No device model descriptor registered for $model.');
    }
    return descriptor;
  }

  WaveshareModel fromCode(String? raw) {
    final code = raw?.trim().toUpperCase();
    return _byCode[code] ?? WaveshareModel.sk18;
  }

  WaveshareModel? fromSimulatorPort(String port) {
    final normalizedPort = port.trim().toLowerCase();
    for (final descriptor in all) {
      if (normalizedPort == descriptor.simulatorPortUri.toLowerCase() ||
          descriptor.portHints.any(
            (hint) => normalizedPort.contains(hint.toLowerCase()),
          )) {
        return descriptor.model;
      }
    }
    return null;
  }
}
