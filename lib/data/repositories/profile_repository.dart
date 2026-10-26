import 'dart:convert';
import 'dart:io';

import '../../domain/models/key_button_config.dart';
import '../../domain/models/sk18_profile.dart';

class ProfileRepository {
  final List<Sk18Profile> _profiles = <Sk18Profile>[];
  int _activeProfileIndex = 0;
  int _activePageIndex = 0;

  ProfileRepository({List<Sk18Profile>? initialProfiles}) {
    if (initialProfiles != null && initialProfiles.isNotEmpty) {
      _profiles.addAll(initialProfiles);
    } else {
      _profiles.add(Sk18Profile.createDefault());
    }
  }

  List<Sk18Profile> get profiles => List.unmodifiable(_profiles);
  int get activeProfileIndex => _activeProfileIndex;
  int get activePageIndex => _activePageIndex;

  Sk18Profile get activeProfile => _profiles[_activeProfileIndex];
  Sk18Page get activePage =>
      activeProfile.pages[_activePageIndex.clamp(0, activeProfile.pages.length - 1)];

  void selectProfile(int index) {
    if (index >= 0 && index < _profiles.length) {
      _activeProfileIndex = index;
      _activePageIndex = 0;
    }
  }

  void selectPage(int index) {
    final pages = activeProfile.pages;
    if (index >= 0 && index < pages.length) {
      _activePageIndex = index;
    }
  }

  Sk18Profile createProfile(String name) {
    final newProfile = Sk18Profile(
      id: 'profile_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Profile ${_profiles.length + 1}' : name.trim(),
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
    return newProfile;
  }

  Sk18Page addPage(String name) {
    final currentPages = List<Sk18Page>.from(activeProfile.pages);
    final newPage = Sk18Page.empty(
      id: 'page_${currentPages.length + 1}_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Page ${currentPages.length + 1}' : name.trim(),
      landscapeMode: activeProfile.landscapeMode,
    );
    currentPages.add(newPage);
    _profiles[_activeProfileIndex] = activeProfile.copyWith(pages: currentPages);
    _activePageIndex = currentPages.length - 1;
    return newPage;
  }

  void updateActiveProfile(Sk18Profile updated) {
    _profiles[_activeProfileIndex] = updated;
    if (_activePageIndex >= updated.pages.length) {
      _activePageIndex = (updated.pages.length - 1).clamp(0, 100);
    }
  }

  void updateKeyConfig(int keyIndex, KeyButtonConfig updatedKey) {
    final page = activePage;
    if (keyIndex < 0 || keyIndex >= page.keys.length) return;
    final updatedKeys = List<KeyButtonConfig>.from(page.keys);
    updatedKeys[keyIndex] = updatedKey;

    final updatedPages = List<Sk18Page>.from(activeProfile.pages);
    updatedPages[_activePageIndex] = page.copyWith(keys: updatedKeys);
    _profiles[_activeProfileIndex] = activeProfile.copyWith(pages: updatedPages);
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
}
