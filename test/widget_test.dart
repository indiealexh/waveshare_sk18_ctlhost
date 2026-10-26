import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavectl_host/data/repositories/device_repository.dart';
import 'package:wavectl_host/data/repositories/home_assistant_repository.dart';
import 'package:wavectl_host/data/repositories/profile_repository.dart';
import 'package:wavectl_host/data/services/config_storage_service.dart';
import 'package:wavectl_host/data/services/host_launcher_service.dart';
import 'package:wavectl_host/domain/models/button_action.dart';
import 'package:wavectl_host/domain/use_cases/action_executor_use_case.dart';
import 'package:wavectl_host/main.dart';
import 'package:wavectl_host/ui/features/studio/view_models/studio_view_model.dart';

void main() {
  testWidgets(
    'Three-Pane Studio UI renders 18 keys, customizes button appearance/action, switches pages, and executes actions cleanly',
    (WidgetTester tester) async {
      // Configure desktop viewport as required by Ahem font layout guardrails
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final profileRepo = ProfileRepository();
      final deviceRepo = DeviceRepository(useBackgroundJpegIsolate: false);
      final haRepo = HomeAssistantRepository();
      final launcherService = HostLauncherService(dryRun: true);
      final executor = ActionExecutorUseCase(
        deviceRepository: deviceRepo,
        homeAssistantRepository: haRepo,
        hostLauncherService: launcherService,
      );
      final viewModel = StudioViewModel(
        profileRepository: profileRepo,
        deviceRepository: deviceRepo,
        homeAssistantRepository: haRepo,
        actionExecutor: executor,
      );

      await viewModel.initialize(
        autoConnectSimulator: true,
        envFilePath: '/non/existent/.env',
      );

      await tester.pumpWidget(
        WavectlHostApp(
          viewModel: viewModel,
          autoConnectSimulator: false,
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial Three-Pane Studio elements and all 18 key hit targets exist
      expect(find.byKey(const Key('sk18_lcd_custom_paint')), findsOneWidget);
      for (int i = 0; i < 18; i++) {
        expect(find.byKey(Key('lcd_key_$i')), findsOneWidget);
      }

      // 1. Trigger Key 0 (Office Light toggle: ON -> OFF)
      await tester.tap(find.byKey(const Key('trigger_selected_key_btn')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(haRepo.entities['light.office_main']?.state, equals('off'));

      // 2. Select Key 6 (K7: Terminal) on the interactive LCD canvas
      await tester.tap(find.byKey(const Key('lcd_key_6')));
      await tester.pumpAndSettle();
      expect(viewModel.selectedKeyIndex, equals(6));
      expect(find.text('Key K7 Inspector'), findsOneWidget);

      // 3. Customize Key 6 label, icon, and Host Launcher script target in Right Inspector
      await tester.enterText(
        find.byKey(const Key('key_label_field')),
        'Deploy App',
      );
      await tester.pump();
      expect(viewModel.selectedKeyConfig.label, equals('Deploy App'));

      await tester.ensureVisible(find.byKey(const Key('icon_chip_globe')));
      await tester.tap(find.byKey(const Key('icon_chip_globe')));
      await tester.pump();
      expect(viewModel.selectedKeyConfig.iconName, equals('globe'));

      await tester.ensureVisible(find.byKey(const Key('launcher_type_script')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('launcher_type_script')));
      await tester.pump();
      expect(
        viewModel.selectedKeyConfig.action.launcherType,
        equals(HostLauncherType.script),
      );

      await tester.ensureVisible(find.byKey(const Key('launcher_target_field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('launcher_target_field')),
        'echo sk18_ready',
      );
      await tester.pump();

      // Trigger customized Key 6 and verify HostLauncherService executed it
      await tester.tap(find.byKey(const Key('trigger_selected_key_btn')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(launcherService.history.last.target, equals('echo sk18_ready'));

      // 4. Test physical portrait key press remapping (portrait col=2, row=0 -> logical K1 index=0)
      deviceRepo.simulatorTransport.emitPhysicalKeyStateChanged(
        col: 2,
        row: 0,
        pressed: true,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(haRepo.entities['light.office_main']?.state, equals('on'));
      deviceRepo.simulatorTransport.emitPhysicalKeyStateChanged(
        col: 2,
        row: 0,
        pressed: false,
      );
      await tester.pump();

      // 4b. Toggle Upside Down orientation and verify physical key press at (col=0, row=5) triggers K1 (index=0)
      await tester.ensureVisible(find.byKey(const Key('upside_down_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('upside_down_switch')));
      await tester.pump();
      expect(viewModel.activeProfile.upsideDown, isTrue);

      deviceRepo.simulatorTransport.emitPhysicalKeyStateChanged(
        col: 0,
        row: 5,
        pressed: true,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(haRepo.entities['light.office_main']?.state, equals('off'));
      deviceRepo.simulatorTransport.emitPhysicalKeyStateChanged(
        col: 0,
        row: 5,
        pressed: false,
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('upside_down_switch')));
      await tester.pump();
      expect(viewModel.activeProfile.upsideDown, isFalse);

      // 5. Add a new page in Left Sidebar and switch back
      await tester.tap(find.byKey(const Key('add_page_btn')));
      await tester.pumpAndSettle();
      expect(viewModel.activeProfile.pages.length, equals(3));
      expect(viewModel.activePageIndex, equals(2));

      await tester.tap(find.byKey(const Key('page_chip_0')));
      await tester.pumpAndSettle();
      expect(viewModel.activePageIndex, equals(0));

      // 6. Adjust calibration offset and verify update
      await tester.ensureVisible(find.byKey(const Key('offset_x_inc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offset_x_inc')));
      await tester.pump();
      expect(viewModel.activeProfile.offsetX, equals(1));

      // 7. Verify Sync Config works on stock V2.32 firmware fallback and error status shows red X
      deviceRepo.simulatorTransport.simulateStockV232Only = true;
      await viewModel.syncLayoutToDevice();
      await tester.pump();
      expect(viewModel.isStatusError, isFalse);
      expect(viewModel.statusMessage, contains('Synced layout & settings'));
      final okIcon = tester.widget<Icon>(find.byKey(const Key('status_bar_icon')));
      expect(okIcon.icon, equals(Icons.check_circle_rounded));

      // Trigger an error state (e.g. invalid JSON import) and verify red X icon is shown
      viewModel.importProfileJson('{invalid_json');
      await tester.pump();
      expect(viewModel.isStatusError, isTrue);
      final errIcon = tester.widget<Icon>(find.byKey(const Key('status_bar_icon')));
      expect(errIcon.icon, equals(Icons.cancel_rounded));

      // 8. Dispose widget tree and verify zero pending timers
      await tester.pumpWidget(const SizedBox.shrink());
      viewModel.dispose();
      haRepo.dispose();
      deviceRepo.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'Persists studio config on edit and restores keys, pages, and settings upon relaunch',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1.0;

      late Directory tempDir;
      late ConfigStorageService storageService;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('wavectl_widget_cfg_');
        storageService = ConfigStorageService(
          configFilePath: p.join(tempDir.path, 'studio_config.json'),
        );
      });

      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      // --- Launch 1: Customize key, add page, and adjust calibration ---
      final profileRepo1 = ProfileRepository(storageService: storageService);
      final deviceRepo1 = DeviceRepository(useBackgroundJpegIsolate: false);
      final haRepo1 = HomeAssistantRepository();
      final executor1 = ActionExecutorUseCase(
        deviceRepository: deviceRepo1,
        homeAssistantRepository: haRepo1,
        hostLauncherService: HostLauncherService(dryRun: true),
      );
      final viewModel1 = StudioViewModel(
        profileRepository: profileRepo1,
        deviceRepository: deviceRepo1,
        homeAssistantRepository: haRepo1,
        actionExecutor: executor1,
      );

      await tester.runAsync(() async {
        await viewModel1.initialize(
          autoConnectSimulator: true,
          envFilePath: '/non/existent/.env',
        );
      });

      await tester.pumpWidget(
        WavectlHostApp(
          viewModel: viewModel1,
          autoConnectSimulator: false,
        ),
      );
      await tester.pumpAndSettle();

      // Edit Key 0 label and icon
      await tester.enterText(
        find.byKey(const Key('key_label_field')),
        'Saved Macro Key',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('icon_chip_bolt')));
      await tester.tap(find.byKey(const Key('icon_chip_bolt')));
      await tester.pump();

      // Increment X offset
      await tester.ensureVisible(find.byKey(const Key('offset_x_inc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offset_x_inc')));
      await tester.pump();

      // Add a new page and switch back to Page 0
      await tester.tap(find.byKey(const Key('add_page_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page_chip_0')));
      await tester.pumpAndSettle();

      // Flush debounced auto-save inside real async context and tear down Launch 1
      await tester.runAsync(() async {
        await profileRepo1.saveConfigNow();
      });

      await tester.pumpWidget(const SizedBox.shrink());
      viewModel1.dispose();
      haRepo1.dispose();
      deviceRepo1.dispose();
      await tester.pump();

      // --- Launch 2: Relaunch with fresh repositories sharing the same storage ---
      final profileRepo2 = ProfileRepository(storageService: storageService);
      final deviceRepo2 = DeviceRepository(useBackgroundJpegIsolate: false);
      final haRepo2 = HomeAssistantRepository();
      final executor2 = ActionExecutorUseCase(
        deviceRepository: deviceRepo2,
        homeAssistantRepository: haRepo2,
        hostLauncherService: HostLauncherService(dryRun: true),
      );
      final viewModel2 = StudioViewModel(
        profileRepository: profileRepo2,
        deviceRepository: deviceRepo2,
        homeAssistantRepository: haRepo2,
        actionExecutor: executor2,
      );

      await tester.runAsync(() async {
        await viewModel2.initialize(
          autoConnectSimulator: true,
          envFilePath: '/non/existent/.env',
        );
      });

      await tester.pumpWidget(
        WavectlHostApp(
          viewModel: viewModel2,
          autoConnectSimulator: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(viewModel2.activePage.keys[0].label, equals('Saved Macro Key'));
      expect(viewModel2.activePage.keys[0].iconName, equals('bolt'));
      expect(viewModel2.activeProfile.offsetX, equals(1));
      expect(viewModel2.activeProfile.pages.length, equals(3));
      expect(find.byKey(const Key('page_chip_2')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      viewModel2.dispose();
      haRepo2.dispose();
      deviceRepo2.dispose();
      await tester.pump();
    },
  );
}
