import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../actions/domain/button_action.dart';
import '../domain/ha_action_handler_registry.dart';
import '../domain/ha_entity_state.dart';

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

    final plannedAction = action.entityId.isEmpty
        ? action.copyWith(entityId: entityId)
        : action;
    final call = HaActionHandlerRegistry.instance
        .forType(action.haType)
        .plan(plannedAction, existing, domain);

    _callHistory.add(
      HomeAssistantServiceCallRecord(
        domain: call.domain,
        service: call.service,
        serviceData: call.data,
      ),
    );

    if (isConfigured) {
      final uri = Uri.parse(
        '$_baseUrl/api/services/${call.domain}/${call.service}',
      );
      final response = await _httpClient.post(
        uri,
        headers: _headers,
        body: jsonEncode(call.data),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Home Assistant service ${call.domain}.${call.service} failed (HTTP ${response.statusCode})',
        );
      }
    }

    return call.nextState;
  }

  void dispose() {
    _httpClient.close();
  }
}
