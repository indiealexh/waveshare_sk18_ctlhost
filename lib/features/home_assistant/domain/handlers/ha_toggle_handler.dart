import '../../../actions/domain/button_action.dart';
import '../ha_action_handler.dart';
import '../ha_entity_state.dart';

class HaToggleHandler extends HaActionHandler {
  @override
  HaActionType get type => HaActionType.toggle;

  @override
  double get defaultStep => 10.0;

  @override
  HaServiceCall plan(
    ButtonAction action,
    HaEntityState existing,
    String domain,
  ) {
    if (domain == 'scene' || domain == 'script') {
      return HaServiceCall(
        domain: domain,
        service: 'turn_on',
        data: {'entity_id': action.entityId},
        nextState: existing.copyWith(state: 'on'),
      );
    }
    return HaServiceCall(
      domain: 'homeassistant',
      service: 'toggle',
      data: {'entity_id': action.entityId},
      nextState: existing.copyWith(state: existing.isOn ? 'off' : 'on'),
    );
  }

  @override
  String pillText(HaEntityState state) => state.isOn ? 'ON' : 'OFF';
}
