import 'package:flutter/material.dart';

import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';

class MacroEditor extends StatefulWidget {
  final ActionEditorScope scope;

  const MacroEditor({super.key, required this.scope});

  @override
  State<MacroEditor> createState() => _MacroEditorState();
}

class _MacroEditorState extends State<MacroEditor> {
  late final TextEditingController _textController;
  int _lastSyncedKeyIndex = -1;
  String _lastSyncedPageId = '';

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _syncControllerWithSelectedKey();
  }

  @override
  void didUpdateWidget(covariant MacroEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerWithSelectedKey();
  }

  void _syncControllerWithSelectedKey() {
    final key = widget.scope.keyConfig;
    final pageId = widget.scope.vm.activePage.id;
    if (_lastSyncedKeyIndex != key.index || _lastSyncedPageId != pageId) {
      _lastSyncedKeyIndex = key.index;
      _lastSyncedPageId = pageId;
      final firstTextStep = key.action.sequenceSteps
          .where((step) => step.type == MacroStepType.text)
          .firstOrNull;
      _textController.text = firstTextStep?.value ?? '';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final action = scope.action;
    const allModifiers = ['LCTL', 'LSFT', 'LALT', 'LGUI'];
    const keycodePresets = <int, String>{
      0x0004: 'A (0x0004)',
      0x0005: 'B (0x0005)',
      0x0006: 'C (0x0006)',
      0x0019: 'V (0x0019)',
      0x001D: 'Z (0x001D)',
      0x0028: 'ENTER (0x0028)',
      0x002C: 'SPACE (0x002C)',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Keyboard & Mouse Macro Settings',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: MacroActionType.values.map((mType) {
                return ChoiceChip(
                  key: Key('macro_type_${mType.jsonValue}'),
                  label: Text(
                    mType.displayName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: action.macroType == mType,
                  onSelected: (_) {
                    scope.update(action.copyWith(macroType: mType));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            if (action.macroType == MacroActionType.hotkey) ...[
              const Text(
                'Modifiers',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: allModifiers.map((mod) {
                  final active = action.modifiers.contains(mod);
                  return FilterChip(
                    key: Key('modifier_chip_$mod'),
                    label: Text(mod, style: const TextStyle(fontSize: 11)),
                    selected: active,
                    onSelected: (selected) {
                      final nextMods = List<String>.from(action.modifiers);
                      if (selected) {
                        if (!nextMods.contains(mod)) nextMods.add(mod);
                      } else {
                        nextMods.remove(mod);
                      }
                      scope.update(action.copyWith(modifiers: nextMods));
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              const Text(
                'QMK Keycode',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<int>(
                key: const Key('macro_keycode_dropdown'),
                initialValue: keycodePresets.containsKey(action.keycode)
                    ? action.keycode
                    : 0x0004,
                isExpanded: true,
                items: keycodePresets.entries
                    .map(
                      (e) => DropdownMenuItem<int>(
                        value: e.key,
                        child: Text(e.value, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (kc) {
                  if (kc != null) {
                    scope.update(action.copyWith(keycode: kc));
                  }
                },
              ),
            ] else if (action.macroType == MacroActionType.sequence) ...[
              const Text(
                'Text to Type (V2 keyboardInput / Sequence)',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 4),
              TextField(
                key: const Key('macro_sequence_text_field'),
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'e.g. flutter test',
                ),
                onChanged: (val) {
                  scope.update(
                    action.copyWith(
                      sequenceSteps: [
                        MacroStep(type: MacroStepType.text, value: val),
                        const MacroStep(type: MacroStepType.delayMs, value: '40'),
                        const MacroStep(type: MacroStepType.keyTap, value: 'ENTER'),
                      ],
                    ),
                  );
                },
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scroll Wheel V: ${action.wheelV}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => scope.update(
                      action.copyWith(wheelV: action.wheelV - 1),
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => scope.update(
                      action.copyWith(wheelV: action.wheelV + 1),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
