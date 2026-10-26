import 'button_action.dart';
import 'key_button_config.dart';
import 'sk18_geometry.dart';

class Sk18Page {
  final String id;
  final String name;
  final List<KeyButtonConfig> keys; // Always 18 items

  const Sk18Page({
    required this.id,
    required this.name,
    required this.keys,
  });

  Sk18Page copyWith({
    String? id,
    String? name,
    List<KeyButtonConfig>? keys,
  }) {
    return Sk18Page(
      id: id ?? this.id,
      name: name ?? this.name,
      keys: keys ?? this.keys,
    );
  }

  factory Sk18Page.empty({
    required String id,
    required String name,
    bool landscapeMode = true,
  }) {
    final cols = landscapeMode
        ? Sk18Geometry.landscapeCols
        : Sk18Geometry.portraitCols;
    final keys = List<KeyButtonConfig>.generate(Sk18Geometry.totalKeys, (index) {
      return KeyButtonConfig(
        index: index,
        col: index % cols,
        row: index ~/ cols,
        label: 'Key ${index + 1}',
        iconName: 'grid',
        colorHex: 0xFF38BDF8,
      );
    });
    return Sk18Page(id: id, name: name, keys: keys);
  }

  factory Sk18Page.fromJson(
    Map<String, dynamic> json, {
    bool landscapeMode = true,
  }) {
    final cols = landscapeMode
        ? Sk18Geometry.landscapeCols
        : Sk18Geometry.portraitCols;
    final rawKeys = (json['keys'] as List<dynamic>?) ?? const <dynamic>[];
    final parsedByIndex = <int, KeyButtonConfig>{};
    for (final item in rawKeys) {
      if (item is Map<String, dynamic>) {
        final cfg = KeyButtonConfig.fromJson(item);
        if (cfg.index >= 0 && cfg.index < Sk18Geometry.totalKeys) {
          parsedByIndex[cfg.index] = cfg;
        }
      }
    }

    final normalizedKeys = List<KeyButtonConfig>.generate(
      Sk18Geometry.totalKeys,
      (idx) =>
          parsedByIndex[idx] ??
          KeyButtonConfig(
            index: idx,
            col: idx % cols,
            row: idx ~/ cols,
            label: 'Key ${idx + 1}',
          ),
    );

    return Sk18Page(
      id: (json['id'] as String?) ?? 'page_1',
      name: (json['name'] as String?) ?? 'Page 1',
      keys: normalizedKeys,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keys': keys.map((k) => k.toJson()).toList(),
    };
  }
}

class Sk18Profile {
  final String id;
  final String name;
  final bool landscapeMode;
  final bool upsideDown;
  final int backlight; // 0..100
  final int volume; // 0..7
  final int offsetX; // -64..64
  final int offsetY; // -64..64
  final List<Sk18Page> pages;

  const Sk18Profile({
    required this.id,
    required this.name,
    this.landscapeMode = true,
    this.upsideDown = false,
    this.backlight = 85,
    this.volume = 5,
    this.offsetX = 0,
    this.offsetY = 0,
    required this.pages,
  });

