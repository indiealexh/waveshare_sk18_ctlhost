import '../../actions/domain/button_action.dart';
import 'ha_action_handler.dart';
import 'handlers/ha_brightness_step_handler.dart';
import 'handlers/ha_hvac_mode_handler.dart';
import 'handlers/ha_hvac_temp_step_handler.dart';
import 'handlers/ha_toggle_handler.dart';

class HaActionHandlerRegistry {
  static HaActionHandlerRegistry? _instance;

  static HaActionHandlerRegistry get instance =>
      _instance ??= HaActionHandlerRegistry.defaults();

  static set instance(HaActionHandlerRegistry registry) =>
      _instance = registry;

  final List<HaActionHandler> ordered;
  final Map<HaActionType, HaActionHandler> _byType;

  HaActionHandlerRegistry({required List<HaActionHandler> ordered})
    : ordered = List.unmodifiable(ordered),
      _byType = Map.unmodifiable(<HaActionType, HaActionHandler>{
        for (final handler in ordered) handler.type: handler,
      });

  factory HaActionHandlerRegistry.defaults() {
    return HaActionHandlerRegistry(
      ordered: [
        HaToggleHandler(),
        const HaBrightnessStepHandler(sign: 1),
        const HaBrightnessStepHandler(sign: -1),
        HaHvacModeHandler(),
        const HaHvacTempStepHandler(sign: 1),
        const HaHvacTempStepHandler(sign: -1),
      ],
    );
  }

  HaActionHandler forType(HaActionType type) {
    final handler = _byType[type];
    if (handler == null) {
      throw StateError('No Home Assistant action handler registered for $type.');
    }
    return handler;
  }
}
