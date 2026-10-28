import 'action_plugin_registry.dart';

enum ActionCategory {
  none('none', 'No Action'),
  hostLauncher('host_launcher', 'Host Launcher'),
  macro('macro', 'Keyboard / Mouse Macro'),
  homeAssistant('ha', 'Home Assistant'),
  audio('audio', 'On-Device Audio');

  final String jsonValue;
  final String displayName;
  const ActionCategory(this.jsonValue, this.displayName);

  static ActionCategory fromString(String? raw) {
    switch (raw) {
      case 'host_launcher':
      case 'hostLauncher':
      case 'macro_host_launcher':
        return ActionCategory.hostLauncher;
      case 'macro':
        return ActionCategory.macro;
      case 'ha':
      case 'homeAssistant':
      case 'home_assistant':
        return ActionCategory.homeAssistant;
      case 'audio':
        return ActionCategory.audio;
      default:
        return ActionCategory.none;
    }
  }
}

enum HostLauncherType {
  app('app', 'Desktop App'),
  script('script', 'Shell Command / Script'),
  url('url', 'Open Web URL');

  final String jsonValue;
  final String displayName;
  const HostLauncherType(this.jsonValue, this.displayName);

  static HostLauncherType fromString(String? raw) {
    switch (raw) {
      case 'script':
        return HostLauncherType.script;
      case 'url':
        return HostLauncherType.url;
      case 'app':
      default:
        return HostLauncherType.app;
    }
  }
}

enum MacroActionType {
  hotkey('macro_hotkey', 'Hotkey / Shortcut'),
  sequence('macro_sequence', 'Keystroke Sequence'),
  mouse('macro_mouse', 'Mouse & Scroll');

  final String jsonValue;
  final String displayName;
  const MacroActionType(this.jsonValue, this.displayName);

  static MacroActionType fromString(String? raw) {
    switch (raw) {
      case 'sequence':
      case 'macro_sequence':
        return MacroActionType.sequence;
      case 'mouse':
      case 'macro_mouse':
        return MacroActionType.mouse;
      case 'hotkey':
      case 'macro_hotkey':
      default:
        return MacroActionType.hotkey;
    }
  }
}

enum HaActionType {
  toggle('ha_toggle', 'Toggle Entity'),
  brightnessUp('ha_brightness_up', 'Brightness Up'),
  brightnessDown('ha_brightness_down', 'Brightness Down'),
  hvacMode('ha_hvac_mode', 'HVAC Mode'),
  hvacTempUp('ha_hvac_temp_up', 'Target Temp +'),
  hvacTempDown('ha_hvac_temp_down', 'Target Temp -');

  final String jsonValue;
  final String displayName;
  const HaActionType(this.jsonValue, this.displayName);

  static HaActionType fromString(String? raw) {
    switch (raw) {
      case 'ha_brightness_up':
      case 'brightnessUp':
        return HaActionType.brightnessUp;
      case 'ha_brightness_down':
      case 'brightnessDown':
        return HaActionType.brightnessDown;
      case 'ha_hvac_mode':
      case 'hvacMode':
        return HaActionType.hvacMode;
      case 'ha_hvac_temp_up':
      case 'hvacTempUp':
        return HaActionType.hvacTempUp;
      case 'ha_hvac_temp_down':
      case 'hvacTempDown':
        return HaActionType.hvacTempDown;
      case 'ha_toggle':
      case 'toggle':
      default:
        return HaActionType.toggle;
    }
  }
}

enum MacroStepType {
  text('text'),
  keyTap('key_tap'),
  delayMs('delay_ms');

  final String jsonValue;
  const MacroStepType(this.jsonValue);

  static MacroStepType fromString(String? raw) {
    switch (raw) {
      case 'key_tap':
      case 'keyTap':
        return MacroStepType.keyTap;
      case 'delay_ms':
      case 'delayMs':
        return MacroStepType.delayMs;
      case 'text':
      default:
        return MacroStepType.text;
    }
  }
}

class MacroStep {
  final MacroStepType type;
  final String value;

  const MacroStep({
    required this.type,
    required this.value,
  });

