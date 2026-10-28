// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../../core/models/device_model_registry.dart';
import '../../../core/models/sk18_device_info.dart';
import '../../../core/models/sk18_geometry.dart';
import '../../../core/protocol/serial_transport_service.dart';
import '../../device/data/device_repository.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/sk18_profile.dart';
import '../../studio/presentation/studio_session.dart';

class DeviceViewModel extends StudioSubViewModel {
  final DeviceRepository _deviceRepository;
  final ProfileRepository _profileRepository;
  String _selectedPort;

  DeviceViewModel({
    required StudioSession session,
    required DeviceRepository deviceRepository,
    required ProfileRepository profileRepository,
    required String initialSelectedPort,
  }) : _deviceRepository = deviceRepository,
       _profileRepository = profileRepository,
       _selectedPort = initialSelectedPort,
       super(session);

  bool get isDeviceConnected => _deviceRepository.isConnected;
  bool get isSimulatorMode => _deviceRepository.isSimulator;
  String get selectedPort => _selectedPort;
  List<String> get availablePorts => _deviceRepository.availablePorts;
  Sk18DeviceInfo get deviceInfo => _deviceRepository.deviceInfo;

  void restoreSelectedPort(String port) {
    _selectedPort = port;
  }

  bool get isStandardSimulatorPort => DeviceModelRegistry.instance.all.any(
    (descriptor) => descriptor.simulatorPortUri == _selectedPort,
  );

  Future<void> refreshPorts({bool notifyChange = true}) async {
    await _deviceRepository.refreshPorts();
    if (!_deviceRepository.availablePorts.contains(_selectedPort)) {
      _selectedPort = SerialPortDiscovery.simulatorPortUri;
    }
    if (notifyChange) notify(markCanvasDirty: false);
  }

  void setSelectedPort(String port, {bool notifyChange = true}) {
    _selectedPort = port;
    _profileRepository.setSelectedPort(port);
    if (notifyChange) notify(markCanvasDirty: false);
  }

  Future<Sk18DeviceInfo?> connectToPort(
    String? portOverride, {
    bool notifyChange = true,
  }) async {
    final targetPort = portOverride ?? _selectedPort;
    _selectedPort = targetPort;
    _profileRepository.setSelectedPort(targetPort);
    try {
      session.bindFrameStreamer();
      final info = await _deviceRepository.connect(targetPort);
      final isExplicitModelSim = DeviceModelRegistry.instance.all.any(
        (descriptor) => descriptor.simulatorPortUri == targetPort,
      );
      if (!_deviceRepository.isSimulator || isExplicitModelSim) {
        session.setStatus(
          _deviceRepository.isSimulator
              ? 'Connected: Virtual ${info.deviceModel} (${info.deviceWidth}x${info.deviceHeight})'
              : 'Connected: ${info.deviceModel} ${info.deviceVersion} on $targetPort',
        );
      } else {
        session.setStatus(
          'Connected: Virtual ${info.deviceModel} (${info.deviceWidth}x${info.deviceHeight})',
        );
      }
      if (notifyChange) notify();
      return info;
    } catch (e) {
      session.setStatus('Connection error: $e', isError: true);
      if (notifyChange) notify(markCanvasDirty: false);
      return null;
    }
  }

  Future<void> disconnectDevice({bool notifyChange = true}) async {
    await _deviceRepository.disconnect();
    session.setStatus('Disconnected');
    if (notifyChange) notify(markCanvasDirty: false);
  }

  Future<void> syncLayoutToDevice(
    Sk18Profile profile, {
    required int pageIndex,
    bool notifyChange = true,
  }) async {
    try {
      session.bindFrameStreamer();
      final usedCustomFirmwareRpc = await _deviceRepository.syncProfileToFirmware(
        profile,
        pageIndex: pageIndex,
      );
      session.setStatus(
        usedCustomFirmwareRpc
            ? 'Synced sk18_config.json to ${deviceInfo.deviceModel}'
            : 'Synced layout & settings to ${deviceInfo.deviceModel} (${deviceInfo.deviceVersion})',
      );
    } catch (e) {
      session.setStatus('Sync failed: $e', isError: true);
    }
    if (notifyChange) notify();
  }

  void syncSimulatorPortForModel(WaveshareModel model) {
    if (!isStandardSimulatorPort) return;
    final desiredPort = SerialPortDiscovery.simulatorPortForModel(model);
    if (_selectedPort != desiredPort && availablePorts.contains(desiredPort)) {
      _selectedPort = desiredPort;
      _profileRepository.setSelectedPort(desiredPort);
      if (_deviceRepository.isConnected && _deviceRepository.isSimulator) {
        unawaited(connectToPort(desiredPort));
      }
    }
  }

  Future<void> setLandscapeMode(
    bool landscape, {
    bool notifyChange = true,
  }) async {
    final spec = _profileRepository.activeProfile.deviceModel.spec;
    final updated = _profileRepository.activeProfile.copyWith(
      landscapeMode: landscape,
    );
    _profileRepository.updateActiveProfile(updated);
    session.setStatus(
      landscape
          ? 'Orientation: Landscape (${spec.landscapeWidth}x${spec.landscapeHeight}, ${spec.landscapeCols}x${spec.landscapeRows})'
          : 'Orientation: Portrait (${spec.portraitWidth}x${spec.portraitHeight}, ${spec.portraitCols}x${spec.portraitRows})',
    );
    if (notifyChange) notify();
  }

  Future<void> setUpsideDown(
    bool upsideDown, {
    bool notifyChange = true,
  }) async {
    final updated = _profileRepository.activeProfile.copyWith(
      upsideDown: upsideDown,
    );
    _profileRepository.updateActiveProfile(updated);
    session.setStatus(
      upsideDown
          ? 'Device Display: Upside Down (180°)'
          : 'Device Display: Normal (0°)',
    );
    if (notifyChange) notify();
  }

  Future<void> setBacklight(int level, {bool notifyChange = true}) async {
    final clamped = level.clamp(0, 100);
    _profileRepository.updateActiveProfile(
      _profileRepository.activeProfile.copyWith(backlight: clamped),
    );
    if (notifyChange) notify(markCanvasDirty: false);
    try {
      await _deviceRepository.setBacklight(clamped);
    } catch (_) {}
  }

  Future<void> setVolume(int level, {bool notifyChange = true}) async {
    final clamped = level.clamp(0, 7);
    _profileRepository.updateActiveProfile(
      _profileRepository.activeProfile.copyWith(volume: clamped),
    );
    if (notifyChange) notify(markCanvasDirty: false);
    try {
      await _deviceRepository.setVolume(clamped);
    } catch (_) {}
  }

  void setCalibrationOffsets({
    int? offsetX,
    int? offsetY,
    bool notifyChange = true,
  }) {
    final activeProfile = _profileRepository.activeProfile;
    final updated = activeProfile.copyWith(
      offsetX: offsetX ?? activeProfile.offsetX,
      offsetY: offsetY ?? activeProfile.offsetY,
    );
    _profileRepository.updateActiveProfile(updated);
    session.setStatus('Calibration offset (${updated.offsetX}, ${updated.offsetY}) px');
    if (notifyChange) notify();
  }
}
