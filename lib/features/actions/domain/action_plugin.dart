import 'dart:ui' show Canvas, Color, Rect;

import 'package:flutter/widgets.dart' show BuildContext, Widget;

import '../../device/data/device_repository.dart';
import '../../home_assistant/data/home_assistant_repository.dart';
import '../../home_assistant/domain/ha_entity_state.dart';
import '../../profiles/domain/key_button_config.dart';
import '../../studio/presentation/studio_view_model.dart';
import '../data/host_launcher_service.dart';
import 'button_action.dart';

class ActionExecutionContext {
  final KeyButtonConfig keyConfig;
  final DeviceRepository deviceRepository;
  final HomeAssistantRepository homeAssistantRepository;
  final HostLauncherService hostLauncherService;

  const ActionExecutionContext({
    required this.keyConfig,
    required this.deviceRepository,
    required this.homeAssistantRepository,
    required this.hostLauncherService,
  });
}

class ActionEditorScope {
  final StudioViewModel vm;
  final KeyButtonConfig keyConfig;

  const ActionEditorScope({required this.vm, required this.keyConfig});

  ButtonAction get action => keyConfig.action;

  void update(ButtonAction action) => vm.updateSelectedKeyAction(action);
}

class KeyTelemetryPaintContext {
  final Rect baseRect;
  final ButtonAction action;
  final HaEntityState? haState;
  final Color accentColor;

  const KeyTelemetryPaintContext({
    required this.baseRect,
    required this.action,
    required this.haState,
    required this.accentColor,
  });
}

abstract class ActionPlugin {
  ActionCategory get category;

  bool matchesJson(Map<String, dynamic> json);

  ButtonAction readFields(Map<String, dynamic> json, ButtonAction acc);

  Map<String, dynamic> toJson(ButtonAction action);

  String summaryBadge(ButtonAction action);

  Future<String> execute(ActionExecutionContext context);

  Widget buildEditor(BuildContext context, ActionEditorScope scope);

  String? topRightPill(ButtonAction action, HaEntityState? state) => null;

  void paintKeyTelemetry(Canvas canvas, KeyTelemetryPaintContext context) {}
}
