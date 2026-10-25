import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavectl_host/data/services/env_config_loader.dart';
import 'package:wavectl_host/data/services/home_assistant_service.dart';
import 'package:wavectl_host/domain/models/button_action.dart';
import 'package:wavectl_host/domain/models/ha_entity_state.dart';

void main() {
  group('EnvConfigLoader & HomeAssistantService', () {
    test('parses HOME_ASSISTANT_BASE_URL and HOME_ASSISTANT_TOKEN from .env text', () {
      const envText = '''
# Home Assistant config
export HOME_ASSISTANT_BASE_URL="http://192.168.1.10:8123/"
HOME_ASSISTANT_TOKEN='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
''';
      final parsed = EnvConfigLoader.parseEnvString(envText);
      expect(
        parsed[EnvConfigLoader.baseUrlKey],
        equals('http://192.168.1.10:8123/'),
      );
      expect(
        parsed[EnvConfigLoader.tokenKey],
        equals('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'),
      );
    });

    test('gracefully returns empty credentials when .env file is missing', () async {
      final creds = await EnvConfigLoader.loadFromFile(
        filePath: '/non/existent/path/.env',
      );
      expect(creds.hasCredentials, isFalse);
      expect(creds.baseUrl, isEmpty);
      expect(creds.token, isEmpty);
    });

    test('fetches filtered entity states and dispatches toggle, brightness, and HVAC services', () async {
      final capturedRequests = <http.Request>[];
      final mockClient = MockClient((request) async {
        capturedRequests.add(request);
        if (request.url.path == '/api/states') {
          return http.Response(
            jsonEncode([
              {
                'entity_id': 'light.office_main',
                'state': 'on',
                'attributes': {
                  'friendly_name': 'Office Light',
                  'brightness': 128,
                },
              },
              {
                'entity_id': 'climate.studio_hvac',
                'state': 'cool',
                'attributes': {
                  'friendly_name': 'Studio AC',
                  'current_temperature': 21.5,
                  'temperature': 22.0,
                  'hvac_modes': ['off', 'heat', 'cool', 'auto'],
                },
              },
              {
                'entity_id': 'person.alice',
                'state': 'home',
                'attributes': {},
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final service = HomeAssistantService(
        httpClient: mockClient,
        baseUrl: 'ws://homeassistant.local:8123/api/websocket',
        token: 'test-token-123',
      );

      expect(service.baseUrl, equals('http://homeassistant.local:8123'));

      final states = await service.fetchEntityStates();
      expect(states.length, equals(2));
      expect(states.first.entityId, equals('light.office_main'));
      expect(states.first.brightnessPct, equals(50));

      // 1. Toggle light off
      final toggled = await service.executeAction(
        action: const ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.toggle,
          entityId: 'light.office_main',
        ),
        currentState: states.first,
      );
      expect(toggled.state, equals('off'));
      expect(service.callHistory.last.domain, equals('homeassistant'));
      expect(service.callHistory.last.service, equals('toggle'));

      // 2. Brightness up +15%
      final brightened = await service.executeAction(
        action: const ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.brightnessUp,
          entityId: 'light.office_main',
          step: 15,
        ),
        currentState: states.first,
      );
      expect(brightened.brightnessPct, equals(65));
      expect(service.callHistory.last.domain, equals('light'));
      expect(service.callHistory.last.service, equals('turn_on'));
      expect(
        service.callHistory.last.serviceData['brightness_step_pct'],
        equals(15),
      );

      // 3. HVAC temp up +0.5
      final climateState = states[1];
      final tempRaised = await service.executeAction(
        action: const ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.hvacTempUp,
          entityId: 'climate.studio_hvac',
          step: 0.5,
        ),
        currentState: climateState,
      );
      expect(tempRaised.targetTemperature, equals(22.5));
      expect(service.callHistory.last.domain, equals('climate'));
      expect(service.callHistory.last.service, equals('set_temperature'));

      // 4. HVAC mode cycle (cool -> auto)
      final modeCycled = await service.executeAction(
        action: const ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.hvacMode,
          entityId: 'climate.studio_hvac',
        ),
        currentState: HaEntityState(
          entityId: 'climate.studio_hvac',
          domain: 'climate',
          friendlyName: 'Studio AC',
          state: 'cool',
          attributes: const {
            'hvac_modes': ['off', 'heat', 'cool', 'auto'],
          },
        ),
      );
      expect(modeCycled.state, equals('auto'));
      expect(capturedRequests.length, equals(5));
    });
  });
}
