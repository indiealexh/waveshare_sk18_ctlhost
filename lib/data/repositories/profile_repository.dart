// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/key_button_config.dart';
import '../../domain/models/sk18_profile.dart';
import '../services/config_storage_service.dart';
import '../services/serial_transport_service.dart';

class ProfileRepository {
  final ConfigStorageService? _storageService;
  final Duration _autoSaveDebounce;
  Timer? _saveDebounceTimer;

  final List<Sk18Profile> _profiles = <Sk18Profile>[];
  int _activeProfileIndex = 0;
  int _activePageIndex = 0;
  String _selectedPort;
  bool _interactiveTriggerOnTap;

  ProfileRepository({
    List<Sk18Profile>? initialProfiles,
    ConfigStorageService? storageService,
    Duration autoSaveDebounce = const Duration(milliseconds: 150),
    String initialSelectedPort = SerialPortDiscovery.simulatorPortUri,
    bool initialInteractiveTriggerOnTap = false,
  }) : _storageService = storageService,
       _autoSaveDebounce = autoSaveDebounce,
       _selectedPort = initialSelectedPort,
       _interactiveTriggerOnTap = initialInteractiveTriggerOnTap {
    if (initialProfiles != null && initialProfiles.isNotEmpty) {
      _profiles.addAll(initialProfiles);
    } else {
      _profiles.add(Sk18Profile.createDefault());
    }
  }

  ConfigStorageService? get storageService => _storageService;
  List<Sk18Profile> get profiles => List.unmodifiable(_profiles);
  int get activeProfileIndex => _activeProfileIndex;
  int get activePageIndex => _activePageIndex;
  String get selectedPort => _selectedPort;
  bool get interactiveTriggerOnTap => _interactiveTriggerOnTap;

  Sk18Profile get activeProfile => _profiles[_activeProfileIndex];
  Sk18Page get activePage => activeProfile
      .pages[_activePageIndex.clamp(0, activeProfile.pages.length - 1)];

  void setSelectedPort(String port) {
    final trimmed = port.trim();
    if (trimmed.isEmpty || _selectedPort == trimmed) return;
    _selectedPort = trimmed;
    _scheduleAutoSave();
  }

  void setInteractiveTriggerOnTap(bool enabled) {
    if (_interactiveTriggerOnTap == enabled) return;
    _interactiveTriggerOnTap = enabled;
    _scheduleAutoSave();
  }

  void selectProfile(int index) {
    if (index >= 0 && index < _profiles.length) {
      _activeProfileIndex = index;
      _activePageIndex = 0;
      _scheduleAutoSave();
    }
  }

  void selectPage(int index) {
    final pages = activeProfile.pages;
    if (index >= 0 && index < pages.length) {
      _activePageIndex = index;
      _scheduleAutoSave();
    }
  }

  Sk18Profile createProfile(String name) {
    final newProfile = Sk18Profile(
      id: 'profile_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty
          ? 'Profile ${_profiles.length + 1}'
          : name.trim(),
      landscapeMode: activeProfile.landscapeMode,
      upsideDown: activeProfile.upsideDown,
      backlight: activeProfile.backlight,
      volume: activeProfile.volume,
      offsetX: activeProfile.offsetX,
      offsetY: activeProfile.offsetY,
      pages: [
        Sk18Page.empty(
          id: 'page_1',
          name: 'Page 1',
          landscapeMode: activeProfile.landscapeMode,
        ),
      ],
    );
    _profiles.add(newProfile);
    _activeProfileIndex = _profiles.length - 1;
    _activePageIndex = 0;
    _scheduleAutoSave();
    return newProfile;
  }

  Sk18Page addPage(String name) {
    final currentPages = List<Sk18Page>.from(activeProfile.pages);
    final newPage = Sk18Page.empty(
      id: 'page_${currentPages.length + 1}_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty
          ? 'Page ${currentPages.length + 1}'
          : name.trim(),
      landscapeMode: activeProfile.landscapeMode,
    );
    currentPages.add(newPage);
    _profiles[_activeProfileIndex] = activeProfile.copyWith(pages: currentPages);
    _activePageIndex = currentPages.length - 1;
    _scheduleAutoSave();
    return newPage;
  }

  void updateActiveProfile(Sk18Profile updated) {
    _profiles[_activeProfileIndex] = updated;
    if (_activePageIndex >= updated.pages.length) {
      _activePageIndex = (updated.pages.length - 1).clamp(0, 100);
    }
    _scheduleAutoSave();
  }

  void updateKeyConfig(int keyIndex, KeyButtonConfig updatedKey) {
    final page = activePage;
    if (keyIndex < 0 || keyIndex >= page.keys.length) return;
    final updatedKeys = List<KeyButtonConfig>.from(page.keys);
    updatedKeys[keyIndex] = updatedKey;

    final updatedPages = List<Sk18Page>.from(activeProfile.pages);
    updatedPages[_activePageIndex] = page.copyWith(keys: updatedKeys);
    _profiles[_activeProfileIndex] = activeProfile.copyWith(pages: updatedPages);
    _scheduleAutoSave();
  }

