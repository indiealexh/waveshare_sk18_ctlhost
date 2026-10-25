import 'package:flutter/material.dart';

import '../../../../domain/models/button_action.dart';
import '../../../../domain/models/key_button_config.dart';
import '../../../core/rendering/sk18_canvas_painter.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

class RightInspectorPanel extends StatefulWidget {
  final StudioViewModel viewModel;

  const RightInspectorPanel({
    super.key,
    required this.viewModel,
  });

  @override
  State<RightInspectorPanel> createState() => _RightInspectorPanelState();
}

class _RightInspectorPanelState extends State<RightInspectorPanel> {
  late TextEditingController _labelController;
  late TextEditingController _launcherTargetController;
  late TextEditingController _launcherArgsController;
  late TextEditingController _haEntityController;
  late TextEditingController _macroTextController;
  int _lastSyncedKeyIndex = -1;
  String _lastSyncedPageId = '';

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
    _launcherTargetController = TextEditingController();
    _launcherArgsController = TextEditingController();
    _haEntityController = TextEditingController();
    _macroTextController = TextEditingController();
    _syncControllersWithSelectedKey();
  }

  @override
  void didUpdateWidget(covariant RightInspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllersWithSelectedKey();
  }

  void _syncControllersWithSelectedKey() {
    final vm = widget.viewModel;
    final key = vm.selectedKeyConfig;
    final pageId = vm.activePage.id;

    if (_lastSyncedKeyIndex != key.index || _lastSyncedPageId != pageId) {
      _lastSyncedKeyIndex = key.index;
      _lastSyncedPageId = pageId;
      _labelController.text = key.label;
      _launcherTargetController.text = key.action.target;
      _launcherArgsController.text = key.action.args.join(' ');
      _haEntityController.text = key.action.entityId;
      final firstTextStep = key.action.sequenceSteps
          .where((s) => s.type == MacroStepType.text)
          .firstOrNull;
      _macroTextController.text = firstTextStep?.value ?? '';
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _launcherTargetController.dispose();
    _launcherArgsController.dispose();
    _haEntityController.dispose();
    _macroTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncControllersWithSelectedKey();
    final vm = widget.viewModel;
    final keyCfg = vm.selectedKeyConfig;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.panelSurface,
        border: Border(
          left: BorderSide(color: AppTheme.borderSubtle, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildKeyHeaderCard(keyCfg),
            const SizedBox(height: 14),
            _buildAppearanceCard(keyCfg),
            const SizedBox(height: 14),
            _buildActionCategoryCard(keyCfg),
            const SizedBox(height: 14),
            _buildCategoryParametersCard(keyCfg),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyHeaderCard(KeyButtonConfig keyCfg) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Color(keyCfg.colorHex).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(keyCfg.colorHex), width: 2),
              ),
              child: Icon(
                Sk18IconCatalog.resolve(keyCfg.iconName),
                color: Color(keyCfg.colorHex),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Key K${keyCfg.index + 1} Inspector',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Slot (${keyCfg.col}, ${keyCfg.row}) • ${keyCfg.action.category.displayName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard(KeyButtonConfig keyCfg) {
    final vm = widget.viewModel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Keycap Appearance',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            const Text(
              'Button Label',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('key_label_field'),
              controller: _labelController,
              decoration: const InputDecoration(
                hintText: 'Enter button label...',
              ),
              onChanged: vm.updateSelectedKeyLabel,
            ),
            const SizedBox(height: 12),
            const Text(
              'Icon',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: Sk18IconCatalog.iconNames.map((iconName) {
                final isSelected = keyCfg.iconName == iconName;
                return InkWell(
                  key: Key('icon_chip_$iconName'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => vm.updateSelectedKeyIcon(iconName),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryAccent.withValues(alpha: 0.25)
                          : AppTheme.studioBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : AppTheme.borderSubtle,
                      ),
                    ),
                    child: Icon(
                      Sk18IconCatalog.resolve(iconName),
                      size: 18,
                      color: isSelected
                          ? AppTheme.primaryAccent
                          : Colors.white70,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Accent Color',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppTheme.keyColorPalette.map((colorHex) {
                final isSelected = keyCfg.colorHex == colorHex;
                return InkWell(
                  key: Key('color_swatch_${colorHex.toRadixString(16)}'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => vm.updateSelectedKeyColor(colorHex),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(colorHex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.black,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCategoryCard(KeyButtonConfig keyCfg) {
    final vm = widget.viewModel;
    final currentCategory = keyCfg.action.category;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Action Category',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ActionCategory.values.map((category) {
                final isSelected = category == currentCategory;
                return ChoiceChip(
                  key: Key('category_chip_${category.jsonValue}'),
                  label: Text(
                    category.displayName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    vm.updateSelectedKeyAction(
                      keyCfg.action.copyWith(category: category),
                    );
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryParametersCard(KeyButtonConfig keyCfg) {
    final action = keyCfg.action;
    switch (action.category) {
      case ActionCategory.none:
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No action assigned. Choose Host Launcher, Macro, Home Assistant, or Audio above.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        );
      case ActionCategory.hostLauncher:
        return _buildHostLauncherEditor(action);
      case ActionCategory.macro:
        return _buildMacroEditor(action);
      case ActionCategory.homeAssistant:
        return _buildHomeAssistantEditor(action);
      case ActionCategory.audio:
        return _buildAudioEditor(action);
    }
  }

  Widget _buildHostLauncherEditor(ButtonAction action) {
    final vm = widget.viewModel;

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
                    vm.updateSelectedKeyAction(
                      action.copyWith(launcherType: type),
                    );
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
              controller: _launcherTargetController,
              decoration: const InputDecoration(
                hintText: 'e.g. Terminal, git status, or https://...',
              ),
              onChanged: (val) {
                vm.updateSelectedKeyAction(action.copyWith(target: val));
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
              controller: _launcherArgsController,
              decoration: const InputDecoration(
                hintText: '--single-instance',
              ),
              onChanged: (val) {
                final splitArgs = val
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((s) => s.isNotEmpty)
                    .toList();
                vm.updateSelectedKeyAction(action.copyWith(args: splitArgs));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroEditor(ButtonAction action) {
    final vm = widget.viewModel;
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
                    vm.updateSelectedKeyAction(
                      action.copyWith(macroType: mType),
                    );
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
                      vm.updateSelectedKeyAction(
                        action.copyWith(modifiers: nextMods),
                      );
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
                    vm.updateSelectedKeyAction(action.copyWith(keycode: kc));
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
                controller: _macroTextController,
                decoration: const InputDecoration(
                  hintText: 'e.g. flutter test',
                ),
                onChanged: (val) {
                  vm.updateSelectedKeyAction(
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
                    onPressed: () => vm.updateSelectedKeyAction(
                      action.copyWith(wheelV: action.wheelV - 1),
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => vm.updateSelectedKeyAction(
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

  Widget _buildHomeAssistantEditor(ButtonAction action) {
    final vm = widget.viewModel;
    final entities = vm.haEntities;
    final liveEntity = entities[action.entityId];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Home Assistant Action',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                IconButton(
                  key: const Key('refresh_ha_btn'),
                  tooltip: 'Refresh Home Assistant Telemetry',
                  visualDensity: VisualDensity.compact,
                  onPressed: vm.refreshHomeAssistantStates,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<HaActionType>(
              key: const Key('ha_action_type_dropdown'),
              initialValue: action.haType,
              isExpanded: true,
              items: HaActionType.values
                  .map(
                    (t) => DropdownMenuItem<HaActionType>(
                      value: t,
                      child: Text(
                        '${t.displayName} (${t.jsonValue})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  vm.updateSelectedKeyAction(action.copyWith(haType: val));
                }
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Entity ID',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('ha_entity_field'),
              controller: _haEntityController,
              decoration: const InputDecoration(
                hintText: 'e.g. light.office_main or climate.studio_hvac',
              ),
              onChanged: (val) {
                vm.updateSelectedKeyAction(
                  action.copyWith(entityId: val.trim()),
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entities.keys.map((entityId) {
                return ActionChip(
                  key: Key('ha_entity_preset_$entityId'),
                  label: Text(entityId, style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    _haEntityController.text = entityId;
                    vm.updateSelectedKeyAction(
                      action.copyWith(entityId: entityId),
                    );
                  },
                );
              }).toList(),
            ),
            if (liveEntity != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.studioBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Text(
                  'Live State: ${liveEntity.friendlyName} = ${liveEntity.state.toUpperCase()}'
                  '${liveEntity.brightnessPct != null ? ' (${liveEntity.brightnessPct}%)' : ''}'
                  '${liveEntity.targetTemperature != null ? ' (→ ${liveEntity.targetTemperature}°)' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.successEmerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioEditor(ButtonAction action) {
    final vm = widget.viewModel;
    final wavList = vm.wavFiles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'On-Device WAV Audio Settings',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Device WAV File (/data/sound/*.wav)',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: wavList.map((entry) {
                final isSelected = action.audioFilePath == entry.filePath;
                return ChoiceChip(
                  key: Key('wav_chip_${entry.fileName}'),
                  label: Text(
                    entry.fileName,
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    vm.updateSelectedKeyAction(
                      action.copyWith(audioFilePath: entry.filePath),
                    );
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            if (vm.wavUploadProgress != null) ...[
              LinearProgressIndicator(value: vm.wavUploadProgress),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const Key('play_wav_btn'),
                  onPressed: () => vm.playWavFile(action.audioFilePath),
                  icon: const Icon(Icons.volume_up_rounded, size: 16),
                  label: const Text('Play WAV', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  key: const Key('stop_wav_btn'),
                  onPressed: vm.stopWavPlayback,
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Stop', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  key: const Key('upload_wav_btn'),
                  onPressed: () =>
                      vm.uploadGeneratedSampleWav('studio_beep.wav'),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                  label: const Text(
                    'Upload WAV',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
