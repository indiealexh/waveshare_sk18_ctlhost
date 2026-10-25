import 'dart:io';

class HaEnvCredentials {
  final String baseUrl;
  final String token;

  const HaEnvCredentials({
    this.baseUrl = '',
    this.token = '',
  });

  bool get hasCredentials =>
      baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;
}

/// Parses `.env` files to load `HOME_ASSISTANT_BASE_URL` and `HOME_ASSISTANT_TOKEN`
/// without hardcoding secrets in source control.
class EnvConfigLoader {
  static const String baseUrlKey = 'HOME_ASSISTANT_BASE_URL';
  static const String tokenKey = 'HOME_ASSISTANT_TOKEN';

  const EnvConfigLoader._();

  static Map<String, String> parseEnvString(String content) {
    final result = <String, String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final normalized = line.startsWith('export ')
          ? line.substring(7).trim()
          : line;
      final eqIndex = normalized.indexOf('=');
      if (eqIndex <= 0) continue;

      final key = normalized.substring(0, eqIndex).trim();
      var value = normalized.substring(eqIndex + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }

  static Future<HaEnvCredentials> loadFromFile({
    String filePath = '.env',
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return const HaEnvCredentials();
      }
      final content = file.readAsStringSync();
      final map = parseEnvString(content);
      return HaEnvCredentials(
        baseUrl: map[baseUrlKey] ?? '',
        token: map[tokenKey] ?? '',
      );
    } catch (_) {
      return const HaEnvCredentials();
    }
  }
}
