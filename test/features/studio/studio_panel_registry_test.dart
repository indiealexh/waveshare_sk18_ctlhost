import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/features/studio/presentation/studio_panel_registry.dart';

void main() {
  test('default panel registry preserves wide and compact layout orders', () {
    final registry = StudioPanelRegistry.defaults;

    expect(
      registry.wideOrder.map((panel) => panel.id).toList(),
      ['profiles', 'canvas', 'inspector'],
    );
    expect(
      registry.wideOrder.map((panel) => panel.fixedWidth).toList(),
      [300, null, 340],
    );
    expect(
      registry.compactTabOrder.map((panel) => panel.id).toList(),
      ['canvas', 'inspector', 'profiles'],
    );
    expect(
      registry.compactTabOrder.map((panel) => panel.tabTitle).toList(),
      ['LCD Canvas', 'Key Inspector', 'Profiles & Device'],
    );
  });
}
