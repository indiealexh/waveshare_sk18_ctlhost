import 'package:flutter/material.dart';

import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';

class HostLauncherEditor extends StatefulWidget {
  final ActionEditorScope scope;

  const HostLauncherEditor({super.key, required this.scope});

  @override
  State<HostLauncherEditor> createState() => _HostLauncherEditorState();
}

class _HostLauncherEditorState extends State<HostLauncherEditor> {
  late final TextEditingController _targetController;
  late final TextEditingController _argsController;
  int _lastSyncedKeyIndex = -1;
  String _lastSyncedPageId = '';

  @override
  void initState() {
    super.initState();
    _targetController = TextEditingController();
    _argsController = TextEditingController();
    _syncControllersWithSelectedKey();
  }

  @override
  void didUpdateWidget(covariant HostLauncherEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllersWithSelectedKey();
  }

  void _syncControllersWithSelectedKey() {
    final key = widget.scope.keyConfig;
    final pageId = widget.scope.vm.activePage.id;
    if (_lastSyncedKeyIndex != key.index || _lastSyncedPageId != pageId) {
      _lastSyncedKeyIndex = key.index;
      _lastSyncedPageId = pageId;
      _targetController.text = key.action.target;
      _argsController.text = key.action.args.join(' ');
    }
  }

  @override
  void dispose() {
    _targetController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final action = scope.action;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Host Launcher Settings',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: HostLauncherType.values.map((type) {
                return ChoiceChip(
                  key: Key('launcher_type_${type.jsonValue}'),
                  label: Text(
                    type.displayName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: action.launcherType == type,
                  onSelected: (_) {
                    scope.update(action.copyWith(launcherType: type));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            const Text(
              'Target (App Name, Shell Command, or URL)',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('launcher_target_field'),
              controller: _targetController,
              decoration: const InputDecoration(
                hintText: 'e.g. Terminal, git status, or https://...',
              ),
              onChanged: (val) {
                scope.update(action.copyWith(target: val));
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Arguments (space-separated)',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('launcher_args_field'),
              controller: _argsController,
              decoration: const InputDecoration(
                hintText: '--single-instance',
              ),
              onChanged: (val) {
                final splitArgs = val
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((s) => s.isNotEmpty)
                    .toList();
                scope.update(action.copyWith(args: splitArgs));
              },
            ),
          ],
        ),
      ),
    );
  }
}