  Sk18Profile copyWith({
    String? id,
    String? name,
    bool? landscapeMode,
    bool? upsideDown,
    int? backlight,
    int? volume,
    int? offsetX,
    int? offsetY,
    List<Sk18Page>? pages,
  }) {
    return Sk18Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      landscapeMode: landscapeMode ?? this.landscapeMode,
      upsideDown: upsideDown ?? this.upsideDown,
      backlight: (backlight ?? this.backlight).clamp(0, 100),
      volume: (volume ?? this.volume).clamp(0, 7),
      offsetX: Sk18Geometry.clampOffset(offsetX ?? this.offsetX),
      offsetY: Sk18Geometry.clampOffset(offsetY ?? this.offsetY),
      pages: pages ?? this.pages,
    );
  }

  /// Serializes the active page (and full profile metadata) into the shared
  /// `/mnt/SDCARD/sk18_config.json` format expected by the SK18 custom firmware
  /// and companion JSON import/export.
  Map<String, dynamic> toSk18ConfigJson({
    int pageIndex = 0,
    String haUrl = 'http://homeassistant.local:8123',
    bool haEnabled = true,
  }) {
    final safeIndex = pages.isEmpty
        ? 0
        : pageIndex.clamp(0, pages.length - 1);
    final activeKeys = pages.isEmpty
        ? Sk18Page.empty(id: 'page_1', name: 'Main').keys
        : pages[safeIndex].keys;

    return {
      'version': 1,
      'profileId': id,
      'profileName': name,
      'activePageIndex': safeIndex,
      'device': {
        'backlight': backlight.clamp(0, 100),
        'volume': volume.clamp(0, 7),
        'landscapeMode': landscapeMode,
        'upsideDown': upsideDown,
        'offsetX': Sk18Geometry.clampOffset(offsetX),
        'offsetY': Sk18Geometry.clampOffset(offsetY),
      },
      'homeAssistant': {
        'enabled': haEnabled,
        'url': haUrl,
      },
      'keys': activeKeys.map((k) => k.toJson()).toList(),
      'pages': pages.map((p) => p.toJson()).toList(),
    };
  }

  factory Sk18Profile.fromJson(Map<String, dynamic> json) {
    final deviceMap =
        (json['device'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final landscape =
        (json['landscapeMode'] as bool?) ??
        (deviceMap['landscapeMode'] as bool?) ??
        true;
    final upsideDown =
        (json['upsideDown'] as bool?) ??
        (deviceMap['upsideDown'] as bool?) ??
        false;
    final backlight =
        (json['backlight'] as num? ?? deviceMap['backlight'] as num?)?.toInt() ??
        85;
    final volume =
        (json['volume'] as num? ?? deviceMap['volume'] as num?)?.toInt() ?? 5;
    final offsetX =
        (json['offsetX'] as num? ?? deviceMap['offsetX'] as num?)?.toInt() ?? 0;
    final offsetY =
        (json['offsetY'] as num? ?? deviceMap['offsetY'] as num?)?.toInt() ?? 0;

    final rawPages = json['pages'];
    List<Sk18Page> parsedPages = [];
    if (rawPages is List && rawPages.isNotEmpty) {
      parsedPages = rawPages
          .whereType<Map<String, dynamic>>()
          .map((p) => Sk18Page.fromJson(p, landscapeMode: landscape))
          .toList();
    } else if (json['keys'] is List) {
      parsedPages = [
        Sk18Page.fromJson(
          {
            'id': 'page_1',
            'name': 'Main Page',
            'keys': json['keys'],
          },
          landscapeMode: landscape,
        ),
      ];
    }

    if (parsedPages.isEmpty) {
      parsedPages = [
        Sk18Page.empty(
          id: 'page_1',
          name: 'Main Page',
          landscapeMode: landscape,
        ),
      ];
    }

    return Sk18Profile(
      id:
          (json['id'] as String? ?? json['profileId'] as String?) ??
          'profile_default',
      name:
          (json['name'] as String? ?? json['profileName'] as String?) ??
          'Default Studio',
      landscapeMode: landscape,
      upsideDown: upsideDown,
      backlight: backlight.clamp(0, 100),
      volume: volume.clamp(0, 7),
      offsetX: Sk18Geometry.clampOffset(offsetX),
      offsetY: Sk18Geometry.clampOffset(offsetY),
      pages: parsedPages,
    );
  }

  Map<String, dynamic> toJson() => toSk18ConfigJson();

  factory Sk18Profile.createDefault() {
    final mainPageKeys = <KeyButtonConfig>[
      const KeyButtonConfig(
        index: 0,
        col: 0,
        row: 0,
        label: 'Office Light',
        iconName: 'lightbulb',
        colorHex: 0xFFFFB300,
        action: ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.toggle,
          entityId: 'light.office_main',
        ),
      ),
      const KeyButtonConfig(
        index: 1,
        col: 1,
        row: 0,
        label: 'Bright +10%',
        iconName: 'sun',
        colorHex: 0xFFF59E0B,
        action: ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.brightnessUp,
          entityId: 'light.office_main',
          step: 10,
        ),
      ),
      const KeyButtonConfig(
        index: 2,
        col: 2,
        row: 0,
        label: 'Bright -10%',
        iconName: 'moon',
        colorHex: 0xFF6366F1,
        action: ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.brightnessDown,
          entityId: 'light.office_main',
          step: 10,
        ),
      ),
      const KeyButtonConfig(
        index: 3,
        col: 3,
        row: 0,
        label: 'Studio AC',
        iconName: 'thermostat',
        colorHex: 0xFF06B6D4,
        action: ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.hvacMode,
          entityId: 'climate.studio_hvac',
        ),
      ),
      const KeyButtonConfig(
        index: 4,
        col: 4,
        row: 0,
        label: 'Temp +0.5°',
        iconName: 'temp_up',
        colorHex: 0xFFEF4444,
        action: ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.hvacTempUp,
          entityId: 'climate.studio_hvac',
          step: 0.5,
        ),
      ),
      const KeyButtonConfig(
        index: 5,
        col: 5,
        row: 0,
        label: 'Temp -0.5°',
        iconName: 'temp_down',
        colorHex: 0xFF3B82F6,
        action: ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.hvacTempDown,
          entityId: 'climate.studio_hvac',
          step: 0.5,
        ),
      ),
      const KeyButtonConfig(
        index: 6,
        col: 0,
        row: 1,
        label: 'Terminal',
        iconName: 'terminal',
        colorHex: 0xFF10B981,
        action: ButtonAction(
          category: ActionCategory.hostLauncher,
          launcherType: HostLauncherType.app,
          target: 'Terminal',
        ),
      ),
      const KeyButtonConfig(
        index: 7,
        col: 1,
        row: 1,
        label: 'Git Status',
        iconName: 'code',
        colorHex: 0xFF14B8A6,
        action: ButtonAction(
          category: ActionCategory.hostLauncher,
          launcherType: HostLauncherType.script,
          target: 'git status --short',
        ),
      ),
      const KeyButtonConfig(
        index: 8,
        col: 2,
        row: 1,
        label: 'Docs Portal',
        iconName: 'globe',
        colorHex: 0xFF0EA5E9,
        action: ButtonAction(
          category: ActionCategory.hostLauncher,
          launcherType: HostLauncherType.url,
          target: 'https://www.waveshare.com/wiki/SK18',
        ),
      ),
      const KeyButtonConfig(
        index: 9,
        col: 3,
        row: 1,
        label: 'Copy',
        iconName: 'copy',
        colorHex: 0xFF8B5CF6,
        action: ButtonAction(
          category: ActionCategory.macro,
          macroType: MacroActionType.hotkey,
          keycode: 0x0006, // KC_C
          modifiers: ['LGUI'],
        ),
      ),
      const KeyButtonConfig(
        index: 10,
        col: 4,
        row: 1,
        label: 'Paste',
        iconName: 'paste',
        colorHex: 0xFFA855F7,
        action: ButtonAction(
          category: ActionCategory.macro,
          macroType: MacroActionType.hotkey,
          keycode: 0x0019, // KC_V
          modifiers: ['LGUI'],
        ),
      ),
      const KeyButtonConfig(
        index: 11,
        col: 5,
        row: 1,
        label: 'Deploy Macro',
        iconName: 'bolt',
        colorHex: 0xFFEC4899,
        action: ButtonAction(
          category: ActionCategory.macro,
          macroType: MacroActionType.sequence,
          sequenceSteps: [
            MacroStep(type: MacroStepType.text, value: 'flutter test'),
            MacroStep(type: MacroStepType.delayMs, value: '50'),
            MacroStep(type: MacroStepType.keyTap, value: 'ENTER'),
          ],
        ),
      ),
      const KeyButtonConfig(
        index: 12,
        col: 0,
        row: 2,
        label: 'Click SFX',
        iconName: 'speaker',
        colorHex: 0xFFF97316,
        action: ButtonAction(
          category: ActionCategory.audio,
          audioFilePath: '/data/sound/click.wav',
        ),
      ),
      const KeyButtonConfig(
        index: 13,
        col: 1,
        row: 2,
        label: 'Chime SFX',
        iconName: 'music',
        colorHex: 0xFFEAB308,
        action: ButtonAction(
          category: ActionCategory.audio,
          audioFilePath: '/data/sound/chime.wav',
        ),
      ),
      const KeyButtonConfig(
        index: 14,
        col: 2,
        row: 2,
        label: 'Scroll Up',
        iconName: 'mouse',
        colorHex: 0xFF22C55E,
        action: ButtonAction(
          category: ActionCategory.macro,
          macroType: MacroActionType.mouse,
          mouseButtons: 0,
          wheelV: 3,
        ),
      ),
      const KeyButtonConfig(
        index: 15,
        col: 3,
        row: 2,
        label: 'Scroll Down',
        iconName: 'mouse',
        colorHex: 0xFF16A34A,
        action: ButtonAction(
          category: ActionCategory.macro,
          macroType: MacroActionType.mouse,
          mouseButtons: 0,
          wheelV: -3,
        ),
      ),
      const KeyButtonConfig(
        index: 16,
        col: 4,
        row: 2,
        label: 'Desk Fan',
        iconName: 'power',
        colorHex: 0xFF06B6D4,
        action: ButtonAction(
          category: ActionCategory.homeAssistant,
          haType: HaActionType.toggle,
          entityId: 'switch.desk_fan',
        ),
      ),
      const KeyButtonConfig(
        index: 17,
        col: 5,
        row: 2,
        label: 'Build All',
        iconName: 'play',
        colorHex: 0xFF38BDF8,
        action: ButtonAction(
          category: ActionCategory.macro,
          macroType: MacroActionType.hotkey,
          keycode: 0x0005, // KC_B
          modifiers: ['LGUI', 'LSFT'],
        ),
      ),
    ];

    final secondPage = Sk18Page.empty(
      id: 'page_media',
      name: 'Media & Stream',
      landscapeMode: true,
    );

    return Sk18Profile(
      id: 'profile_studio',
      name: 'SK18 Master Studio',
      landscapeMode: true,
      backlight: 85,
      volume: 5,
      offsetX: 0,
      offsetY: 0,
      pages: [
        Sk18Page(
          id: 'page_main',
          name: 'Smart Desk & Dev',
          keys: mainPageKeys,
        ),
        secondPage,
      ],
    );
  }
}
