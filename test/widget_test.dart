import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/data/repositories/device_repository.dart';
import 'package:wavectl_host/data/repositories/home_assistant_repository.dart';
import 'package:wavectl_host/data/repositories/profile_repository.dart';
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
}
