import '../domain/action_plugin.dart';
import 'audio/audio_plugin.dart';
import 'host_launcher/host_launcher_plugin.dart';
import 'home_assistant/ha_action_plugin.dart';
import 'macro/macro_plugin.dart';
import 'none/no_action_plugin.dart';

List<ActionPlugin> defaultActionPlugins() => [
  NoActionPlugin(),
  HostLauncherPlugin(),
  MacroPlugin(),
  HomeAssistantActionPlugin(),
  AudioPlugin(),
];
