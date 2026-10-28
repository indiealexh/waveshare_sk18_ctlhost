// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/device_model_registry.dart';
import '../../../core/models/sk18_device_info.dart';
import '../../../core/models/sk18_geometry.dart';
import '../../../core/protocol/serial_transport_service.dart';
import '../../../core/protocol/sk18_rpc_client.dart';
import '../../../core/rendering/sk18_canvas_painter.dart';
import '../../actions/domain/action_executor_use_case.dart';
import '../../actions/domain/button_action.dart';
import '../../actions/presentation/key_interaction_view_model.dart';
import '../../audio/presentation/audio_view_model.dart';
import '../../device/data/device_repository.dart';
import '../../device/presentation/device_view_model.dart';
import '../../home_assistant/data/home_assistant_repository.dart';
import '../../home_assistant/domain/ha_entity_state.dart';
import '../../home_assistant/presentation/ha_view_model.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/key_button_config.dart';
import '../../profiles/domain/sk18_profile.dart';
import '../../profiles/presentation/profile_editor_view_model.dart';
import 'studio_session.dart';

class StudioViewModel extends ChangeNotifier {
  final ProfileRepository _profileRepository;
  final DeviceRepository _deviceRepository;
  final HomeAssistantRepository _homeAssistantRepository;
  final ActionExecutorUseCase _actionExecutor;
  final bool streamFramesInSimulator;
  final StudioSession _session = StudioSession();

  late final DeviceViewModel device;
  late final ProfileEditorViewModel profileEditor;
  late final KeyInteractionViewModel keys;
  late final HaViewModel ha;
  late final AudioViewModel audio;

  StreamSubscription<Sk18DeviceEvent>? _deviceEventSub;
  Timer? _clockTimer;
  String _clockString = '12:00';
  bool _disposed = false;

