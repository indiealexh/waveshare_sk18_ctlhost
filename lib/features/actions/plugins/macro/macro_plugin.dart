import 'package:flutter/material.dart';

import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';
import 'macro_editor.dart';

class MacroPlugin extends ActionPlugin {
  @override
  ActionCategory get category => ActionCategory.macro;

  @override
  bool matchesJson(Map<String, dynamic> json) => json['category'] == 'macro';

  @override
  ButtonAction readFields(Map<String, dynamic> json, ButtonAction acc) {
    final rawModifiers = json['modifiers'];
    final rawSteps = json['sequenceSteps'] ?? json['steps'];
    final sequenceSteps = rawSteps is List
        ? rawSteps
              .whereType<Map<String, dynamic>>()
              .map(MacroStep.fromJson)
              .toList()
        : const <MacroStep>[];

    return acc.copyWith(
      macroType: MacroActionType.fromString(json['macroType'] as String?),
      keycode: (json['keycode'] as num?)?.toInt() ?? 0x0004,
      modifiers: rawModifiers is List
          ? rawModifiers.map((value) => value.toString()).toList()
          : const <String>[],
      consumerCode: (json['consumerCode'] as num?)?.toInt(),
      sequenceSteps: sequenceSteps,
      mouseButtons:
          (json['mouseButtons'] as num? ?? json['buttons'] as num?)?.toInt() ??
          1,
      mouseDx:
          (json['mouseDx'] as num? ?? json['dx'] as num?)?.toInt() ?? 0,
      mouseDy:
          (json['mouseDy'] as num? ?? json['dy'] as num?)?.toInt() ?? 0,
      wheelV: (json['wheelV'] as num?)?.toInt() ?? 0,
      wheelH: (json['wheelH'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson(ButtonAction action) => {
    'category': 'macro',
    'macroType': action.macroType.jsonValue,
    'keycode': action.keycode,
    'modifiers': action.modifiers,
    if (action.consumerCode != null) 'consumerCode': action.consumerCode,
    'steps': action.sequenceSteps.map((step) => step.toJson()).toList(),
    'sequenceSteps': action.sequenceSteps.map((step) => step.toJson()).toList(),
    'buttons': action.mouseButtons,
    'mouseButtons': action.mouseButtons,
    'dx': action.mouseDx,
    'mouseDx': action.mouseDx,
    'dy': action.mouseDy,
    'mouseDy': action.mouseDy,
    'wheelV': action.wheelV,
    'wheelH': action.wheelH,
  };

  @override
  String summaryBadge(ButtonAction action) {
    switch (action.macroType) {
      case MacroActionType.hotkey:
        return action.modifiers.isEmpty ? 'KEY' : action.modifiers.join('+');
      case MacroActionType.sequence:
        return 'SEQ(${action.sequenceSteps.length})';
      case MacroActionType.mouse:
        return 'MOUSE';
    }
  }

  @override
  Future<String> execute(ActionExecutionContext context) async {
    final keyConfig = context.keyConfig;
    final action = keyConfig.action;
    final deviceRepository = context.deviceRepository;

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

  @override
  Widget buildEditor(BuildContext context, ActionEditorScope scope) =>
      MacroEditor(scope: scope);
}
