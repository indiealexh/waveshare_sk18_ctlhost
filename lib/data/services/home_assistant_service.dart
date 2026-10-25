import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../domain/models/button_action.dart';
import '../../domain/models/ha_entity_state.dart';

class HomeAssistantServiceCallRecord {
  final String domain;
  final String service;
  final Map<String, dynamic> serviceData;

  const HomeAssistantServiceCallRecord({
    required this.domain,
    required this.service,
    required this.serviceData,
  });
}

/// Stateless/configurable service wrapping Home Assistant REST API calls
/// (`/api/states` and `/api/services/<domain>/<service>`).
class HomeAssistantService {
  final http.Client _httpClient;
  String _baseUrl;
  String _token;
  final List<HomeAssistantServiceCallRecord> _callHistory =
      <HomeAssistantServiceCallRecord>[];

  HomeAssistantService({
    http.Client? httpClient,
    String baseUrl = '',
    String token = '',
  }) : _httpClient = httpClient ?? http.Client(),
       _baseUrl = _normalizeBaseUrl(baseUrl),
       _token = token.trim();

  String get baseUrl => _baseUrl;
  String get token => _token;
  bool get isConfigured => _baseUrl.isNotEmpty && _token.isNotEmpty;
  List<HomeAssistantServiceCallRecord> get callHistory =>
      List.unmodifiable(_callHistory);

  void updateCredentials({required String baseUrl, required String token}) {
    _baseUrl = _normalizeBaseUrl(baseUrl);
    _token = token.trim();
  }

  static String _normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('ws://')) {
      trimmed = 'http://${trimmed.substring(5)}';
    } else if (trimmed.startsWith('wss://')) {
      trimmed = 'https://${trimmed.substring(6)}';
    }
    if (trimmed.endsWith('/api/websocket')) {
      trimmed = trimmed.substring(0, trimmed.length - '/api/websocket'.length);
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $_token',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Fetches filtered Home Assistant states (`light`, `switch`, `fan`,
  /// `input_boolean`, `scene`, `script`, `climate`).
  Future<List<HaEntityState>> fetchEntityStates() async {
    if (!isConfigured) {
      throw StateError('Home Assistant URL and token are not configured.');
    }

    final uri = Uri.parse('$_baseUrl/api/states');
    final response = await _httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch Home Assistant states (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Expected a JSON array from /api/states');
    }

    const supportedDomains = <String>{
      'light',
      'switch',
      'fan',
      'input_boolean',
      'scene',
      'script',
      'climate',
    };

    final states = <HaEntityState>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final state = HaEntityState.fromJson(item);
        if (supportedDomains.contains(state.domain)) {
          states.add(state);
        }
      }
    }
    return states;
  }

  /// Calls a Home Assistant service (`/api/services/<domain>/<service>`) when
  /// credentials are configured, and computes the optimistic updated `HaEntityState`
  /// for immediate keycap telemetry rendering.
  Future<HaEntityState> executeAction({
    required ButtonAction action,
    HaEntityState? currentState,
  }) async {
    final entityId = action.entityId.isEmpty
        ? 'light.office_main'
        : action.entityId;
    final domain = entityId.contains('.')
        ? entityId.split('.').first
        : 'light';

    final existing =
        currentState ??
        HaEntityState(
          entityId: entityId,
          domain: domain,
          friendlyName: entityId,
          state: 'off',
        );

    late final String serviceDomain;
    late final String serviceName;
    late final Map<String, dynamic> serviceData;
    late final HaEntityState nextState;

    switch (action.haType) {
      case HaActionType.toggle:
        if (domain == 'scene' || domain == 'script') {
          serviceDomain = domain;
          serviceName = 'turn_on';
          serviceData = {'entity_id': entityId};
          nextState = existing.copyWith(state: 'on');
        } else {
          serviceDomain = 'homeassistant';
          serviceName = 'toggle';
          serviceData = {'entity_id': entityId};
          nextState = existing.copyWith(
            state: existing.isOn ? 'off' : 'on',
          );
        }
        break;

      case HaActionType.brightnessUp:
      case HaActionType.brightnessDown:
        final signedStep = action.haType == HaActionType.brightnessUp
            ? action.step.round()
            : -action.step.round();
        final currentPct = existing.brightnessPct ?? (existing.isOn ? 100 : 0);
        final updatedPct = (currentPct + signedStep).clamp(0, 100);
        final updatedRawBrightness = ((updatedPct / 100.0) * 255.0).round();

        serviceDomain = 'light';
        serviceName = 'turn_on';
        serviceData = {
          'entity_id': entityId,
          'brightness_step_pct': signedStep,
        };
        nextState = existing.copyWith(
          state: updatedPct > 0 ? 'on' : 'off',
          attributes: {
            ...existing.attributes,
            'brightness': updatedRawBrightness,
            'brightness_pct': updatedPct,
          },
        );
        break;

      case HaActionType.hvacMode:
        final modes = existing.hvacModes.isNotEmpty
            ? existing.hvacModes
            : action.hvacModes;
        String chosenMode;
        if (action.targetHvacMode != null &&
            action.targetHvacMode!.trim().isNotEmpty) {
          chosenMode = action.targetHvacMode!.trim();
        } else {
          final idx = modes.indexOf(existing.state);
          chosenMode = modes[(idx + 1) % modes.length];
        }
        serviceDomain = 'climate';
        serviceName = 'set_hvac_mode';
        serviceData = {
          'entity_id': entityId,
          'hvac_mode': chosenMode,
        };
        nextState = existing.copyWith(state: chosenMode);
        break;

      case HaActionType.hvacTempUp:
      case HaActionType.hvacTempDown:
        final delta = action.haType == HaActionType.hvacTempUp
            ? action.step
            : -action.step;
        final curTarget = existing.targetTemperature ?? 21.0;
        final newTarget = (curTarget + delta).clamp(
          existing.minTemp,
          existing.maxTemp,
        );
        serviceDomain = 'climate';
        serviceName = 'set_temperature';
        serviceData = {
          'entity_id': entityId,
          'temperature': double.parse(newTarget.toStringAsFixed(1)),
        };
        nextState = existing.copyWith(
          state: existing.state == 'off' ? 'heat' : existing.state,
          attributes: {
            ...existing.attributes,
            'temperature': double.parse(newTarget.toStringAsFixed(1)),
          },
        );
        break;
    }

    _callHistory.add(
      HomeAssistantServiceCallRecord(
        domain: serviceDomain,
        service: serviceName,
        serviceData: serviceData,
      ),
    );

    if (isConfigured) {
      final uri = Uri.parse(
        '$_baseUrl/api/services/$serviceDomain/$serviceName',
      );
      final response = await _httpClient.post(
        uri,
        headers: _headers,
        body: jsonEncode(serviceData),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Home Assistant service $serviceDomain.$serviceName failed (HTTP ${response.statusCode})',
        );
      }
    }

    return nextState;
  }

  void dispose() {
    _httpClient.close();
  }
}
