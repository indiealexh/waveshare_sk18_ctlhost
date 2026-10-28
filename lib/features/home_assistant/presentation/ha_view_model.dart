// ignore_for_file: prefer_initializing_formals

import '../../home_assistant/data/home_assistant_repository.dart';
import '../../home_assistant/domain/ha_entity_state.dart';
import '../../studio/presentation/studio_session.dart';

class HaViewModel extends StudioSubViewModel {
  final HomeAssistantRepository _homeAssistantRepository;

  HaViewModel({
    required StudioSession session,
    required HomeAssistantRepository homeAssistantRepository,
  }) : _homeAssistantRepository = homeAssistantRepository,
       super(session);

  Map<String, HaEntityState> get haEntities =>
      _homeAssistantRepository.entities;
  String get haBaseUrl => _homeAssistantRepository.baseUrl;
  bool get isHaConfigured => _homeAssistantRepository.isConfigured;

  void updateHomeAssistantCredentials({
    required String baseUrl,
    required String token,
    bool notifyChange = true,
  }) {
    _homeAssistantRepository.updateCredentials(baseUrl: baseUrl, token: token);
    session.setStatus('Updated Home Assistant endpoint: $baseUrl');
    if (notifyChange) notify(markCanvasDirty: false);
  }

  Future<void> refreshHomeAssistantStates({bool notifyChange = true}) async {
    try {
      await _homeAssistantRepository.refreshStates();
      session.setStatus('Refreshed Home Assistant entity telemetry');
    } catch (e) {
      session.setStatus('HA refresh error: $e', isError: true);
    }
    if (notifyChange) notify();
  }

  void handleHaStateUpdated(
    Map<String, dynamic> eventParameters, {
    bool notifyChange = true,
  }) {
    final updated = _homeAssistantRepository.applyHaStateUpdatedEvent(
      eventParameters,
    );
    session.setStatus(
      'HA Telemetry: ${updated.entityId} -> ${updated.state.toUpperCase()}',
    );
    if (notifyChange) notify();
  }
}
