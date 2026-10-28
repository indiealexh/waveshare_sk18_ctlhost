import 'dart:ui' show Canvas, Color, Paint, Radius, Rect, RRect;

import '../../../actions/domain/button_action.dart';
import '../../../actions/domain/action_plugin.dart';
import '../ha_action_handler.dart';
import '../ha_entity_state.dart';

class HaBrightnessStepHandler extends HaActionHandler {
  final int sign;

  const HaBrightnessStepHandler({required this.sign});

  @override
  HaActionType get type => sign > 0
      ? HaActionType.brightnessUp
      : HaActionType.brightnessDown;

  @override
  double get defaultStep => 10.0;

  @override
  HaServiceCall plan(
    ButtonAction action,
    HaEntityState existing,
    String domain,
  ) {
    final signedStep = sign > 0 ? action.step.round() : -action.step.round();
    final currentPct = existing.brightnessPct ?? (existing.isOn ? 100 : 0);
    final updatedPct = (currentPct + signedStep).clamp(0, 100);
    final updatedRawBrightness = ((updatedPct / 100.0) * 255.0).round();

    return HaServiceCall(
      domain: 'light',
      service: 'turn_on',
      data: {
        'entity_id': action.entityId,
        'brightness_step_pct': signedStep,
      },
      nextState: existing.copyWith(
        state: updatedPct > 0 ? 'on' : 'off',
        attributes: {
          ...existing.attributes,
          'brightness': updatedRawBrightness,
          'brightness_pct': updatedPct,
        },
      ),
    );
  }

  @override
  String pillText(HaEntityState state) => '${state.brightnessPct ?? 0}%';

  @override
  void paintOverlay(Canvas canvas, KeyTelemetryPaintContext context) {
    final baseRect = context.baseRect;
    final pct = (context.haState?.brightnessPct ?? 50).clamp(0, 100);
    final isCompactTile = baseRect.height <= 144.0;
    final barY = baseRect.bottom - (isCompactTile ? 44 : 50);
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(baseRect.left + 18, barY, baseRect.width - 36, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(trackRect, Paint()..color = const Color(0xFF0F172A));
    final fillWidth = ((baseRect.width - 36) * (pct / 100.0)).clamp(
      0.0,
      baseRect.width - 36,
    );
    if (fillWidth > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(baseRect.left + 18, barY, fillWidth, 8),
        const Radius.circular(4),
      );
      canvas.drawRRect(fillRect, Paint()..color = context.accentColor);
    }
  }
}
