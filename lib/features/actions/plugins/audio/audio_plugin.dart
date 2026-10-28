import 'package:flutter/material.dart';

import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';
import 'audio_editor.dart';

class AudioPlugin extends ActionPlugin {
  @override
  ActionCategory get category => ActionCategory.audio;

  @override
  bool matchesJson(Map<String, dynamic> json) => json['category'] == 'audio';

  @override
  ButtonAction readFields(Map<String, dynamic> json, ButtonAction acc) {
    final audioFilePath =
        (json['audioFilePath'] as String? ?? json['filePath'] as String?) ??
        '/data/sound/click.wav';
    return acc.copyWith(audioFilePath: audioFilePath);
  }

  @override
  Map<String, dynamic> toJson(ButtonAction action) => {
    'category': 'audio',
    'audioFilePath': action.audioFilePath,
    'filePath': action.audioFilePath,
  };

  @override
  String summaryBadge(ButtonAction action) => 'WAV';

  @override
  Future<String> execute(ActionExecutionContext context) async {
    final filePath = context.keyConfig.action.audioFilePath;
    await context.deviceRepository.playAudio(filePath);
    return 'Playing WAV on SK18: $filePath';
  }

  @override
  Widget buildEditor(BuildContext context, ActionEditorScope scope) =>
      AudioEditor(scope: scope);
}
