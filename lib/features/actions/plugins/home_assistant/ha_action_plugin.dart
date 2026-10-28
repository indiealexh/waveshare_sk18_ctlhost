import 'package:flutter/material.dart';

import '../../../home_assistant/domain/ha_entity_state.dart';
import '../../../home_assistant/domain/ha_action_handler_registry.dart';
import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';
import 'ha_action_editor.dart';

class HomeAssistantActionPlugin extends ActionPlugin {
  @override
  ActionCategory get category => ActionCategory.homeAssistant;

  @override
  bool matchesJson(Map<String, dynamic> json) {
    final rawCategory = json['category'];
    return rawCategory == 'ha' ||
        rawCategory == 'homeAssistant' ||
        rawCategory == 'home_assistant';
  }

  @override
  ButtonAction readFields(Map<String, dynamic> json, ButtonAction acc) {
    final rawHvacModes = json['hvacModes'];
    final hvacModes = rawHvacModes is List
        ? rawHvacModes.map((value) => value.toString()).toList()
        : const <String>['off', 'heat', 'cool', 'auto'];
    final haType = HaActionType.fromString(json['haType'] as String?);
    final defaultStep = HaActionHandlerRegistry.instance
        .forType(haType)
        .defaultStep;

    return acc.copyWith(
      haType: haType,
      entityId: (json['entityId'] as String?) ?? '',
      step: (json['step'] as num?)?.toDouble() ?? defaultStep,
      targetHvacMode: json['targetHvacMode'] as String?,
      hvacModes: hvacModes,
    );
  }

  @override
  Map<String, dynamic> toJson(ButtonAction action) => {
    'category': 'ha',
    'haType': action.haType.jsonValue,
    'entityId': action.entityId,
    'step': action.step,
    if (action.targetHvacMode != null)
      'targetHvacMode': action.targetHvacMode,
    'hvacModes': action.hvacModes,
  };

  @override
  String summaryBadge(ButtonAction action) => 'HA';

  @override
  String? topRightPill(ButtonAction action, HaEntityState? state) {
    if (state == null) return null;
    return HaActionHandlerRegistry.instance
        .forType(action.haType)
        .pillText(state);
  }

  @override
  void paintKeyTelemetry(Canvas canvas, KeyTelemetryPaintContext context) {
    HaActionHandlerRegistry.instance
        .forType(context.action.haType)
        .paintOverlay(canvas, context);
  }

  @override
  Future<String> execute(ActionExecutionContext context) async {
    final action = context.keyConfig.action;
    final updatedState = await context.homeAssistantRepository.executeHaAction(
      action,
    );
    return 'HA ${action.haType.jsonValue} -> ${updatedState.entityId} is ${updatedState.state.toUpperCase()}';
  }

  @override
  Widget buildEditor(BuildContext context, ActionEditorScope scope) =>
      HaActionEditor(scope: scope);
}
