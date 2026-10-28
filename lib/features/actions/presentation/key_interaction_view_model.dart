// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../../core/models/sk18_geometry.dart';
import '../../../core/protocol/sk18_rpc_client.dart';
import '../../device/data/device_repository.dart';
import '../../profiles/domain/key_button_config.dart';
import '../../profiles/presentation/profile_editor_view_model.dart';
import '../../studio/presentation/studio_session.dart';
import '../domain/action_executor_use_case.dart';

class KeyInteractionViewModel extends StudioSubViewModel {
  final ProfileEditorViewModel _profiles;
  final DeviceRepository _deviceRepository;
  final ActionExecutorUseCase _actionExecutor;
  final Map<int, Timer> _releaseTimers = <int, Timer>{};
  final Set<int> _pressedKeyIndices = <int>{};
  int _selectedKeyIndex = 0;
  bool _interactiveTriggerOnTap;

  KeyInteractionViewModel({
    required StudioSession session,
    required ProfileEditorViewModel profiles,
    required DeviceRepository deviceRepository,
    required ActionExecutorUseCase actionExecutor,
    required bool initialInteractiveTriggerOnTap,
  }) : _profiles = profiles,
       _deviceRepository = deviceRepository,
       _actionExecutor = actionExecutor,
       _interactiveTriggerOnTap = initialInteractiveTriggerOnTap,
       super(session);

  int get selectedKeyIndex => _selectedKeyIndex;
  Set<int> get pressedKeyIndices => Set.unmodifiable(_pressedKeyIndices);
  bool get interactiveTriggerOnTap => _interactiveTriggerOnTap;
  KeyButtonConfig get selectedKeyConfig =>
      _profiles.activePage.keys[_selectedKeyIndex.clamp(
        0,
        _profiles.activePage.keys.length - 1,
      )];
  List<ActionExecutionLog> get executionLogs => _actionExecutor.logs;

  void restoreInteractiveTriggerOnTap(bool value) {
    _interactiveTriggerOnTap = value;
  }

  void resetSelection({bool notifyChange = true}) {
    _selectedKeyIndex = 0;
    if (notifyChange) notify(markCanvasDirty: false);
  }

  void clampSelection(int keyCount) {
    _selectedKeyIndex = _selectedKeyIndex.clamp(0, keyCount - 1);
  }

  void setInteractiveTriggerOnTap(bool value, {bool notifyChange = true}) {
    _interactiveTriggerOnTap = value;
    _profiles.setInteractiveTriggerOnTap(value);
    if (notifyChange) notify(markCanvasDirty: false);
  }

  void selectKey(int index, {bool notifyChange = true}) {
    if (index < 0 || index >= _profiles.activePage.keys.length) return;
    _selectedKeyIndex = index;
    if (notifyChange) notify(markCanvasDirty: false);
  }

  Future<void> handleCanvasKeyTap(int index) async {
    selectKey(index);
    if (_interactiveTriggerOnTap) {
      await triggerKeyByIndex(index, fromPhysicalDevice: false);
    }
  }

  void updateSelectedKeyConfig(KeyButtonConfig updatedKey) {
    _profiles.updateKeyConfig(
      _selectedKeyIndex,
      updatedKey,
      notifyChange: false,
    );
    notify();
  }

  Future<ActionExecutionLog> triggerKeyByIndex(
    int index, {
    bool fromPhysicalDevice = false,
  }) async {
    final safeIdx = index.clamp(0, _profiles.activePage.keys.length - 1);
    final keyConfig = _profiles.activePage.keys[safeIdx];

    _pressedKeyIndices.add(safeIdx);
    _releaseTimers[safeIdx]?.cancel();
    _releaseTimers[safeIdx] = Timer(const Duration(milliseconds: 180), () {
      _pressedKeyIndices.remove(safeIdx);
      _releaseTimers.remove(safeIdx);
      notify();
    });
    notify();

    final log = await _actionExecutor.executeKeyAction(keyConfig);
    session.setStatus(log.summary, isError: !log.success);
    notify();
    return log;
  }

  Future<ActionExecutionLog> triggerSelectedKey() =>
      triggerKeyByIndex(_selectedKeyIndex, fromPhysicalDevice: false);

  Future<void> handleKeyStateChanged(Sk18DeviceEvent event) async {
    final rawCol = (event.parameters['col'] as num?)?.toInt() ?? 0;
    final rawRow = (event.parameters['row'] as num?)?.toInt() ?? 0;
    final pressed = event.parameters['pressed'] as bool? ?? false;
    final activeProfile = _profiles.activeProfile;
    final activePage = _profiles.activePage;
    final deviceInfo = _deviceRepository.deviceInfo;
    final remapped = Sk18Geometry.remapKeyEvent(
      col: rawCol,
      row: rawRow,
      fromPhysicalDevice: true,
      deviceIsPortrait: deviceInfo.isPortrait,
      authoringInLandscape: activeProfile.landscapeMode,
      deviceRectCols: deviceInfo.rectCols,
      upsideDown: activeProfile.upsideDown,
      model: activeProfile.deviceModel,
    );
    final keyIndex = remapped.index.clamp(0, activePage.keys.length - 1);

    if (pressed) {
      _pressedKeyIndices.add(keyIndex);
      _selectedKeyIndex = keyIndex;
      notify();
      final keyConfig = activePage.keys[keyIndex];
      final log = await _actionExecutor.executeKeyAction(keyConfig);
      session.setStatus(
        'Physical K${keyIndex + 1}: ${log.summary}',
        isError: !log.success,
      );
      notify();
    } else {
      _pressedKeyIndices.remove(keyIndex);
      notify();
    }
  }

  Future<void> handleMacroTriggered(Map<String, dynamic> parameters) async {
    final log = await _actionExecutor.handleFirmwareMacroTriggered(parameters);
    session.setStatus(log.summary, isError: !log.success);
    notify();
  }

  @override
  void dispose() {
    for (final timer in _releaseTimers.values) {
      timer.cancel();
    }
    _releaseTimers.clear();
    super.dispose();
  }
}
