// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/device_repository.dart';
import '../../../../data/repositories/home_assistant_repository.dart';
import '../../../../data/repositories/profile_repository.dart';
import '../../../../data/services/serial_transport_service.dart';
import '../../../../data/services/sk18_rpc_client.dart';
import '../../../../domain/models/button_action.dart';
import '../../../../domain/models/ha_entity_state.dart';
import '../../../../domain/models/key_button_config.dart';
import '../../../../domain/models/sk18_device_info.dart';
import '../../../../domain/models/sk18_geometry.dart';
import '../../../../domain/models/sk18_profile.dart';
import '../../../../domain/use_cases/action_executor_use_case.dart';
import '../../../core/rendering/sk18_canvas_painter.dart';

/// Main studio ViewModel (`ChangeNotifier`) coordinating multi-page profiles,
/// 18-key selection & customization, hybrid action dispatch, Home Assistant
/// telemetry, on-device WAV management, and SK18 serial/simulator connection.
class StudioViewModel extends ChangeNotifier {
  final ProfileRepository _profileRepository;
  final DeviceRepository _deviceRepository;
  final HomeAssistantRepository _homeAssistantRepository;
  final ActionExecutorUseCase _actionExecutor;
  final bool streamFramesInSimulator;

  StreamSubscription<Sk18DeviceEvent>? _deviceEventSub;
  Timer? _clockTimer;
  final Map<int, Timer> _releaseTimers = <int, Timer>{};

