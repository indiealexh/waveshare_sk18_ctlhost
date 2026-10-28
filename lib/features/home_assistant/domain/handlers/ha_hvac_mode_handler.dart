import '../../../actions/domain/button_action.dart';
import '../ha_action_handler.dart';
import '../ha_entity_state.dart';
import 'ha_hvac_temp_step_handler.dart';

class HaHvacModeHandler extends HaActionHandler with HaTemperatureOverlay {
  @override
  HaActionType get type => HaActionType.hvacMode;

  @override
  double get defaultStep => 10.0;

  @override
  HaServiceCall plan(
    ButtonAction action,
    HaEntityState existing,
    String domain,
  ) {
    final modes = existing.hvacModes.isNotEmpty
        ? existing.hvacModes
        : action.hvacModes;
    final String chosenMode;
    if (action.targetHvacMode != null &&
        action.targetHvacMode!.trim().isNotEmpty) {
      chosenMode = action.targetHvacMode!.trim();
    } else {
      final index = modes.indexOf(existing.state);
      chosenMode = modes[(index + 1) % modes.length];
    }

    return HaServiceCall(
      domain: 'climate',
      service: 'set_hvac_mode',
      data: {'entity_id': action.entityId, 'hvac_mode': chosenMode},
      nextState: existing.copyWith(state: chosenMode),
    );
  }

  @override
  String pillText(HaEntityState state) => state.state.toUpperCase();
}