  StudioViewModel({
    required ProfileRepository profileRepository,
    required DeviceRepository deviceRepository,
    required HomeAssistantRepository homeAssistantRepository,
    required ActionExecutorUseCase actionExecutor,
    bool startClockTimer = true,
    this.streamFramesInSimulator = false,
  }) : _profileRepository = profileRepository,
       _deviceRepository = deviceRepository,
       _homeAssistantRepository = homeAssistantRepository,
       _actionExecutor = actionExecutor {
    device = DeviceViewModel(
      session: _session,
      deviceRepository: _deviceRepository,
      profileRepository: _profileRepository,
      initialSelectedPort: _profileRepository.selectedPort,
    );
    profileEditor = ProfileEditorViewModel(
      session: _session,
      profileRepository: _profileRepository,
    );
    keys = KeyInteractionViewModel(
      session: _session,
      profiles: profileEditor,
      deviceRepository: _deviceRepository,
      actionExecutor: _actionExecutor,
      initialInteractiveTriggerOnTap: _profileRepository.interactiveTriggerOnTap,
    );
    ha = HaViewModel(
      session: _session,
      homeAssistantRepository: _homeAssistantRepository,
    );
    audio = AudioViewModel(
      session: _session,
      deviceRepository: _deviceRepository,
    );

    _session
      ..requestFrame = _pumpDeviceFrameIfNeeded
      ..bindFrameStreamer = _ensureFrameStreamerCallbackBound;
    for (final subViewModel in _subViewModels) {
      subViewModel.addListener(_onSubViewModelChanged);
    }

    _updateClockString();
    _ensureFrameStreamerCallbackBound();
    _deviceEventSub = _deviceRepository.deviceEvents.listen(
      _onDeviceEventReceived,
    );
    if (startClockTimer) {
      _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _updateClockString();
        _safeNotifyListeners();
      });
    }
  }

  List<StudioSubViewModel> get _subViewModels => [
    device,
    profileEditor,
    keys,
    ha,
    audio,
  ];

  List<Sk18Profile> get profiles => profileEditor.profiles;
  int get activeProfileIndex => profileEditor.activeProfileIndex;
  int get activePageIndex => profileEditor.activePageIndex;
  Sk18Profile get activeProfile => profileEditor.activeProfile;
  Sk18Page get activePage => profileEditor.activePage;
  WaveshareModel get activeDeviceModel => activeProfile.deviceModel;
  DeviceModelSpec get activeModelSpec => activeProfile.deviceModel.spec;

  int get selectedKeyIndex => keys.selectedKeyIndex;
  KeyButtonConfig get selectedKeyConfig => keys.selectedKeyConfig;
  Set<int> get pressedKeyIndices => keys.pressedKeyIndices;
  bool get interactiveTriggerOnTap => keys.interactiveTriggerOnTap;

  bool get isDeviceConnected => device.isDeviceConnected;
  bool get isSimulatorMode => device.isSimulatorMode;
  String get selectedPort => device.selectedPort;
  List<String> get availablePorts => device.availablePorts;
  Sk18DeviceInfo get deviceInfo => device.deviceInfo;
  List<Sk18WavFileEntry> get wavFiles => audio.wavFiles;
  double? get wavUploadProgress => audio.wavUploadProgress;

  Map<String, HaEntityState> get haEntities => ha.haEntities;
  String get haBaseUrl => ha.haBaseUrl;
  bool get isHaConfigured => ha.isHaConfigured;

  List<ActionExecutionLog> get executionLogs => keys.executionLogs;
  String get statusMessage => _session.statusMessage;
  bool get isStatusError => _session.isStatusError;
  String get clockString => _clockString;

  void _ensureFrameStreamerCallbackBound() {
    _deviceRepository.frameStreamer.setFrameRenderCallback(
      _renderCurrentDeviceFrame,
    );
  }

  Future<Sk18RawFrameBuffer> _renderCurrentDeviceFrame() {
    final profile = activeProfile;
    final page = activePage;
    final devInfo = _deviceRepository.deviceInfo;
    return Sk18CanvasRenderer.renderOffscreenRgba(
      page: page,
      authoringInLandscape: profile.landscapeMode,
      rotateForPortraitDevice: devInfo.isPortrait,
      model: profile.deviceModel,
      upsideDown: profile.upsideDown,
      haEntities: haEntities,
      pressedKeyIndices: pressedKeyIndices,
      rawDeviceRects: devInfo.rects,
      offsetX: profile.offsetX,
      offsetY: profile.offsetY,
      profileName: profile.name,
      statusText: _deviceRepository.isSimulator ? 'SIMULATOR' : 'USB LIVE',
      clockString: _clockString,
    );
  }

  void _pumpDeviceFrameIfNeeded() {
    if (_disposed || !_deviceRepository.isConnected) return;
    if (_deviceRepository.isSimulator && !streamFramesInSimulator) return;
    _ensureFrameStreamerCallbackBound();
    unawaited(_deviceRepository.frameStreamer.markDirtyAndPump());
  }

  Future<void> initialize({
    bool autoConnectSimulator = true,
    String envFilePath = '.env',
  }) async {
    await _profileRepository.loadSavedConfig();
    device.restoreSelectedPort(_profileRepository.selectedPort);
    keys.restoreInteractiveTriggerOnTap(
      _profileRepository.interactiveTriggerOnTap,
    );

    await device.refreshPorts(notifyChange: false);
    await _homeAssistantRepository.initializeFromEnv(envFilePath: envFilePath);
    if (autoConnectSimulator) {
      final restoredPort = selectedPort;
      final targetPort = availablePorts.contains(restoredPort)
          ? restoredPort
          : SerialPortDiscovery.simulatorPortUri;
      await connectToPort(targetPort);
      if (!isDeviceConnected && targetPort != SerialPortDiscovery.simulatorPortUri) {
        await connectToPort(SerialPortDiscovery.simulatorPortUri);
      }
    } else {
      _safeNotifyListeners();
    }
  }

  Future<void> refreshPorts() => device.refreshPorts();

  void setSelectedPort(String port) => device.setSelectedPort(port);

  Future<void> connectToPort([String? portOverride]) async {
    final targetPort = portOverride ?? selectedPort;
    final info = await device.connectToPort(
      targetPort,
      notifyChange: false,
    );
    if (info == null) {
      _safeNotifyListeners(markCanvasDirty: false);
      return;
    }

    final isExplicitModelSim = DeviceModelRegistry.instance.all.any(
      (descriptor) => descriptor.simulatorPortUri == targetPort,
    );
    if (!device.isSimulatorMode || isExplicitModelSim) {
      if (activeProfile.deviceModel != info.model) {
        profileEditor.selectOrCreateProfileForModel(info.model);
        keys.resetSelection(notifyChange: false);
      }
    }
    keys.clampSelection(activePage.keys.length);
    _safeNotifyListeners();
  }

  Future<void> disconnectDevice() => device.disconnectDevice();

  Future<void> syncLayoutToDevice() => device.syncLayoutToDevice(
    activeProfile,
    pageIndex: activePageIndex,
  );

  void _syncVirtualSimulatorForActiveProfile() {
    device.syncSimulatorPortForModel(activeProfile.deviceModel);
  }

  Future<void> switchDeviceModel(WaveshareModel model) async {
    profileEditor.selectOrCreateProfileForModel(model);
    keys.resetSelection(notifyChange: false);
    final desiredPort = SerialPortDiscovery.simulatorPortForModel(model);
    if (device.isStandardSimulatorPort &&
        availablePorts.contains(desiredPort)) {
      await connectToPort(desiredPort);
      return;
    }
    _session.setStatus(
      'Switched to ${model.code} profile "${activeProfile.name}"',
    );
    _safeNotifyListeners();
  }

  void selectProfile(int index) {
    profileEditor.selectProfile(index, notifyChange: false);
    keys.resetSelection(notifyChange: false);
    _syncVirtualSimulatorForActiveProfile();
    _safeNotifyListeners();
  }

  void createNewProfile(String name, {WaveshareModel? model}) {
    profileEditor.createNewProfile(name, model: model, notifyChange: false);
    keys.resetSelection(notifyChange: false);
    _syncVirtualSimulatorForActiveProfile();
    _safeNotifyListeners();
  }

  void selectPage(int index) {
    profileEditor.selectPage(index, notifyChange: false);
    keys.resetSelection(notifyChange: false);
    _safeNotifyListeners();
  }

  void addNewPage(String name) {
    profileEditor.addNewPage(name, notifyChange: false);
    keys.resetSelection(notifyChange: false);
    _safeNotifyListeners();
  }

  String exportProfileJson() => profileEditor.exportProfileJson();

  bool importProfileJson(String jsonContent) {
    final imported = profileEditor.importProfileJson(
      jsonContent,
      notifyChange: false,
    );
    if (imported) {
      keys.resetSelection(notifyChange: false);
      _safeNotifyListeners();
    } else {
      _safeNotifyListeners(markCanvasDirty: false);
    }
    return imported;
  }

  Future<void> setLandscapeMode(bool landscape) =>
      device.setLandscapeMode(landscape);

  Future<void> setUpsideDown(bool upsideDown) =>
      device.setUpsideDown(upsideDown);

  Future<void> setBacklight(int level) => device.setBacklight(level);

  Future<void> setVolume(int level) => device.setVolume(level);

  void setCalibrationOffsets({int? offsetX, int? offsetY}) =>
      device.setCalibrationOffsets(offsetX: offsetX, offsetY: offsetY);

  void setInteractiveTriggerOnTap(bool value) =>
      keys.setInteractiveTriggerOnTap(value);

  void selectKey(int index) => keys.selectKey(index);

  Future<void> handleCanvasKeyTap(int index) => keys.handleCanvasKeyTap(index);

  void updateSelectedKeyConfig(KeyButtonConfig updatedKey) =>
      keys.updateSelectedKeyConfig(updatedKey);

  void updateSelectedKeyLabel(String label) =>
      updateSelectedKeyConfig(selectedKeyConfig.copyWith(label: label));

  void updateSelectedKeyIcon(String iconName) =>
      updateSelectedKeyConfig(selectedKeyConfig.copyWith(iconName: iconName));

  void updateSelectedKeyColor(int colorHex) =>
      updateSelectedKeyConfig(selectedKeyConfig.copyWith(colorHex: colorHex));

  void updateSelectedKeyAction(ButtonAction action) =>
      updateSelectedKeyConfig(selectedKeyConfig.copyWith(action: action));

  Future<ActionExecutionLog> triggerKeyByIndex(
    int index, {
    bool fromPhysicalDevice = false,
  }) => keys.triggerKeyByIndex(
    index,
    fromPhysicalDevice: fromPhysicalDevice,
  );

  Future<ActionExecutionLog> triggerSelectedKey() => keys.triggerSelectedKey();

  void updateHomeAssistantCredentials({
    required String baseUrl,
    required String token,
  }) => ha.updateHomeAssistantCredentials(baseUrl: baseUrl, token: token);

  Future<void> refreshHomeAssistantStates() => ha.refreshHomeAssistantStates();

  Future<void> uploadWavBytes({
    required String fileName,
    required Uint8List wavBytes,
  }) => audio.uploadWavBytes(fileName: fileName, wavBytes: wavBytes);

  Future<void> uploadGeneratedSampleWav(String name) =>
      audio.uploadGeneratedSampleWav(name);

  Future<void> playWavFile(String remoteFilePath) =>
      audio.playWavFile(remoteFilePath);

  Future<void> stopWavPlayback() => audio.stopWavPlayback();

  Future<void> deleteWavFile(String remoteFilePath) =>
      audio.deleteWavFile(remoteFilePath);

  void _onDeviceEventReceived(Sk18DeviceEvent event) {
    switch (event.method) {
      case 'keyStateChanged':
        unawaited(keys.handleKeyStateChanged(event));
        break;
      case 'macroTriggered':
        unawaited(keys.handleMacroTriggered(event.parameters));
        break;
      case 'haStateUpdated':
        ha.handleHaStateUpdated(event.parameters);
        break;
    }
  }

  void _updateClockString() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _clockString = '$hh:$mm';
  }

  void _onSubViewModelChanged() {
    if (!_disposed) notifyListeners();
  }

  void _safeNotifyListeners({bool markCanvasDirty = true}) {
    if (markCanvasDirty) _pumpDeviceFrameIfNeeded();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session.disposed = true;
    _clockTimer?.cancel();
    _clockTimer = null;
    _deviceEventSub?.cancel();
    for (final subViewModel in _subViewModels) {
      subViewModel.removeListener(_onSubViewModelChanged);
      subViewModel.dispose();
    }
    _profileRepository.dispose();
    super.dispose();
  }
}
