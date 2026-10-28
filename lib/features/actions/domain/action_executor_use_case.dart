import '../../device/data/device_repository.dart';
import '../../home_assistant/data/home_assistant_repository.dart';
import '../data/host_launcher_service.dart';
import 'action_plugin.dart';
import 'action_plugin_registry.dart';
import 'button_action.dart';
import '../../profiles/domain/key_button_config.dart';

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
      final summary = await ActionPluginRegistry.instance
          .forCategory(action.category)
          .execute(
            ActionExecutionContext(
              keyConfig: keyConfig,
              deviceRepository: deviceRepository,
              homeAssistantRepository: homeAssistantRepository,
              hostLauncherService: hostLauncherService,
            ),
          );

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
