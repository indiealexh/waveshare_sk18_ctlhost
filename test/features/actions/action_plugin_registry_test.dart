import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/features/actions/domain/action_plugin_registry.dart';
import 'package:wavectl_host/features/actions/domain/button_action.dart';

void main() {
  group('ActionPluginRegistry', () {
    final registry = ActionPluginRegistry.instance;

    test('plugins follow ActionCategory order and are keyed by category', () {
      expect(
        registry.ordered.map((plugin) => plugin.category).toList(),
        ActionCategory.values,
      );
      for (final category in ActionCategory.values) {
        expect(registry.forCategory(category).category, category);
      }
    });

    test('resolves category aliases with host launcher precedence', () {
      final cases = <Map<String, dynamic>>[
        {
          'json': {'category': 'none'},
          'category': ActionCategory.none,
        },
        {
          'json': {'category': 'host_launcher'},
          'category': ActionCategory.hostLauncher,
        },
        {
          'json': {'category': 'hostLauncher'},
          'category': ActionCategory.hostLauncher,
        },
        {
          'json': {
            'category': 'macro',
            'macroType': 'macro_host_launcher',
          },
          'category': ActionCategory.hostLauncher,
        },
        {
          'json': {'category': 'ha'},
          'category': ActionCategory.homeAssistant,
        },
        {
          'json': {'category': 'homeAssistant'},
          'category': ActionCategory.homeAssistant,
        },
        {
          'json': {'category': 'home_assistant'},
          'category': ActionCategory.homeAssistant,
        },
        {
          'json': {'category': 'audio'},
          'category': ActionCategory.audio,
        },
        {
          'json': {'category': 'macro_host_launcher'},
          'category': ActionCategory.hostLauncher,
        },
        {
          'json': {'category': 'future_category'},
          'category': ActionCategory.none,
        },
      ];

      for (final testCase in cases) {
        expect(
          registry.resolveCategory(testCase['json'] as Map<String, dynamic>),
          testCase['category'],
        );
      }
    });
  });
}
