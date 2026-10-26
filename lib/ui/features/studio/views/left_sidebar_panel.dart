import 'package:flutter/material.dart';

import '../../../../data/services/serial_transport_service.dart';
import '../../../../domain/models/sk18_geometry.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

class LeftSidebarPanel extends StatelessWidget {
  final StudioViewModel viewModel;

  const LeftSidebarPanel({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final profile = viewModel.activeProfile;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.panelSurface,
        border: Border(
          right: BorderSide(color: AppTheme.borderSubtle, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConnectionSection(context),
            const SizedBox(height: 14),
            _buildProfilesAndPagesSection(context),
            const SizedBox(height: 14),
            _buildHardwareControlsSection(context, profile.backlight, profile.volume),
            const SizedBox(height: 14),
            _buildCalibrationSection(context, profile.offsetX, profile.offsetY),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSection(BuildContext context) {
    final ports = viewModel.availablePorts;
    final activePort = ports.contains(viewModel.selectedPort)
        ? viewModel.selectedPort
        : (ports.isNotEmpty ? ports.first : 'simulator://sk18');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.usb_rounded,
                  size: 18,
                  color: AppTheme.primaryAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${viewModel.activeDeviceModel.code} Device',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: viewModel.isDeviceConnected
                        ? AppTheme.successEmerald.withValues(alpha: 0.2)
                        : AppTheme.borderSubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    viewModel.isDeviceConnected
                        ? (viewModel.isSimulatorMode ? 'SIM' : 'USB')
                        : 'OFF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: viewModel.isDeviceConnected
                          ? AppTheme.successEmerald
                          : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('port_selector_dropdown'),
              initialValue: activePort,
              isExpanded: true,
              items: ports
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p,
                      child: Text(
                        p == SerialPortDiscovery.simulatorPortUri
                            ? 'Virtual SK18 Simulator'
                            : (p == SerialPortDiscovery.mk10SimulatorPortUri
                                  ? 'Virtual MK10 Simulator'
                                  : p),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  viewModel.setSelectedPort(val);
                }
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const Key('connect_device_btn'),
                  onPressed: () {
                    if (viewModel.isDeviceConnected) {
                      viewModel.disconnectDevice();
                    } else {
                      viewModel.connectToPort();
                    }
                  },
                  icon: Icon(
                    viewModel.isDeviceConnected
                        ? Icons.link_off_rounded
                        : Icons.link_rounded,
                    size: 16,
                  ),
                  label: Text(
                    viewModel.isDeviceConnected ? 'Disconnect' : 'Connect',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('sync_firmware_btn'),
                  onPressed: viewModel.isDeviceConnected
                      ? viewModel.syncLayoutToDevice
                      : null,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text(
                    'Sync Config',
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

  Widget _buildProfilesAndPagesSection(BuildContext context) {
    final profiles = viewModel.profiles;
    final pages = viewModel.activeProfile.pages;
    final activeModel = viewModel.activeDeviceModel;
    final spec = viewModel.activeModelSpec;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.layers_rounded,
                  size: 18,
                  color: AppTheme.primaryAccent,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Profiles & Pages',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('add_profile_btn'),
                  tooltip: 'Create New ${activeModel.code} Profile',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    viewModel.createNewProfile(
                      '${activeModel.code} Profile ${profiles.length + 1}',
                      model: activeModel,
                    );
                  },
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  key: const Key('device_model_sk18_chip'),
                  label: const Text(
                    'SK18 (18 Keys)',
                    style: TextStyle(fontSize: 11),
                  ),
                  selected: activeModel == WaveshareModel.sk18,
                  onSelected: (_) =>
                      viewModel.switchDeviceModel(WaveshareModel.sk18),
                ),
                ChoiceChip(
                  key: const Key('device_model_mk10_chip'),
                  label: const Text(
                    'MK10 (10 Keys)',
                    style: TextStyle(fontSize: 11),
                  ),
                  selected: activeModel == WaveshareModel.mk10,
                  onSelected: (_) =>
                      viewModel.switchDeviceModel(WaveshareModel.mk10),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const Key('profile_selector_dropdown'),
              initialValue: viewModel.activeProfileIndex,
              isExpanded: true,
              items: List.generate(profiles.length, (idx) {
                final p = profiles[idx];
                return DropdownMenuItem<int>(
                  value: idx,
                  child: Text(
                    '[${p.deviceModel.code}] ${p.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }),
              onChanged: (idx) {
                if (idx != null) {
                  viewModel.selectProfile(idx);
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pages (${spec.totalKeys} keys/page)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('add_page_btn'),
                  onPressed: () {
                    viewModel.addNewPage('Page ${pages.length + 1}');
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Page', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(pages.length, (pageIdx) {
                final isSelected = pageIdx == viewModel.activePageIndex;
                return ChoiceChip(
                  key: Key('page_chip_$pageIdx'),
                  label: Text(
                    pages[pageIdx].name,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: isSelected,
                  onSelected: (_) => viewModel.selectPage(pageIdx),
                );
              }),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('export_json_btn'),
                  onPressed: () => _showJsonDialog(context, isImport: false),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Export', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  key: const Key('import_json_btn'),
                  onPressed: () => _showJsonDialog(context, isImport: true),
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Import', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHardwareControlsSection(
    BuildContext context,
    int backlight,
    int volume,
  ) {
    final isLandscape = viewModel.activeProfile.landscapeMode;
    final isUpsideDown = viewModel.activeProfile.upsideDown;
    final spec = viewModel.activeModelSpec;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: AppTheme.primaryAccent,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Display & Audio',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isLandscape
                        ? 'Landscape (${spec.landscapeCols}x${spec.landscapeRows})'
                        : 'Portrait (${spec.portraitCols}x${spec.portraitRows})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Switch(
                  key: const Key('orientation_switch'),
                  value: isLandscape,
                  onChanged: viewModel.setLandscapeMode,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Upside Down (180°)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Switch(
                  key: const Key('upside_down_switch'),
                  value: isUpsideDown,
                  onChanged: viewModel.setUpsideDown,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Backlight',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '$backlight%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Slider(
              key: const Key('backlight_slider'),
              value: backlight.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '$backlight%',
              onChanged: (v) => viewModel.setBacklight(v.round()),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Speaker Volume',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '$volume / 7',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Slider(
              key: const Key('volume_slider'),
              value: volume.toDouble(),
              min: 0,
              max: 7,
              divisions: 7,
              label: '$volume',
              onChanged: (v) => viewModel.setVolume(v.round()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalibrationSection(
    BuildContext context,
    int offsetX,
    int offsetY,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.straighten_rounded,
                  size: 18,
                  color: AppTheme.primaryAccent,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Key Alignment (+12px Fix)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('reset_calibration_btn'),
                  onPressed: () =>
                      viewModel.setCalibrationOffsets(offsetX: 0, offsetY: 0),
                  child: const Text('Reset', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Offset X: $offsetX px',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  key: const Key('offset_x_dec'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Shift Left 1 px',
                  onPressed: () =>
                      viewModel.setCalibrationOffsets(offsetX: offsetX - 1),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                ),
                IconButton(
                  key: const Key('offset_x_inc'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Shift Right 1 px',
                  onPressed: () =>
                      viewModel.setCalibrationOffsets(offsetX: offsetX + 1),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Offset Y: $offsetY px',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  key: const Key('offset_y_dec'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Shift Up 1 px',
                  onPressed: () =>
                      viewModel.setCalibrationOffsets(offsetY: offsetY - 1),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                ),
                IconButton(
                  key: const Key('offset_y_inc'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Shift Down 1 px',
                  onPressed: () =>
                      viewModel.setCalibrationOffsets(offsetY: offsetY + 1),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showJsonDialog(
    BuildContext context, {
    required bool isImport,
  }) async {
    final controller = TextEditingController(
      text: isImport ? '' : viewModel.exportProfileJson(),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            isImport ? 'Import sk18_config.json' : 'Export sk18_config.json',
          ),
          content: SizedBox(
            width: 520,
            child: TextField(
              key: const Key('json_dialog_textfield'),
              controller: controller,
              maxLines: 12,
              readOnly: !isImport,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: isImport
                    ? 'Paste sk18_config.json content here...'
                    : null,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            if (isImport)
              ElevatedButton(
                key: const Key('confirm_import_json_btn'),
                onPressed: () {
                  viewModel.importProfileJson(controller.text);
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Import Profile'),
              ),
          ],
        );
      },
    );
    controller.dispose();
  }
}
