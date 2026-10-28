import '../plugins/default_action_plugins.dart';
import 'action_plugin.dart';
import 'button_action.dart';

class ActionPluginRegistry {
  static ActionPluginRegistry? _instance;

  static ActionPluginRegistry get instance =>
      _instance ??= ActionPluginRegistry.defaults();

  static set instance(ActionPluginRegistry registry) => _instance = registry;

  final List<ActionPlugin> ordered;
  final Map<ActionCategory, ActionPlugin> _byCategory;

  ActionPluginRegistry({required List<ActionPlugin> ordered})
    : ordered = List.unmodifiable(ordered),
      _byCategory = Map.unmodifiable(<ActionCategory, ActionPlugin>{
        for (final plugin in ordered) plugin.category: plugin,
      });

  factory ActionPluginRegistry.defaults() =>
      ActionPluginRegistry(ordered: defaultActionPlugins());

  ActionPlugin forCategory(ActionCategory category) {
    final plugin = _byCategory[category];
    if (plugin == null) {
      throw StateError('No action plugin registered for $category.');
    }
    return plugin;
  }

  ActionCategory resolveCategory(Map<String, dynamic> json) {
    final rawCategory = json['category'] as String?;
    if (rawCategory == null) return ActionCategory.none;
    for (final plugin in ordered) {
      if (plugin.matchesJson(json)) return plugin.category;
    }
    return ActionCategory.none;
  }
}
