import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'studio_panel_registry.dart';
import 'studio_view_model.dart';

class StudioScreen extends StatelessWidget {
  final StudioViewModel viewModel;

  const StudioScreen({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final panelRegistry = StudioPanelRegistry.defaults;

    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopStudioHeader(context),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 1020) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: panelRegistry.wideOrder.map((panel) {
                            final child = panel.build(viewModel);
                            final width = panel.fixedWidth;
                            return width == null
                                ? Expanded(child: child)
                                : SizedBox(width: width, child: child);
                          }).toList(),
                        );
                      }

                      // Compact responsive layout for smaller windows
                      final compactPanels = panelRegistry.compactTabOrder;
                      return DefaultTabController(
                        length: compactPanels.length,
                        child: Column(
                          children: [
                            TabBar(
                              tabs: compactPanels
                                  .map((panel) => Tab(text: panel.tabTitle))
                                  .toList(),
                            ),
                            Expanded(
                              child: TabBarView(
                                children: compactPanels
                                    .map((panel) => panel.build(viewModel))
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _buildBottomStatusBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopStudioHeader(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.panelSurface,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.keyboard_command_key_rounded,
            color: AppTheme.primaryAccent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'wavectl_host  •  Waveshare ${viewModel.activeDeviceModel.code} Custom Button Studio',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Flexible(
            child: Text(
              '${viewModel.activeProfile.name} / ${viewModel.activePage.name}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    final latestLog = viewModel.executionLogs.firstOrNull;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.panelSurface,
        border: Border(
          top: BorderSide(color: AppTheme.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            viewModel.isStatusError
                ? Icons.cancel_rounded
                : (viewModel.isDeviceConnected
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded),
            key: const Key('status_bar_icon'),
            size: 15,
            color: viewModel.isStatusError
                ? AppTheme.dangerRose
                : (viewModel.isDeviceConnected
                      ? AppTheme.successEmerald
                      : AppTheme.warningAmber),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              viewModel.statusMessage,
              key: const Key('status_bar_message'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: viewModel.isStatusError ? AppTheme.dangerRose : null,
              ),
            ),
          ),
          if (latestLog != null)
            Flexible(
              child: Text(
                'Last Action: [K${latestLog.keyIndex + 1}] ${latestLog.summary}',
                key: const Key('last_action_summary'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.primaryAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
