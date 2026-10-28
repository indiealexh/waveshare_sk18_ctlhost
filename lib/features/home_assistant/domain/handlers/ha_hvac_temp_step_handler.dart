import 'package:flutter/material.dart';

import '../../../actions/domain/action_plugin.dart';
import '../../../actions/domain/button_action.dart';
import '../ha_action_handler.dart';
import '../ha_entity_state.dart';

class HaHvacTempStepHandler extends HaActionHandler with HaTemperatureOverlay {
  final int sign;

  const HaHvacTempStepHandler({required this.sign});

  @override
  HaActionType get type =>
      sign > 0 ? HaActionType.hvacTempUp : HaActionType.hvacTempDown;

  @override
  double get defaultStep => 0.5;

  @override
  HaServiceCall plan(
    ButtonAction action,
    HaEntityState existing,
    String domain,
  ) {
    final delta = sign > 0 ? action.step : -action.step;
    final currentTarget = existing.targetTemperature ?? 21.0;
    final newTarget = (currentTarget + delta).clamp(
      existing.minTemp,
      existing.maxTemp,
    );
    final roundedTarget = double.parse(newTarget.toStringAsFixed(1));
    return HaServiceCall(
      domain: 'climate',
      service: 'set_temperature',
      data: {'entity_id': action.entityId, 'temperature': roundedTarget},
      nextState: existing.copyWith(
        state: existing.state == 'off' ? 'heat' : existing.state,
        attributes: {...existing.attributes, 'temperature': roundedTarget},
      ),
    );
  }

  @override
  String pillText(HaEntityState state) => state.state.toUpperCase();
}

mixin HaTemperatureOverlay on HaActionHandler {
  @override
  void paintOverlay(Canvas canvas, KeyTelemetryPaintContext context) {
    final baseRect = context.baseRect;
    final current = context.haState?.currentTemperature;
    final target = context.haState?.targetTemperature;
    if (current == null && target == null) return;

    final isCompactTile = baseRect.height <= 144.0;
    final tempLabel =
        '${current?.toStringAsFixed(1) ?? '--'}° → ${target?.toStringAsFixed(1) ?? '--'}°';
    final painter = TextPainter(
      text: TextSpan(
        text: tempLabel,
        style: TextStyle(
          color: context.accentColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: baseRect.width - 20, maxWidth: baseRect.width - 20);
    painter.paint(
      canvas,
      Offset(baseRect.left + 10, baseRect.bottom - (isCompactTile ? 48 : 54)),
    );
  }
}
