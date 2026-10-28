import 'package:flutter/widgets.dart';

import 'panels/center_canvas_panel.dart';
import 'panels/left_sidebar_panel.dart';
import 'panels/right_inspector_panel.dart';
import 'studio_view_model.dart';

class StudioPanelDescriptor {
  final String id;
  final String tabTitle;
  final double? fixedWidth;
  final Widget Function(StudioViewModel viewModel) build;

  const StudioPanelDescriptor({
    required this.id,
    required this.tabTitle,
    required this.fixedWidth,
    required this.build,
  });
}

class StudioPanelRegistry {
  final List<StudioPanelDescriptor> wideOrder;
  final List<StudioPanelDescriptor> compactTabOrder;

  StudioPanelRegistry({
    required List<StudioPanelDescriptor> wideOrder,
    required List<StudioPanelDescriptor> compactTabOrder,
  }) : wideOrder = List.unmodifiable(wideOrder),
       compactTabOrder = List.unmodifiable(compactTabOrder);

  static final StudioPanelRegistry defaults = _createDefaults();

  static StudioPanelRegistry _createDefaults() {
    final profiles = StudioPanelDescriptor(
      id: 'profiles',
      tabTitle: 'Profiles & Device',
      fixedWidth: 300,
      build: (viewModel) => LeftSidebarPanel(viewModel: viewModel),
    );
    final canvas = StudioPanelDescriptor(
      id: 'canvas',
      tabTitle: 'LCD Canvas',
      fixedWidth: null,
      build: (viewModel) => CenterCanvasPanel(viewModel: viewModel),
    );
    final inspector = StudioPanelDescriptor(
      id: 'inspector',
      tabTitle: 'Key Inspector',
      fixedWidth: 340,
      build: (viewModel) => RightInspectorPanel(viewModel: viewModel),
    );

    return StudioPanelRegistry(
      wideOrder: [profiles, canvas, inspector],
      compactTabOrder: [canvas, inspector, profiles],
    );
  }
}
