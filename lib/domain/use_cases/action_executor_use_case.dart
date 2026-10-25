import '../../data/repositories/device_repository.dart';
import '../../data/repositories/home_assistant_repository.dart';
import '../../data/services/host_launcher_service.dart';
import '../models/button_action.dart';
import '../models/key_button_config.dart';

class ActionExecutionLog {
  final DateTime timestamp;
  final int keyIndex;
  final String keyLabel;
  final ActionCategory category;
  final String summary;
  final bool success;

  const ActionExecutionLog({
    required this.timestamp,
    required this.keyIndex,
    required this.keyLabel,
    required this.category,
    required this.summary,
    this.success = true,
  });
}

/// Hybrid Host + Device Action Execution Router.
/// Dispatches actions across all four categories:
/// 1. Host Launcher (`app`, `script`, `url`)
/// 2. Keyboard & Mouse Macros (`macro_hotkey`, `macro_sequence`, `macro_mouse`)
/// 3. Home Assistant (`ha_toggle`, `ha_brightness_up/down`, `ha_hvac_mode`, `ha_hvac_temp_up/down`)
/// 4. On-Device Audio (`playAudio` on `/data/sound/*.wav`)
class ActionExecutorUseCase {
  final DeviceRepository deviceRepository;
  final HomeAssistantRepository homeAssistantRepository;
  final HostLauncherService hostLauncherService;
  final List<ActionExecutionLog> _logs = <ActionExecutionLog>[];

  ActionExecutorUseCase({
    required this.deviceRepository,
    required this.homeAssistantRepository,
    required this.hostLauncherService,
  });

  List<ActionExecutionLog> get logs => List.unmodifiable(_logs);

  Future<ActionExecutionLog> executeKeyAction(KeyButtonConfig keyConfig) async {
    final action = keyConfig.action;
    try {
      String summary;
      switch (action.category) {
        case ActionCategory.none:
          summary = 'No action bound to ${keyConfig.label}';
          break;

        case ActionCategory.hostLauncher:
          final result = await hostLauncherService.execute(
            launcherType: action.launcherType,
            target: action.target,
            args: action.args,
          );
          summary =
              'Launched ${action.launcherType.jsonValue}: ${action.target} (exit=${result.exitCode})';
          break;

        case ActionCategory.macro:
          summary = await _executeMacroAction(keyConfig);
          break;

        case ActionCategory.homeAssistant:
          final updatedState = await homeAssistantRepository.executeHaAction(
            action,
          );
          summary =
              'HA ${action.haType.jsonValue} -> ${updatedState.entityId} is ${updatedState.state.toUpperCase()}';
          break;

        case ActionCategory.audio:
          await deviceRepository.playAudio(action.audioFilePath);
          summary = 'Playing WAV on SK18: ${action.audioFilePath}';
          break;
      }

      final entry = ActionExecutionLog(
        timestamp: DateTime.now(),
        keyIndex: keyConfig.index,
        keyLabel: keyConfig.label,
        category: action.category,
        summary: summary,
        success: true,
      );
      _recordLog(entry);
      return entry;
    } catch (e) {
      final entry = ActionExecutionLog(
        timestamp: DateTime.now(),
        keyIndex: keyConfig.index,
        keyLabel: keyConfig.label,
        category: action.category,
        summary: 'Failed ${keyConfig.label}: $e',
        success: false,
      );
      _recordLog(entry);
      return entry;
    }
  }

  Future<String> _executeMacroAction(KeyButtonConfig keyConfig) async {
    final action = keyConfig.action;
    switch (action.macroType) {
      case MacroActionType.hotkey:
        final modPrefix = action.modifiers.isEmpty
            ? ''
            : '${action.modifiers.join('+')}+';
        final keyStr =
            '${modPrefix}0x${action.keycode.toRadixString(16).toUpperCase()}';
        if (deviceRepository.isConnected) {
          await deviceRepository.sendKeyboardInput(keyStr);
        }
        return 'Macro Hotkey sent: $keyStr';

      case MacroActionType.sequence:
        final executedParts = <String>[];
        for (final step in action.sequenceSteps) {
          switch (step.type) {
            case MacroStepType.text:
              if (deviceRepository.isConnected && step.value.isNotEmpty) {
                await deviceRepository.sendKeyboardInput(step.value);
              }
              executedParts.add('"${step.value}"');
              break;
            case MacroStepType.keyTap:
              if (deviceRepository.isConnected && step.value.isNotEmpty) {
                await deviceRepository.sendKeyboardInput('<${step.value}>');
              }
              executedParts.add('[${step.value}]');
              break;
            case MacroStepType.delayMs:
              final ms = step.delayMilliseconds.clamp(0, 200);
              if (ms > 0) {
                await Future<void>.delayed(Duration(milliseconds: ms));
              }
              executedParts.add('${step.delayMilliseconds}ms');
              break;
          }
        }
        return 'Macro Sequence: ${executedParts.join(' -> ')}';

      case MacroActionType.mouse:
        if (deviceRepository.isConnected) {
          await deviceRepository.rpcClient.triggerKeyAction(
            col: keyConfig.col,
            row: keyConfig.row,
            pressed: true,
          );
        }
        return 'Macro Mouse: btn=${action.mouseButtons} dx=${action.mouseDx} dy=${action.mouseDy} wheelV=${action.wheelV}';
    }
  }

  /// Handles unsolicited `macroTriggered` events emitted by custom SK18 firmware.
  Future<ActionExecutionLog> handleFirmwareMacroTriggered(
    Map<String, dynamic> params,
  ) async {
    final index = (params['index'] as num?)?.toInt() ?? 0;
    final label = (params['label'] as String?) ?? 'Key ${index + 1}';
    final launcherType = HostLauncherType.fromString(
      params['launcherType'] as String?,
    );
    final target = (params['target'] as String?) ?? '';
    final rawArgs = params['args'];
    final args = rawArgs is List
        ? rawArgs.map((e) => e.toString()).toList()
        : const <String>[];

    final res = await hostLauncherService.execute(
      launcherType: launcherType,
      target: target,
      args: args,
    );
    final log = ActionExecutionLog(
      timestamp: DateTime.now(),
      keyIndex: index,
      keyLabel: label,
      category: ActionCategory.hostLauncher,
      summary:
          'Firmware macroTriggered -> ${launcherType.jsonValue}: $target (exit=${res.exitCode})',
      success: res.exitCode == 0,
    );
    _recordLog(log);
    return log;
  }

  void _recordLog(ActionExecutionLog log) {
    _logs.insert(0, log);
    if (_logs.length > 50) {
      _logs.removeRange(50, _logs.length);
    }
  }
}
