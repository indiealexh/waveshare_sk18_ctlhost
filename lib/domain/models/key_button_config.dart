import 'button_action.dart';

class KeyButtonConfig {
  final int index; // 0..17
  final int col; // 0..5 (landscape) or 0..2 (portrait)
  final int row; // 0..2 (landscape) or 0..5 (portrait)
  final String label;
  final String iconName;
  final int colorHex; // ARGB 32-bit int, e.g. 0xFFFFB300
  final ButtonAction action;

  const KeyButtonConfig({
    required this.index,
    required this.col,
    required this.row,
    required this.label,
    this.iconName = 'bolt',
    this.colorHex = 0xFF38BDF8,
    this.action = const ButtonAction(),
  });

  String get colorCssHex {
    final rgb = colorHex & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static int parseColorHex(Object? raw, {int fallback = 0xFF38BDF8}) {
    if (raw is int) {
      return (raw & 0xFF000000) == 0 ? (0xFF000000 | raw) : raw;
    }
    if (raw is String) {
      final cleaned = raw.trim().replaceFirst('#', '').replaceFirst('0x', '');
      if (cleaned.length == 6) {
        final val = int.tryParse(cleaned, radix: 16);
        if (val != null) return 0xFF000000 | val;
      } else if (cleaned.length == 8) {
        final val = int.tryParse(cleaned, radix: 16);
        if (val != null) return val;
      }
    }
    return fallback;
  }

  KeyButtonConfig copyWith({
    int? index,
    int? col,
    int? row,
    String? label,
    String? iconName,
    int? colorHex,
    ButtonAction? action,
  }) {
    return KeyButtonConfig(
      index: index ?? this.index,
      col: col ?? this.col,
      row: row ?? this.row,
      label: label ?? this.label,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
      action: action ?? this.action,
    );
  }

  factory KeyButtonConfig.fromJson(Map<String, dynamic> json) {
    final index = (json['index'] as num?)?.toInt() ?? 0;
    final col = (json['col'] as num?)?.toInt() ?? (index % 6);
    final row = (json['row'] as num?)?.toInt() ?? (index ~/ 6);
    final rawAction = json['action'];

    return KeyButtonConfig(
      index: index,
      col: col,
      row: row,
      label: (json['label'] as String?) ?? 'Key ${index + 1}',
      iconName:
          (json['iconName'] as String? ?? json['icon'] as String?) ?? 'bolt',
      colorHex: parseColorHex(json['colorHex'] ?? json['color']),
      action: rawAction is Map<String, dynamic>
          ? ButtonAction.fromJson(rawAction)
          : const ButtonAction(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'col': col,
      'row': row,
      'label': label,
      'icon': iconName,
      'iconName': iconName,
      'color': colorCssHex,
      'colorHex': colorHex,
      'action': action.toJson(),
    };
  }
}
