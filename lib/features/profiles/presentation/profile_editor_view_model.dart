// ignore_for_file: prefer_initializing_formals

import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/key_button_config.dart';
import '../../profiles/domain/sk18_profile.dart';
import '../../../core/models/sk18_geometry.dart';
import '../../studio/presentation/studio_session.dart';

class ProfileEditorViewModel extends StudioSubViewModel {
  final ProfileRepository _profileRepository;

  ProfileEditorViewModel({
    required StudioSession session,
    required ProfileRepository profileRepository,
  }) : _profileRepository = profileRepository,
       super(session);

  List<Sk18Profile> get profiles => _profileRepository.profiles;
  int get activeProfileIndex => _profileRepository.activeProfileIndex;
  int get activePageIndex => _profileRepository.activePageIndex;
  Sk18Profile get activeProfile => _profileRepository.activeProfile;
  Sk18Page get activePage => _profileRepository.activePage;

  Sk18Profile selectOrCreateProfileForModel(WaveshareModel model) =>
      _profileRepository.selectOrCreateProfileForModel(model);

  void setInteractiveTriggerOnTap(bool value) {
    _profileRepository.setInteractiveTriggerOnTap(value);
  }

  void selectProfile(int index, {bool notifyChange = true}) {
    _profileRepository.selectProfile(index);
    session.setStatus('Switched to profile "${activeProfile.name}"');
    if (notifyChange) notify();
  }

  Sk18Profile createNewProfile(
    String name, {
    WaveshareModel? model,
    bool notifyChange = true,
  }) {
    final created = _profileRepository.createProfile(name, model: model);
    session.setStatus('Created profile "${created.name}"');
    if (notifyChange) notify();
    return created;
  }

  void selectPage(int index, {bool notifyChange = true}) {
    _profileRepository.selectPage(index);
    session.setStatus('Switched to page "${activePage.name}"');
    if (notifyChange) notify();
  }

  Sk18Page addNewPage(String name, {bool notifyChange = true}) {
    final created = _profileRepository.addPage(name);
    session.setStatus('Added page "${created.name}"');
    if (notifyChange) notify();
    return created;
  }

  String exportProfileJson() =>
      _profileRepository.exportActiveProfileJson(pretty: true);

  bool importProfileJson(String jsonContent, {bool notifyChange = true}) {
    try {
      final imported = _profileRepository.importProfileFromJsonString(
        jsonContent,
      );
      session.setStatus('Imported profile "${imported.name}"');
      if (notifyChange) notify();
      return true;
    } catch (e) {
      session.setStatus('Invalid JSON config: $e', isError: true);
      if (notifyChange) notify(markCanvasDirty: false);
      return false;
    }
  }

  void updateKeyConfig(
    int index,
    KeyButtonConfig config, {
    bool notifyChange = true,
  }) {
    _profileRepository.updateKeyConfig(index, config);
    if (notifyChange) notify();
  }
}