  int get delayMilliseconds => int.tryParse(value) ?? 50;

  factory MacroStep.fromJson(Map<String, dynamic> json) {
    return MacroStep(
      type: MacroStepType.fromString(json['type'] as String?),
      value: (json['value'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.jsonValue,
      'value': value,
    };
  }
}

class ButtonAction {
  final ActionCategory category;

  // Host Launcher
  final HostLauncherType launcherType;
  final String target;
  final List<String> args;

  // Macro
  final MacroActionType macroType;
  final int keycode;
  final List<String> modifiers; // ["LCTL", "LSFT", "LALT", "LGUI"]
  final int? consumerCode;
  final List<MacroStep> sequenceSteps;
  final int mouseButtons;
  final int mouseDx;
  final int mouseDy;
  final int wheelV;
  final int wheelH;

  // Home Assistant
  final HaActionType haType;
  final String entityId;
  final double step;
  final String? targetHvacMode;
  final List<String> hvacModes;

  // On-Device Audio
  final String audioFilePath;

  const ButtonAction({
    this.category = ActionCategory.none,
    this.launcherType = HostLauncherType.app,
    this.target = '',
    this.args = const [],
    this.macroType = MacroActionType.hotkey,
    this.keycode = 0x0004, // KC_A default
    this.modifiers = const [],
    this.consumerCode,
    this.sequenceSteps = const [],
    this.mouseButtons = 1,
    this.mouseDx = 0,
    this.mouseDy = 0,
    this.wheelV = 0,
    this.wheelH = 0,
    this.haType = HaActionType.toggle,
    this.entityId = '',
    this.step = 10.0,
    this.targetHvacMode,
    this.hvacModes = const ['off', 'heat', 'cool', 'auto'],
    this.audioFilePath = '/data/sound/click.wav',
  });

  String get summaryBadge =>
      ActionPluginRegistry.instance.forCategory(category).summaryBadge(this);

  ButtonAction copyWith({
    ActionCategory? category,
    HostLauncherType? launcherType,
    String? target,
    List<String>? args,
    MacroActionType? macroType,
    int? keycode,
    List<String>? modifiers,
    int? consumerCode,
    bool clearConsumerCode = false,
    List<MacroStep>? sequenceSteps,
    int? mouseButtons,
    int? mouseDx,
    int? mouseDy,
    int? wheelV,
    int? wheelH,
    HaActionType? haType,
    String? entityId,
    double? step,
    String? targetHvacMode,
    bool clearTargetHvacMode = false,
    List<String>? hvacModes,
    String? audioFilePath,
  }) {
    return ButtonAction(
      category: category ?? this.category,
      launcherType: launcherType ?? this.launcherType,
      target: target ?? this.target,
      args: args ?? this.args,
      macroType: macroType ?? this.macroType,
      keycode: keycode ?? this.keycode,
      modifiers: modifiers ?? this.modifiers,
      consumerCode: clearConsumerCode ? null : (consumerCode ?? this.consumerCode),
      sequenceSteps: sequenceSteps ?? this.sequenceSteps,
      mouseButtons: mouseButtons ?? this.mouseButtons,
      mouseDx: mouseDx ?? this.mouseDx,
      mouseDy: mouseDy ?? this.mouseDy,
      wheelV: wheelV ?? this.wheelV,
      wheelH: wheelH ?? this.wheelH,
      haType: haType ?? this.haType,
      entityId: entityId ?? this.entityId,
      step: step ?? this.step,
      targetHvacMode: clearTargetHvacMode
          ? null
          : (targetHvacMode ?? this.targetHvacMode),
      hvacModes: hvacModes ?? this.hvacModes,
      audioFilePath: audioFilePath ?? this.audioFilePath,
    );
  }

  factory ButtonAction.fromJson(Map<String, dynamic> json) {
    final registry = ActionPluginRegistry.instance;
    var action = ButtonAction(category: registry.resolveCategory(json));
    for (final plugin in registry.ordered) {
      action = plugin.readFields(json, action);
    }
    return action;
  }

  Map<String, dynamic> toJson() =>
      ActionPluginRegistry.instance.forCategory(category).toJson(this);
}
