import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/device/data/device_repository.dart';
import 'features/home_assistant/data/home_assistant_repository.dart';
import 'features/profiles/data/config_storage_service.dart';
import 'features/profiles/data/profile_repository.dart';
import 'features/actions/data/host_launcher_service.dart';
import 'features/actions/domain/action_executor_use_case.dart';
import 'features/studio/presentation/studio_view_model.dart';
import 'features/studio/presentation/studio_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WavectlHostApp());
}

class WavectlHostApp extends StatefulWidget {
  final StudioViewModel? viewModel;
  final ConfigStorageService? configStorageService;
  final bool autoConnectSimulator;

  const WavectlHostApp({
    super.key,
    this.viewModel,
    this.configStorageService,
    this.autoConnectSimulator = true,
  });

  @override
  State<WavectlHostApp> createState() => _WavectlHostAppState();
}

class _WavectlHostAppState extends State<WavectlHostApp> {
  ProfileRepository? _ownedProfileRepo;
  DeviceRepository? _ownedDeviceRepo;
  HomeAssistantRepository? _ownedHaRepo;
  StudioViewModel? _ownedViewModel;

  StudioViewModel get _activeViewModel => widget.viewModel ?? _ownedViewModel!;

  @override
  void initState() {
    super.initState();
    if (widget.viewModel == null) {
      _ownedProfileRepo = ProfileRepository(
        storageService:
            widget.configStorageService ?? const ConfigStorageService(),
      );
      _ownedDeviceRepo = DeviceRepository();
      _ownedHaRepo = HomeAssistantRepository();
      final launcherService = HostLauncherService();
      final executor = ActionExecutorUseCase(
        deviceRepository: _ownedDeviceRepo!,
        homeAssistantRepository: _ownedHaRepo!,
        hostLauncherService: launcherService,
      );
      _ownedViewModel = StudioViewModel(
        profileRepository: _ownedProfileRepo!,
        deviceRepository: _ownedDeviceRepo!,
        homeAssistantRepository: _ownedHaRepo!,
        actionExecutor: executor,
      );
      _ownedViewModel!.initialize(
        autoConnectSimulator: widget.autoConnectSimulator,
      );
    }
  }

  @override
  void dispose() {
    _ownedViewModel?.dispose();
    _ownedProfileRepo?.dispose();
    _ownedHaRepo?.dispose();
    _ownedDeviceRepo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wavectl_host — Waveshare SK18 Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkStudioTheme(),
      home: StudioScreen(viewModel: _activeViewModel),
    );
  }
}
