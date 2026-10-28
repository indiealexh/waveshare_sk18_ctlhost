import 'package:flutter/material.dart';

import '../../../actions/domain/action_plugin.dart';
import '../../../actions/domain/action_plugin_registry.dart';
import '../../../profiles/domain/key_button_config.dart';
import '../../../../core/rendering/sk18_canvas_painter.dart';
import '../../../../core/theme/app_theme.dart';
import '../studio_view_model.dart';

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
  int _lastSyncedKeyIndex = -1;
  String _lastSyncedPageId = '';

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
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
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
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
              children: ActionPluginRegistry.instance.ordered.map((plugin) {
                final category = plugin.category;
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
    final plugin = ActionPluginRegistry.instance.forCategory(
      keyCfg.action.category,
    );
    return plugin.buildEditor(
      context,
      ActionEditorScope(vm: widget.viewModel, keyConfig: keyCfg),
    );
  }

}
