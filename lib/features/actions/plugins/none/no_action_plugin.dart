import 'package:flutter/material.dart';

import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';

class NoActionPlugin extends ActionPlugin {
  @override
  ActionCategory get category => ActionCategory.none;

  @override
  bool matchesJson(Map<String, dynamic> json) => json['category'] == 'none';

  @override
  ButtonAction readFields(Map<String, dynamic> json, ButtonAction acc) => acc;

  @override
  Map<String, dynamic> toJson(ButtonAction action) => {'category': 'none'};

  @override
  String summaryBadge(ButtonAction action) => 'IDLE';

  @override
  Future<String> execute(ActionExecutionContext context) async =>
      'No action bound to ${context.keyConfig.label}';

  @override
  Widget buildEditor(BuildContext context, ActionEditorScope scope) => const Card(
    child: Padding(
      padding: EdgeInsets.all(12),
      child: Text(
        'No action assigned. Choose Host Launcher, Macro, Home Assistant, or Audio above.',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      ),
    ),
  );
}
