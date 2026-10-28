import '../../actions/domain/button_action.dart';
import '../domain/ha_entity_state.dart';
import 'env_config_loader.dart';
import 'home_assistant_service.dart';

class HomeAssistantRepository {
  final HomeAssistantService _service;
  final Map<String, HaEntityState> _entities = <String, HaEntityState>{};

  HomeAssistantRepository({
    HomeAssistantService? service,
    Map<String, HaEntityState>? initialEntities,
  }) : _service = service ?? HomeAssistantService() {
    _seedDefaultEntities();
    if (initialEntities != null) {
      _entities.addAll(initialEntities);
    }
  }

  HomeAssistantService get service => _service;
  String get baseUrl => _service.baseUrl;
  bool get isConfigured => _service.isConfigured;
  Map<String, HaEntityState> get entities => Map.unmodifiable(_entities);

  void _seedDefaultEntities() {
    _entities['light.office_main'] = const HaEntityState(
      entityId: 'light.office_main',
      domain: 'light',
      friendlyName: 'Office Light',
      state: 'on',
      attributes: {
        'friendly_name': 'Office Light',
        'brightness': 204,
        'brightness_pct': 80,
      },
    );
    _entities['climate.studio_hvac'] = const HaEntityState(
      entityId: 'climate.studio_hvac',
      domain: 'climate',
      friendlyName: 'Studio AC',
      state: 'cool',
      attributes: {
        'friendly_name': 'Studio AC',
        'current_temperature': 21.5,
        'temperature': 22.0,
        'min_temp': 16.0,
        'max_temp': 30.0,
        'hvac_modes': ['off', 'heat', 'cool', 'auto'],
      },
    );
    _entities['switch.desk_fan'] = const HaEntityState(
      entityId: 'switch.desk_fan',
      domain: 'switch',
      friendlyName: 'Desk Fan',
      state: 'off',
      attributes: {'friendly_name': 'Desk Fan'},
    );
    _entities['scene.focus_mode'] = const HaEntityState(
      entityId: 'scene.focus_mode',
      domain: 'scene',
      friendlyName: 'Focus Mode',
      state: 'scening',
      attributes: {'friendly_name': 'Focus Mode'},
    );
  }

  Future<void> initializeFromEnv({String envFilePath = '.env'}) async {
    final creds = await EnvConfigLoader.loadFromFile(filePath: envFilePath);
    if (creds.hasCredentials) {
      _service.updateCredentials(
        baseUrl: creds.baseUrl,
        token: creds.token,
      );
      try {
        await refreshStates();
      } catch (_) {
        // Retain local seeded telemetry if offline
      }
    }
  }

  void updateCredentials({required String baseUrl, required String token}) {
    _service.updateCredentials(baseUrl: baseUrl, token: token);
  }

  Future<Map<String, HaEntityState>> refreshStates() async {
    if (!_service.isConfigured) return entities;
    final remoteStates = await _service.fetchEntityStates();
    for (final st in remoteStates) {
      _entities[st.entityId] = st;
    }
    return entities;
  }

  Future<HaEntityState> executeHaAction(ButtonAction action) async {
    final current = _entities[action.entityId];
    final updated = await _service.executeAction(
      action: action,
      currentState: current,
    );
    _entities[updated.entityId] = updated;
    return updated;
  }

  HaEntityState applyHaStateUpdatedEvent(Map<String, dynamic> eventParams) {
    final updated = HaEntityState.fromJson(eventParams);
    _entities[updated.entityId] = updated;
    return updated;
  }

  void dispose() {
    _service.dispose();
  }
}
