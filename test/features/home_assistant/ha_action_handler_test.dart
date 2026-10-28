import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/features/actions/domain/button_action.dart';
import 'package:wavectl_host/features/home_assistant/domain/ha_action_handler_registry.dart';
import 'package:wavectl_host/features/home_assistant/domain/ha_entity_state.dart';

void main() {
  group('HaActionHandlerRegistry', () {
    final registry = HaActionHandlerRegistry.instance;

    test('provides one handler per HA action type with type defaults', () {
      expect(
        registry.ordered.map((handler) => handler.type).toList(),
        HaActionType.values,
      );
      expect(
        registry.ordered.map((handler) => handler.defaultStep).toList(),
        [10.0, 10.0, 10.0, 10.0, 0.5, 0.5],
      );
    });

    test('toggle plans normal entity toggles and scene/script activation', () {
      final light = HaEntityState(
        entityId: 'light.office_main',
        domain: 'light',
        friendlyName: 'Office Light',
        state: 'on',
      );
      final toggle = registry.forType(HaActionType.toggle);
      final lightCall = toggle.plan(
        const ButtonAction(haType: HaActionType.toggle, entityId: 'light.office_main'),
        light,
        'light',
      );
      expect(lightCall.domain, 'homeassistant');
      expect(lightCall.service, 'toggle');
      expect(lightCall.data, {'entity_id': 'light.office_main'});
      expect(lightCall.nextState.state, 'off');
      expect(toggle.pillText(light), 'ON');

      final sceneCall = toggle.plan(
        const ButtonAction(haType: HaActionType.toggle, entityId: 'scene.focus'),
        const HaEntityState(
          entityId: 'scene.focus',
          domain: 'scene',
          friendlyName: 'Focus',
          state: 'scening',
        ),
        'scene',
      );
      expect(sceneCall.domain, 'scene');
      expect(sceneCall.service, 'turn_on');
      expect(sceneCall.nextState.state, 'on');
    });

    test('brightness handlers plan signed steps and clamped optimistic state', () {
      const light = HaEntityState(
        entityId: 'light.office_main',
        domain: 'light',
        friendlyName: 'Office Light',
        state: 'on',
        attributes: {'brightness_pct': 50},
      );
      final action = const ButtonAction(
        category: ActionCategory.homeAssistant,
        haType: HaActionType.brightnessUp,
        entityId: 'light.office_main',
        step: 15,
      );
      final upCall = registry
          .forType(HaActionType.brightnessUp)
          .plan(action, light, 'light');
      expect(upCall.domain, 'light');
      expect(upCall.service, 'turn_on');
      expect(upCall.data['brightness_step_pct'], 15);
      expect(upCall.nextState.brightnessPct, 65);
      expect(
        registry
            .forType(HaActionType.brightnessUp)
            .pillText(upCall.nextState),
        '65%',
      );

      final downCall = registry
          .forType(HaActionType.brightnessDown)
          .plan(action.copyWith(haType: HaActionType.brightnessDown), light, 'light');
      expect(downCall.data['brightness_step_pct'], -15);
      expect(downCall.nextState.brightnessPct, 35);
    });

    test('HVAC mode handler cycles modes and honors explicit target mode', () {
      const climate = HaEntityState(
        entityId: 'climate.studio_hvac',
        domain: 'climate',
        friendlyName: 'Studio AC',
        state: 'cool',
        attributes: {
          'hvac_modes': ['off', 'heat', 'cool', 'auto'],
        },
      );
      final handler = registry.forType(HaActionType.hvacMode);
      final cycleCall = handler.plan(
        const ButtonAction(haType: HaActionType.hvacMode),
        climate,
        'climate',
      );
      expect(cycleCall.domain, 'climate');
      expect(cycleCall.service, 'set_hvac_mode');
      expect(cycleCall.data['hvac_mode'], 'auto');
      expect(cycleCall.nextState.state, 'auto');
      expect(handler.pillText(climate), 'COOL');

      final targetCall = handler.plan(
        const ButtonAction(
          haType: HaActionType.hvacMode,
          targetHvacMode: ' heat ',
        ),
        climate,
        'climate',
      );
      expect(targetCall.data['hvac_mode'], 'heat');
    });

    test('HVAC temperature handlers clamp and round service payloads', () {
      const climate = HaEntityState(
        entityId: 'climate.studio_hvac',
        domain: 'climate',
        friendlyName: 'Studio AC',
        state: 'cool',
        attributes: {
          'temperature': 22.0,
          'min_temp': 16.0,
          'max_temp': 30.0,
        },
      );
      const upAction = ButtonAction(
        haType: HaActionType.hvacTempUp,
        step: 0.5,
      );
      final upCall = registry
          .forType(HaActionType.hvacTempUp)
          .plan(upAction, climate, 'climate');
      expect(upCall.domain, 'climate');
      expect(upCall.service, 'set_temperature');
      expect(upCall.data['temperature'], 22.5);
      expect(upCall.nextState.targetTemperature, 22.5);
      expect(
        registry.forType(HaActionType.hvacTempUp).pillText(climate),
        'COOL',
      );

      final downCall = registry
          .forType(HaActionType.hvacTempDown)
          .plan(upAction.copyWith(haType: HaActionType.hvacTempDown), climate, 'climate');
      expect(downCall.data['temperature'], 21.5);
    });
  });
}
