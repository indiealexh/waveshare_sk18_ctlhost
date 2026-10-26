import 'package:flutter/material.dart';

import '../../../../domain/models/sk18_geometry.dart';
import '../../../core/rendering/sk18_canvas_painter.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

class CenterCanvasPanel extends StatelessWidget {
  final StudioViewModel viewModel;

  const CenterCanvasPanel({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final profile = viewModel.activeProfile;
    final page = viewModel.activePage;
    final isPortrait = !profile.landscapeMode;
    final logicalWidth = isPortrait
        ? Sk18Geometry.portraitWidth.toDouble()
        : Sk18Geometry.landscapeWidth.toDouble();
    final logicalHeight = isPortrait
        ? Sk18Geometry.portraitHeight.toDouble()
        : Sk18Geometry.landscapeHeight.toDouble();

    final keyRects = Sk18Geometry.computeKeyRects(
      isPortrait: isPortrait,
      offsetX: profile.offsetX,
      offsetY: profile.offsetY,
    );

    return Container(
      color: AppTheme.studioBackground,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCanvasToolbar(context),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: logicalWidth / logicalHeight,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.borderSubtle,
                      width: 3,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scaleX = constraints.maxWidth / logicalWidth;
                      final scaleY = constraints.maxHeight / logicalHeight;

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            key: const Key('sk18_lcd_custom_paint'),
                            painter: Sk18CanvasPainter(
                              page: page,
                              isPortrait: isPortrait,
                              haEntities: viewModel.haEntities,
                              pressedKeyIndices: viewModel.pressedKeyIndices,
                              selectedKeyIndex: viewModel.selectedKeyIndex,
                              offsetX: profile.offsetX,
                              offsetY: profile.offsetY,
                              profileName: profile.name,
                              statusText: viewModel.isDeviceConnected
                                  ? (viewModel.isSimulatorMode
                                        ? 'SIMULATOR'
                                        : 'USB LIVE')
                                  : 'OFFLINE',
                              clockString: viewModel.clockString,
                            ),
                          ),
                          // Accessible interactive overlays for all 18 keys
                          for (int i = 0; i < keyRects.length; i++)
                            Positioned(
                              left: (keyRects[i].x * scaleX).clamp(
                                0.0,
                                constraints.maxWidth,
                              ),
                              top: (keyRects[i].y * scaleY).clamp(
                                0.0,
                                constraints.maxHeight,
                              ),
                              width: (keyRects[i].width * scaleX).clamp(
                                10.0,
                                constraints.maxWidth,
                              ),
                              height: (keyRects[i].height * scaleY).clamp(
                                10.0,
                                constraints.maxHeight,
                              ),
                              child: Semantics(
                                label:
                                    'Key ${i + 1}: ${page.keys[i].label} (${page.keys[i].action.category.displayName})',
                                button: true,
                                selected: viewModel.selectedKeyIndex == i,
                                child: Tooltip(
                                  message:
                                      'K${i + 1}: ${page.keys[i].label}',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      key: Key('lcd_key_$i'),
                                      borderRadius: BorderRadius.circular(
                                        Sk18Geometry.cornerRadius * scaleX,
                                      ),
                                      onTap: () =>
                                          viewModel.handleCanvasKeyTap(i),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildQuickKeySelectorStrip(),
        ],
      ),
    );
  }

  Widget _buildCanvasToolbar(BuildContext context) {
    final selectedKey = viewModel.selectedKeyConfig;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.grid_on_rounded,
                  size: 18,
                  color: AppTheme.primaryAccent,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'SK18 Live LCD Preview (${viewModel.activeProfile.landscapeMode ? '1280×720' : '720×1280'}${viewModel.activeProfile.upsideDown ? ' • Device Upside Down' : ''})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  key: const Key('upside_down_chip'),
                  label: const Text(
                    'Upside Down',
                    style: TextStyle(fontSize: 12),
                  ),
                  selected: viewModel.activeProfile.upsideDown,
                  onSelected: viewModel.setUpsideDown,
                ),
                FilterChip(
                  key: const Key('test_mode_switch'),
                  label: const Text(
                    'Trigger on Click',
                    style: TextStyle(fontSize: 12),
                  ),
                  selected: viewModel.interactiveTriggerOnTap,
                  onSelected: viewModel.setInteractiveTriggerOnTap,
                ),
                ElevatedButton.icon(
                  key: const Key('trigger_selected_key_btn'),
                  onPressed: viewModel.triggerSelectedKey,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    'Test K${selectedKey.index + 1} (${selectedKey.label})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickKeySelectorStrip() {
    final keys = viewModel.activePage.keys;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(keys.length, (i) {
              final isSelected = i == viewModel.selectedKeyIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: Key('quick_key_chip_$i'),
                  label: Text(
                    'K${i + 1}: ${keys[i].label}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: isSelected,
                  onSelected: (_) => viewModel.selectKey(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
