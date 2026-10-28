import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/action_plugin.dart';
import '../../domain/button_action.dart';

class HaActionEditor extends StatefulWidget {
  final ActionEditorScope scope;

  const HaActionEditor({super.key, required this.scope});

  @override
  State<HaActionEditor> createState() => _HaActionEditorState();
}

class _HaActionEditorState extends State<HaActionEditor> {
  late final TextEditingController _entityController;
  int _lastSyncedKeyIndex = -1;
  String _lastSyncedPageId = '';

  @override
  void initState() {
    super.initState();
    _entityController = TextEditingController();
    _syncControllerWithSelectedKey();
  }

  @override
  void didUpdateWidget(covariant HaActionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerWithSelectedKey();
  }

  void _syncControllerWithSelectedKey() {
    final key = widget.scope.keyConfig;
    final pageId = widget.scope.vm.activePage.id;
    if (_lastSyncedKeyIndex != key.index || _lastSyncedPageId != pageId) {
      _lastSyncedKeyIndex = key.index;
      _lastSyncedPageId = pageId;
      _entityController.text = key.action.entityId;
    }
  }

  @override
  void dispose() {
    _entityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final vm = scope.vm;
    final action = scope.action;
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
                  scope.update(action.copyWith(haType: val));
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
              controller: _entityController,
              decoration: const InputDecoration(
                hintText: 'e.g. light.office_main or climate.studio_hvac',
              ),
              onChanged: (val) {
                scope.update(action.copyWith(entityId: val.trim()));
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
                    _entityController.text = entityId;
                    scope.update(action.copyWith(entityId: entityId));
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
}
