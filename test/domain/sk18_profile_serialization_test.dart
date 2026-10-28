import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/features/actions/domain/button_action.dart';
import 'package:wavectl_host/core/models/sk18_geometry.dart';
import 'package:wavectl_host/features/profiles/domain/sk18_profile.dart';

void main() {
  group('Sk18Profile & ButtonAction Serialization', () {
    test('round-trips default multi-page profile across all four action categories', () {
      final original = Sk18Profile.createDefault().copyWith(upsideDown: true);
      expect(original.pages.length, equals(2));
      expect(original.pages.first.keys.length, equals(18));

      final jsonString = jsonEncode(original.toSk18ConfigJson(pageIndex: 0));
      final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = Sk18Profile.fromJson(decodedMap);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.upsideDown, isTrue);
      expect(restored.backlight, equals(85));
      expect(restored.volume, equals(5));
      expect(restored.pages.length, equals(2));

      final keys = restored.pages.first.keys;
      // 1. Home Assistant action
      expect(keys[0].action.category, equals(ActionCategory.homeAssistant));
      expect(keys[0].action.haType, equals(HaActionType.toggle));
      expect(keys[0].action.entityId, equals('light.office_main'));

      // 2. Host Launcher action
      expect(keys[6].action.category, equals(ActionCategory.hostLauncher));
      expect(keys[6].action.launcherType, equals(HostLauncherType.app));
      expect(keys[6].action.target, equals('Terminal'));

      // 3. Macro sequence action
      expect(keys[11].action.category, equals(ActionCategory.macro));
      expect(keys[11].action.macroType, equals(MacroActionType.sequence));
      expect(keys[11].action.sequenceSteps.length, equals(3));
      expect(keys[11].action.sequenceSteps.first.value, equals('flutter test'));

      // 4. On-Device Audio action
      expect(keys[12].action.category, equals(ActionCategory.audio));
      expect(keys[12].action.audioFilePath, equals('/data/sound/click.wav'));
    });

    test('imports custom firmware sk18_config.json format with macro_host_launcher', () {
      final firmwareJson = <String, dynamic>{
        'version': 1,
        'device': {
          'backlight': 70,
          'volume': 4,
          'landscapeMode': true,
        },
        'keys': [
          {
            'index': 0,
            'col': 0,
            'row': 0,
            'label': 'Open Kitty',
            'icon': 'terminal',
            'color': '#10B981',
            'action': {
              'category': 'macro',
              'macroType': 'macro_host_launcher',
              'launcherType': 'app',
              'target': 'kitty',
              'args': ['--single-instance'],
            },
          },
        ],
      };

      final profile = Sk18Profile.fromJson(firmwareJson);
      expect(profile.backlight, equals(70));
      expect(profile.volume, equals(4));
      expect(profile.pages.first.keys.length, equals(18));

      final firstKey = profile.pages.first.keys.first;
      expect(firstKey.label, equals('Open Kitty'));
      expect(firstKey.colorCssHex, equals('#10B981'));
      expect(firstKey.action.category, equals(ActionCategory.hostLauncher));
      expect(firstKey.action.launcherType, equals(HostLauncherType.app));
      expect(firstKey.action.target, equals('kitty'));
      expect(firstKey.action.args, equals(['--single-instance']));
      expect(profile.deviceModel, equals(WaveshareModel.sk18));
    });

    test('round-trips MK10 10-key profile with deviceModel == MK10', () {
      final mk10Profile = Sk18Profile.createDefaultMk10();
      expect(mk10Profile.deviceModel, equals(WaveshareModel.mk10));
      expect(mk10Profile.pages.length, equals(2));
      expect(mk10Profile.pages.first.keys.length, equals(10));
      expect(mk10Profile.pages.last.keys.length, equals(10));

      final jsonMap = mk10Profile.toSk18ConfigJson(pageIndex: 0);
      expect(jsonMap['deviceModel'], equals('MK10'));

      final restored = Sk18Profile.fromJson(
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>,
      );
      expect(restored.deviceModel, equals(WaveshareModel.mk10));
      expect(restored.pages.first.keys.length, equals(10));
      expect(restored.pages.first.keys[9].col, equals(4));
      expect(restored.pages.first.keys[9].row, equals(1));
    });
  });
}
