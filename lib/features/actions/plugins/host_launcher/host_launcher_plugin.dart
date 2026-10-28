import 'package:flutter/material.dart';

import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';
import 'host_launcher_editor.dart';

class HostLauncherPlugin extends ActionPlugin {
  @override
  ActionCategory get category => ActionCategory.hostLauncher;

  @override
  bool matchesJson(Map<String, dynamic> json) {
    final rawCategory = json['category'];
    return rawCategory == 'host_launcher' ||
        rawCategory == 'hostLauncher' ||
        rawCategory == 'macro_host_launcher' ||
        (rawCategory == 'macro' && json['macroType'] == 'macro_host_launcher');
  }

  @override
  ButtonAction readFields(Map<String, dynamic> json, ButtonAction acc) {
    final rawArgs = json['args'];
    return acc.copyWith(
      launcherType: HostLauncherType.fromString(
        json['launcherType'] as String?,
      ),
      target: (json['target'] as String?) ?? '',
      args: rawArgs is List
          ? rawArgs.map((value) => value.toString()).toList()
          : const <String>[],
    );
  }

  @override
  Map<String, dynamic> toJson(ButtonAction action) => {
    'category': 'host_launcher',
    'macroType': 'macro_host_launcher',
    'launcherType': action.launcherType.jsonValue,
    'target': action.target,
    'args': action.args,
  };

  @override
  String summaryBadge(ButtonAction action) =>
      action.launcherType.jsonValue.toUpperCase();

  @override
  Future<String> execute(ActionExecutionContext context) async {
    final action = context.keyConfig.action;
    final result = await context.hostLauncherService.execute(
      launcherType: action.launcherType,
      target: action.target,
      args: action.args,
    );
    return 'Launched ${action.launcherType.jsonValue}: ${action.target} (exit=${result.exitCode})';
  }

  @override
  Widget buildEditor(BuildContext context, ActionEditorScope scope) =>
      HostLauncherEditor(scope: scope);
}
