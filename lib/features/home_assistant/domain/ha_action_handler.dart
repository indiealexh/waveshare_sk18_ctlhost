import 'dart:ui' show Canvas;

import '../../actions/domain/action_plugin.dart';
import '../../actions/domain/button_action.dart';
import 'ha_entity_state.dart';

class HaServiceCall {
  final String domain;
  final String service;
  final Map<String, dynamic> data;
  final HaEntityState nextState;

  const HaServiceCall({
    required this.domain,
    required this.service,
    required this.data,
    required this.nextState,
  });
}

abstract class HaActionHandler {
  const HaActionHandler();

  HaActionType get type;

  double get defaultStep;

  HaServiceCall plan(
    ButtonAction action,
    HaEntityState existing,
    String domain,
  );

  String pillText(HaEntityState state);

  void paintOverlay(Canvas canvas, KeyTelemetryPaintContext context) {}
}