  int _selectedKeyIndex = 0;
  final Set<int> _pressedKeyIndices = <int>{};
  bool _interactiveTriggerOnTap = false;
  String _selectedPort = SerialPortDiscovery.simulatorPortUri;
  String _statusMessage = 'Simulator Ready';
  bool _isStatusError = false;
  double? _wavUploadProgress;
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
       _actionExecutor = actionExecutor,
       _selectedPort = profileRepository.selectedPort,
       _interactiveTriggerOnTap = profileRepository.interactiveTriggerOnTap {
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

  // --- Exposed State Getters ---

  List<Sk18Profile> get profiles => _profileRepository.profiles;
  int get activeProfileIndex => _profileRepository.activeProfileIndex;
  int get activePageIndex => _profileRepository.activePageIndex;
  Sk18Profile get activeProfile => _profileRepository.activeProfile;
  Sk18Page get activePage => _profileRepository.activePage;

  int get selectedKeyIndex => _selectedKeyIndex;
  KeyButtonConfig get selectedKeyConfig =>
      activePage.keys[_selectedKeyIndex.clamp(0, activePage.keys.length - 1)];

  Set<int> get pressedKeyIndices => Set.unmodifiable(_pressedKeyIndices);
  bool get interactiveTriggerOnTap => _interactiveTriggerOnTap;

  bool get isDeviceConnected => _deviceRepository.isConnected;
  bool get isSimulatorMode => _deviceRepository.isSimulator;
  String get selectedPort => _selectedPort;
  List<String> get availablePorts => _deviceRepository.availablePorts;
  Sk18DeviceInfo get deviceInfo => _deviceRepository.deviceInfo;
  List<Sk18WavFileEntry> get wavFiles => _deviceRepository.wavFiles;
  double? get wavUploadProgress => _wavUploadProgress;

  Map<String, HaEntityState> get haEntities =>
      _homeAssistantRepository.entities;
  String get haBaseUrl => _homeAssistantRepository.baseUrl;
  bool get isHaConfigured => _homeAssistantRepository.isConfigured;

  List<ActionExecutionLog> get executionLogs => _actionExecutor.logs;
  String get statusMessage => _statusMessage;
  bool get isStatusError => _isStatusError;
  String get clockString => _clockString;

  void _setStatus(String message, {bool isError = false}) {
    _statusMessage = message;
    _isStatusError = isError;
  }

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

  // --- Initialization & Connection ---

  Future<void> initialize({
    bool autoConnectSimulator = true,
    String envFilePath = '.env',
  }) async {
    await _profileRepository.loadSavedConfig();
    _selectedPort = _profileRepository.selectedPort;
    _interactiveTriggerOnTap = _profileRepository.interactiveTriggerOnTap;

    await _deviceRepository.refreshPorts();
    await _homeAssistantRepository.initializeFromEnv(envFilePath: envFilePath);
    if (autoConnectSimulator) {
      final restoredPort = _selectedPort;
      final targetPort = _deviceRepository.availablePorts.contains(restoredPort)
          ? restoredPort
          : SerialPortDiscovery.simulatorPortUri;
      await connectToPort(targetPort);
      if (!_deviceRepository.isConnected &&
          targetPort != SerialPortDiscovery.simulatorPortUri) {
        await connectToPort(SerialPortDiscovery.simulatorPortUri);
      }
    } else {
      _safeNotifyListeners();
    }
  }

  Future<void> refreshPorts() async {
    await _deviceRepository.refreshPorts();
    if (!_deviceRepository.availablePorts.contains(_selectedPort)) {
      _selectedPort = SerialPortDiscovery.simulatorPortUri;
    }
    _safeNotifyListeners(markCanvasDirty: false);
  }

  void setSelectedPort(String port) {
    _selectedPort = port;
    _profileRepository.setSelectedPort(port);
    _safeNotifyListeners(markCanvasDirty: false);
  }

  Future<void> connectToPort([String? portOverride]) async {
    final targetPort = portOverride ?? _selectedPort;
    _selectedPort = targetPort;
    _profileRepository.setSelectedPort(targetPort);
    try {
      _ensureFrameStreamerCallbackBound();
      final info = await _deviceRepository.connect(targetPort);
      _setStatus(
        _deviceRepository.isSimulator
            ? 'Connected: Virtual SK18 (${info.deviceWidth}x${info.deviceHeight})'
            : 'Connected: ${info.deviceModel} ${info.deviceVersion} on $targetPort',
      );
    } catch (e) {
      _setStatus('Connection error: $e', isError: true);
    }
    _safeNotifyListeners();
  }

  Future<void> disconnectDevice() async {
    await _deviceRepository.disconnect();
    _setStatus('Disconnected');
    _safeNotifyListeners(markCanvasDirty: false);
  }

  Future<void> syncLayoutToDevice() async {
    try {
      _ensureFrameStreamerCallbackBound();
      final usedCustomFirmwareRpc = await _deviceRepository
          .syncProfileToFirmware(
            activeProfile,
            pageIndex: activePageIndex,
          );
      _setStatus(
        usedCustomFirmwareRpc
            ? 'Synced sk18_config.json to SK18'
            : 'Synced layout & settings to SK18 (${deviceInfo.deviceVersion})',
      );
    } catch (e) {
      _setStatus('Sync failed: $e', isError: true);
    }
    _safeNotifyListeners();
  }

  // --- Profile & Page Management ---

  void selectProfile(int index) {
    _profileRepository.selectProfile(index);
    _selectedKeyIndex = 0;
    _setStatus('Switched to profile "${activeProfile.name}"');
    _safeNotifyListeners();
  }

  void createNewProfile(String name) {
    final created = _profileRepository.createProfile(name);
    _selectedKeyIndex = 0;
    _setStatus('Created profile "${created.name}"');
    _safeNotifyListeners();
  }

  void selectPage(int index) {
    _profileRepository.selectPage(index);
    _selectedKeyIndex = 0;
    _setStatus('Switched to page "${activePage.name}"');
    _safeNotifyListeners();
  }

  void addNewPage(String name) {
    final created = _profileRepository.addPage(name);
    _selectedKeyIndex = 0;
    _setStatus('Added page "${created.name}"');
    _safeNotifyListeners();
  }

  String exportProfileJson() {
    return _profileRepository.exportActiveProfileJson(pretty: true);
  }

  bool importProfileJson(String jsonContent) {
    try {
      final imported = _profileRepository.importProfileFromJsonString(
        jsonContent,
      );
      _selectedKeyIndex = 0;
      _setStatus('Imported profile "${imported.name}"');
      _safeNotifyListeners();
      return true;
    } catch (e) {
      _setStatus('Invalid JSON config: $e', isError: true);
      _safeNotifyListeners(markCanvasDirty: false);
      return false;
    }
  }

  // --- Device Settings & Calibration ---

  Future<void> setLandscapeMode(bool landscape) async {
    final updated = activeProfile.copyWith(landscapeMode: landscape);
    _profileRepository.updateActiveProfile(updated);
    _setStatus(
      landscape
          ? 'Orientation: Landscape (1280x720, 6x3)'
          : 'Orientation: Portrait (720x1280, 3x6)',
    );
    _safeNotifyListeners();
  }

  Future<void> setUpsideDown(bool upsideDown) async {
    final updated = activeProfile.copyWith(upsideDown: upsideDown);
    _profileRepository.updateActiveProfile(updated);
    _setStatus(
      upsideDown
          ? 'Device Display: Upside Down (180°)'
          : 'Device Display: Normal (0°)',
    );
    _safeNotifyListeners();
  }

  Future<void> setBacklight(int level) async {
    final clamped = level.clamp(0, 100);
    _profileRepository.updateActiveProfile(
      activeProfile.copyWith(backlight: clamped),
    );
    _safeNotifyListeners(markCanvasDirty: false);
    try {
      await _deviceRepository.setBacklight(clamped);
    } catch (_) {}
  }

  Future<void> setVolume(int level) async {
    final clamped = level.clamp(0, 7);
    _profileRepository.updateActiveProfile(
      activeProfile.copyWith(volume: clamped),
    );
    _safeNotifyListeners(markCanvasDirty: false);
    try {
      await _deviceRepository.setVolume(clamped);
    } catch (_) {}
  }

  void setCalibrationOffsets({int? offsetX, int? offsetY}) {
    final updated = activeProfile.copyWith(
      offsetX: offsetX ?? activeProfile.offsetX,
      offsetY: offsetY ?? activeProfile.offsetY,
    );
    _profileRepository.updateActiveProfile(updated);
    _setStatus('Calibration offset (${updated.offsetX}, ${updated.offsetY}) px');
    _safeNotifyListeners();
  }

  // --- Key Selection, Customization & Execution ---

  void setInteractiveTriggerOnTap(bool value) {
    _interactiveTriggerOnTap = value;
    _profileRepository.setInteractiveTriggerOnTap(value);
    _safeNotifyListeners(markCanvasDirty: false);
  }

  void selectKey(int index) {
    if (index < 0 || index >= Sk18Geometry.totalKeys) return;
    _selectedKeyIndex = index;
    _safeNotifyListeners(markCanvasDirty: false);
  }

  Future<void> handleCanvasKeyTap(int index) async {
    selectKey(index);
    if (_interactiveTriggerOnTap) {
      await triggerKeyByIndex(index, fromPhysicalDevice: false);
    }
  }

  void updateSelectedKeyConfig(KeyButtonConfig updatedKey) {
    _profileRepository.updateKeyConfig(_selectedKeyIndex, updatedKey);
    _safeNotifyListeners();
  }

  void updateSelectedKeyLabel(String label) {
    updateSelectedKeyConfig(selectedKeyConfig.copyWith(label: label));
  }

  void updateSelectedKeyIcon(String iconName) {
    updateSelectedKeyConfig(selectedKeyConfig.copyWith(iconName: iconName));
  }

  void updateSelectedKeyColor(int colorHex) {
    updateSelectedKeyConfig(selectedKeyConfig.copyWith(colorHex: colorHex));
  }

  void updateSelectedKeyAction(ButtonAction action) {
    updateSelectedKeyConfig(selectedKeyConfig.copyWith(action: action));
  }

  /// Triggers a key action by logical index (`0..17`) and animates the key press highlight.
  Future<ActionExecutionLog> triggerKeyByIndex(
    int index, {
    bool fromPhysicalDevice = false,
  }) async {
    final safeIdx = index.clamp(0, Sk18Geometry.totalKeys - 1);
    final keyConfig = activePage.keys[safeIdx];

    _pressedKeyIndices.add(safeIdx);
    _releaseTimers[safeIdx]?.cancel();
    _releaseTimers[safeIdx] = Timer(const Duration(milliseconds: 180), () {
      _pressedKeyIndices.remove(safeIdx);
      _releaseTimers.remove(safeIdx);
      _safeNotifyListeners();
    });
    _safeNotifyListeners();

    final log = await _actionExecutor.executeKeyAction(keyConfig);
    _setStatus(log.summary, isError: !log.success);
    _safeNotifyListeners();
    return log;
  }

  Future<ActionExecutionLog> triggerSelectedKey() {
    return triggerKeyByIndex(_selectedKeyIndex, fromPhysicalDevice: false);
  }

  // --- Home Assistant & On-Device WAV Management ---

  void updateHomeAssistantCredentials({
    required String baseUrl,
    required String token,
  }) {
    _homeAssistantRepository.updateCredentials(baseUrl: baseUrl, token: token);
    _setStatus('Updated Home Assistant endpoint: $baseUrl');
    _safeNotifyListeners(markCanvasDirty: false);
  }

  Future<void> refreshHomeAssistantStates() async {
    try {
      await _homeAssistantRepository.refreshStates();
      _setStatus('Refreshed Home Assistant entity telemetry');
    } catch (e) {
      _setStatus('HA refresh error: $e', isError: true);
    }
    _safeNotifyListeners();
  }

  Future<void> uploadWavBytes({
    required String fileName,
    required Uint8List wavBytes,
  }) async {
    final sanitized = fileName.endsWith('.wav') ? fileName : '$fileName.wav';
    final remotePath = sanitized.startsWith('/data/sound/')
        ? sanitized
        : '/data/sound/$sanitized';

    _wavUploadProgress = 0.0;
    _setStatus('Uploading $remotePath...');
    _safeNotifyListeners(markCanvasDirty: false);

    try {
      final crc = await _deviceRepository.uploadWavFile(
        remoteFilePath: remotePath,
        wavBytes: wavBytes,
        onProgress: (p) {
          _wavUploadProgress = p;
          _safeNotifyListeners(markCanvasDirty: false);
        },
      );
      _setStatus('Uploaded $remotePath (CRC32: $crc)');
    } catch (e) {
      _setStatus('WAV upload failed: $e', isError: true);
    } finally {
      _wavUploadProgress = null;
      _safeNotifyListeners(markCanvasDirty: false);
    }
  }

  Future<void> uploadGeneratedSampleWav(String name) async {
    // Generate a valid 44-byte PCM WAV header + 4 KB sine/pulse sample
    final sampleBytes = Uint8List(4096);
    for (int i = 0; i < sampleBytes.length; i++) {
      sampleBytes[i] = (i * 17) & 0xFF;
    }
    await uploadWavBytes(fileName: name, wavBytes: sampleBytes);
  }

  Future<void> playWavFile(String remoteFilePath) async {
    try {
      await _deviceRepository.playAudio(remoteFilePath);
      _setStatus('Playing $remoteFilePath');
    } catch (e) {
      _setStatus('Play audio error: $e', isError: true);
    }
    _safeNotifyListeners(markCanvasDirty: false);
  }

  Future<void> stopWavPlayback() async {
    try {
      await _deviceRepository.stopAudio();
      _setStatus('Stopped device audio');
    } catch (e) {
      _setStatus('Stop audio error: $e', isError: true);
    }
    _safeNotifyListeners(markCanvasDirty: false);
  }

  Future<void> deleteWavFile(String remoteFilePath) async {
    try {
      await _deviceRepository.deleteWavFiles([remoteFilePath]);
      _setStatus('Deleted $remoteFilePath');
    } catch (e) {
      _setStatus('Delete file error: $e', isError: true);
    }
    _safeNotifyListeners(markCanvasDirty: false);
  }

  // --- Incoming Physical Device Events ---

  Future<void> _onDeviceEventReceived(Sk18DeviceEvent event) async {
    switch (event.method) {
      case 'keyStateChanged':
        final rawCol = (event.parameters['col'] as num?)?.toInt() ?? 0;
        final rawRow = (event.parameters['row'] as num?)?.toInt() ?? 0;
        final pressed = event.parameters['pressed'] as bool? ?? false;

        // Remap physical portrait coordinates to logical landscape when applicable
        final remapped = Sk18Geometry.remapKeyEvent(
          col: rawCol,
          row: rawRow,
          fromPhysicalDevice: true,
          deviceIsPortrait: _deviceRepository.deviceInfo.isPortrait,
          authoringInLandscape: activeProfile.landscapeMode,
          deviceRectCols: _deviceRepository.deviceInfo.rectCols,
          upsideDown: activeProfile.upsideDown,
        );

        if (pressed) {
          _pressedKeyIndices.add(remapped.index);
          _selectedKeyIndex = remapped.index;
          _safeNotifyListeners();
          final keyCfg = activePage.keys[remapped.index];
          final log = await _actionExecutor.executeKeyAction(keyCfg);
          _setStatus(
            'Physical K${remapped.index + 1}: ${log.summary}',
            isError: !log.success,
          );
          _safeNotifyListeners();
        } else {
          _pressedKeyIndices.remove(remapped.index);
          _safeNotifyListeners();
        }
        break;

      case 'macroTriggered':
        final log = await _actionExecutor.handleFirmwareMacroTriggered(
          event.parameters,
        );
        _setStatus(log.summary, isError: !log.success);
        _safeNotifyListeners();
        break;

      case 'haStateUpdated':
        final updated = _homeAssistantRepository.applyHaStateUpdatedEvent(
          event.parameters,
        );
        _setStatus(
          'HA Telemetry: ${updated.entityId} -> ${updated.state.toUpperCase()}',
        );
        _safeNotifyListeners();
        break;
    }
  }

  void _updateClockString() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _clockString = '$hh:$mm';
  }

  void _safeNotifyListeners({bool markCanvasDirty = true}) {
    if (markCanvasDirty) {
      _pumpDeviceFrameIfNeeded();
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clockTimer?.cancel();
    _clockTimer = null;
    for (final timer in _releaseTimers.values) {
      timer.cancel();
    }
    _releaseTimers.clear();
    _deviceEventSub?.cancel();
    _profileRepository.dispose();
    super.dispose();
  }
}
