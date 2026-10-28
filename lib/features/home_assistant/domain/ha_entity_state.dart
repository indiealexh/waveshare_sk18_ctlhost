class HaEntityState {
  final String entityId;
  final String domain;
  final String friendlyName;
  final String state;
  final Map<String, dynamic> attributes;

  const HaEntityState({
    required this.entityId,
    required this.domain,
    required this.friendlyName,
    required this.state,
    this.attributes = const {},
  });

  bool get isOn {
    final normalized = state.toLowerCase();
    return normalized == 'on' ||
        normalized == 'playing' ||
        normalized == 'heat' ||
        normalized == 'cool' ||
        normalized == 'heat_cool' ||
        normalized == 'auto';
  }

  int? get brightnessPct {
    final pctAttr = attributes['brightness_pct'];
    if (pctAttr is num) {
      return pctAttr.round().clamp(0, 100);
    }
    final rawBrightness = attributes['brightness'];
    if (rawBrightness is num) {
      return ((rawBrightness.toDouble() / 255.0) * 100.0).round().clamp(0, 100);
    }
    return isOn && domain == 'light' ? 100 : (domain == 'light' ? 0 : null);
  }

  double? get currentTemperature {
    final val = attributes['current_temperature'];
    return val is num ? val.toDouble() : null;
  }

  double? get targetTemperature {
    final val = attributes['temperature'];
    return val is num ? val.toDouble() : null;
  }

  double get minTemp {
    final val = attributes['min_temp'];
    return val is num ? val.toDouble() : 16.0;
  }

  double get maxTemp {
    final val = attributes['max_temp'];
    return val is num ? val.toDouble() : 30.0;
  }

  List<String> get hvacModes {
    final raw = attributes['hvac_modes'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const ['off', 'heat', 'cool', 'auto'];
  }

  HaEntityState copyWith({
    String? entityId,
    String? domain,
    String? friendlyName,
    String? state,
    Map<String, dynamic>? attributes,
  }) {
    return HaEntityState(
      entityId: entityId ?? this.entityId,
      domain: domain ?? this.domain,
      friendlyName: friendlyName ?? this.friendlyName,
      state: state ?? this.state,
      attributes: attributes ?? this.attributes,
    );
  }

  factory HaEntityState.fromJson(Map<String, dynamic> json) {
    final id =
        (json['entityId'] as String?) ??
        (json['entity_id'] as String?) ??
        'unknown.entity';
    final attrs =
        (json['attributes'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final extractedDomain = id.contains('.') ? id.split('.').first : 'switch';
    final name =
        (json['friendlyName'] as String?) ??
        (attrs['friendly_name'] as String?) ??
        id;
    return HaEntityState(
      entityId: id,
      domain: (json['domain'] as String?) ?? extractedDomain,
      friendlyName: name,
      state: (json['state'] as String?) ?? 'off',
      attributes: Map<String, dynamic>.from(attrs),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entityId': entityId,
      'domain': domain,
      'friendlyName': friendlyName,
      'state': state,
      'attributes': attributes,
    };
  }
}