  Map<String, dynamic> toStudioConfigJson() {
    return {
      'version': 1,
      'activeProfileIndex': _activeProfileIndex,
      'activePageIndex': _activePageIndex,
      'selectedPort': _selectedPort,
      'interactiveTriggerOnTap': _interactiveTriggerOnTap,
      'profiles': _profiles
          .asMap()
          .entries
          .map(
            (entry) => entry.value.toSk18ConfigJson(
              pageIndex: entry.key == _activeProfileIndex ? _activePageIndex : 0,
            ),
          )
          .toList(),
    };
  }

  bool restoreFromConfigMap(Map<String, dynamic> decoded) {
    final rawProfiles = decoded['profiles'];
    if (rawProfiles is List) {
      final parsedProfiles = <Sk18Profile>[];
      for (final item in rawProfiles) {
        if (item is Map<String, dynamic>) {
          parsedProfiles.add(Sk18Profile.fromJson(item));
        } else if (item is Map) {
          parsedProfiles.add(
            Sk18Profile.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
      if (parsedProfiles.isEmpty) {
        return false;
      }
      _profiles
        ..clear()
        ..addAll(parsedProfiles);
      _activeProfileIndex =
          ((decoded['activeProfileIndex'] as num?)?.toInt() ?? 0).clamp(
            0,
            _profiles.length - 1,
          );
      final currentPages = activeProfile.pages;
      _activePageIndex =
          ((decoded['activePageIndex'] as num?)?.toInt() ?? 0).clamp(
            0,
            currentPages.isEmpty ? 0 : currentPages.length - 1,
          );
      final port = (decoded['selectedPort'] as String?)?.trim();
      if (port != null && port.isNotEmpty) {
        _selectedPort = port;
      }
      if (decoded['interactiveTriggerOnTap'] is bool) {
        _interactiveTriggerOnTap = decoded['interactiveTriggerOnTap'] as bool;
      }
      return true;
    }

    if (decoded.containsKey('profileId') ||
        decoded.containsKey('id') ||
        decoded.containsKey('keys') ||
        decoded.containsKey('pages') ||
        decoded.containsKey('device')) {
      final singleProfile = Sk18Profile.fromJson(decoded);
      _profiles
        ..clear()
        ..add(singleProfile);
      _activeProfileIndex = 0;
      _activePageIndex =
          ((decoded['activePageIndex'] as num?)?.toInt() ?? 0).clamp(
            0,
            singleProfile.pages.length - 1,
          );
      final port = (decoded['selectedPort'] as String?)?.trim();
      if (port != null && port.isNotEmpty) {
        _selectedPort = port;
      }
      if (decoded['interactiveTriggerOnTap'] is bool) {
        _interactiveTriggerOnTap = decoded['interactiveTriggerOnTap'] as bool;
      }
      return true;
    }

    return false;
  }

  Future<bool> loadSavedConfig() async {
    final storage = _storageService;
    if (storage == null) return false;
    try {
      final decoded = await storage.readConfigJson();
      if (decoded == null) return false;
      return restoreFromConfigMap(decoded);
    } catch (_) {
      return false;
    }
  }

  Future<void> saveConfigNow() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    final storage = _storageService;
    if (storage == null) return;
    try {
      await storage.writeConfigJson(toStudioConfigJson());
    } catch (_) {
      // Ignore background persistence I/O errors
    }
  }

  void _scheduleAutoSave() {
    if (_storageService == null) return;
    _saveDebounceTimer?.cancel();
    if (_autoSaveDebounce <= Duration.zero) {
      unawaited(saveConfigNow());
      return;
    }
    _saveDebounceTimer = Timer(_autoSaveDebounce, () {
      _saveDebounceTimer = null;
      unawaited(saveConfigNow());
    });
  }

  String exportActiveProfileJson({bool pretty = true}) {
    final map = activeProfile.toSk18ConfigJson(pageIndex: _activePageIndex);
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return jsonEncode(map);
  }

  Sk18Profile importProfileFromJsonString(String jsonContent) {
    final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;
    if (decoded['profiles'] is List) {
      final restored = restoreFromConfigMap(decoded);
      if (restored) {
        _scheduleAutoSave();
        return activeProfile;
      }
    }
    final imported = Sk18Profile.fromJson(decoded);
    final existingIdx = _profiles.indexWhere((p) => p.id == imported.id);
    if (existingIdx >= 0) {
      _profiles[existingIdx] = imported;
      _activeProfileIndex = existingIdx;
    } else {
      _profiles.add(imported);
      _activeProfileIndex = _profiles.length - 1;
    }
    _activePageIndex =
        ((decoded['activePageIndex'] as num?)?.toInt() ?? 0).clamp(
          0,
          imported.pages.length - 1,
        );
    _scheduleAutoSave();
    return imported;
  }

  Future<void> saveActiveProfileToFile(String filePath) async {
    final file = File(filePath);
    await file.writeAsString(exportActiveProfileJson(pretty: true));
  }

  Future<Sk18Profile> loadProfileFromFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    return importProfileFromJsonString(content);
  }

  void dispose() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
  }
}
