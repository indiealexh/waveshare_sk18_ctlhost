
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/features/profiles/data/profile_repository.dart';
import 'package:wavectl_host/features/actions/domain/button_action.dart';

void main() {
  test('studio config JSON matches the characterization fixture byte-for-byte', () async {
    final expected = await File(
      'test/fixtures/studio_config_golden.json',
    ).readAsString();

    expect(jsonEncode(ProfileRepository().toStudioConfigJson()), expected);
  });

  test('action aliases and legacy keys normalize consistently', () {
    final cases = <Map<String, dynamic>>[
      {
        'json': {'category': 'host_launcher', 'target': 'Terminal'},
        'category': ActionCategory.hostLauncher,
      },
      {
        'json': {'category': 'hostLauncher', 'target': 'Terminal'},
        'category': ActionCategory.hostLauncher,
      },
      {
        'json': {
          'category': 'macro',
          'macroType': 'macro_host_launcher',
          'target': 'Terminal',
        },
        'category': ActionCategory.hostLauncher,
      },
      {
        'json': {'category': 'ha', 'haType': 'toggle'},
        'category': ActionCategory.homeAssistant,
      },
      {
        'json': {'category': 'homeAssistant', 'haType': 'toggle'},
        'category': ActionCategory.homeAssistant,
      },
      {
        'json': {'category': 'home_assistant', 'haType': 'toggle'},
        'category': ActionCategory.homeAssistant,
      },
      {
        'json': {'category': 'audio', 'filePath': '/data/sound/legacy.wav'},
        'category': ActionCategory.audio,
      },
      {
        'json': {
          'category': 'macro',
          'macroType': 'macro_mouse',
          'steps': [
            {'type': 'text', 'value': 'legacy'},
          ],
          'buttons': 4,
          'dx': -2,
          'dy': 3,
        },
        'category': ActionCategory.macro,
      },
    ];

    for (final testCase in cases) {
      final action = ButtonAction.fromJson(
        testCase['json'] as Map<String, dynamic>,
      );
      expect(action.category, testCase['category']);

      final normalized = action.toJson();
      expect(ButtonAction.fromJson(normalized).toJson(), normalized);
    }

    final legacyMacro = ButtonAction.fromJson(cases.last['json'] as Map<String, dynamic>);
    expect(legacyMacro.sequenceSteps.single.value, 'legacy');
    expect(legacyMacro.mouseButtons, 4);
    expect(legacyMacro.mouseDx, -2);
    expect(legacyMacro.mouseDy, 3);

    final legacyAudio = ButtonAction.fromJson(cases[6]['json'] as Map<String, dynamic>);
    expect(legacyAudio.audioFilePath, '/data/sound/legacy.wav');
  });
}
