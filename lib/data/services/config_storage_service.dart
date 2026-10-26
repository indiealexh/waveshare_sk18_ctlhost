// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class ConfigStorageService {
  static const String defaultConfigFileName = 'studio_config.json';
  static const String appDirectoryName = 'wavectl_host';

  final String? _overrideFilePath;
  final Map<String, String>? _environmentOverride;
  final String? _operatingSystemOverride;

  const ConfigStorageService({
    String? configFilePath,
    Map<String, String>? environmentOverride,
    String? operatingSystemOverride,
  }) : _overrideFilePath = configFilePath,
       _environmentOverride = environmentOverride,
       _operatingSystemOverride = operatingSystemOverride;

  String resolveConfigFilePath() {
    final override = _overrideFilePath?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }

    final os = (_operatingSystemOverride ?? Platform.operatingSystem)
        .toLowerCase();
    final env = _environmentOverride ?? Platform.environment;
    final pathContext = os == 'windows' ? p.windows : p.posix;

    if (os == 'macos') {
      final home = env['HOME']?.trim();
      if (home != null && home.isNotEmpty) {
        return pathContext.join(
          home,
          'Library',
          'Application Support',
          appDirectoryName,
          defaultConfigFileName,
        );
      }
    } else if (os == 'windows') {
      final appData = env['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return pathContext.join(
          appData,
          appDirectoryName,
          defaultConfigFileName,
        );
      }
      final userProfile = env['USERPROFILE']?.trim();
      if (userProfile != null && userProfile.isNotEmpty) {
        return pathContext.join(
          userProfile,
          'AppData',
          'Roaming',
          appDirectoryName,
          defaultConfigFileName,
        );
      }
    } else {
      final xdgConfigHome = env['XDG_CONFIG_HOME']?.trim();
      if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
        return pathContext.join(
          xdgConfigHome,
          appDirectoryName,
          defaultConfigFileName,
        );
      }
      final home = env['HOME']?.trim();
      if (home != null && home.isNotEmpty) {
        return pathContext.join(
          home,
          '.config',
          appDirectoryName,
          defaultConfigFileName,
        );
      }
    }

    return pathContext.join('.', defaultConfigFileName);
  }

  Future<Map<String, dynamic>?> readConfigJson() async {
    try {
      final file = File(resolveConfigFilePath());
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeConfigJson(Map<String, dynamic> data) async {
    final filePath = resolveConfigFilePath();
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final tempFile = File('$filePath.tmp');
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    await tempFile.writeAsString(encoded, flush: true);
    await tempFile.rename(filePath);
  }
}
