import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/core/activation.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/app_version_service.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

class _VersionProvider implements AppVersionProvider {
  @override
  Future<AppVersion> read() async => const AppVersion(name: '2.0.0', code: 33);
}

Future<AppController> _controller() async {
  WebViewPlatform.instance = FakeWebViewPlatform();
  final repository = SettingsRepository(await SharedPreferences.getInstance());
  final notifications = FakeNotificationGateway();
  final reconciler = ReminderReconciler(
    repository: repository,
    notifications: notifications,
  );
  final controller = AppController(
    repository: repository,
    syncService: ScheduleSyncService(
      fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
      repository: repository,
      reconciler: reconciler,
    ),
    reconciler: reconciler,
    notifications: notifications,
    scheduler: FakeBackgroundScheduler(),
    appVersionProvider: _VersionProvider(),
  );
  await controller.initialize();
  return controller;
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('actions-menu')));
  await tester.pumpAndSettle();
}

/// Taps the version row [times] times, scrolling it into view first.
Future<void> _tapVersion(WidgetTester tester, int times) async {
  final version = find.byKey(const Key('app-version'));
  await tester.scrollUntilVisible(version, 120);
  await tester.pumpAndSettle();
  for (var i = 0; i < times; i++) {
    await tester.tap(version, warnIfMissed: false);
    // Pumped well inside the 2s idle reset, so the taps count as a run.
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('mark as watched is hidden until activated, speed is not', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openSettings(tester);

    // The gated row is gone...
    expect(find.byKey(const Key('mark-watched-menu')), findsNothing);
    // ...while the speed controls in the same section stay available to
    // everyone. This is the assertion that pins the narrowed scope: video
    // speed was deliberately left open.
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('1.5×'), findsOneWidget);
  });

  testWidgets('ten taps on the version row open the activation page', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openSettings(tester);
    await _tapVersion(tester, 10);

    expect(find.byKey(const Key('activation-page')), findsOneWidget);
    expect(find.byKey(const Key('activation-input')), findsOneWidget);
    // The developer's handle is reachable from the page, so a user who lands
    // here knows who to ask for a key.
    expect(find.byKey(const Key('activation-contact')), findsOneWidget);
  });

  testWidgets('fewer than ten taps do not open the page', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openSettings(tester);
    await _tapVersion(tester, 9);

    expect(find.byKey(const Key('activation-page')), findsNothing);
  });

  testWidgets('an invalid key is rejected and leaves the feature locked', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openSettings(tester);
    await _tapVersion(tester, 10);

    await tester.enterText(
      find.byKey(const Key('activation-input')),
      'KIU-7F3K-WRNG',
    );
    await tester.tap(find.byKey(const Key('activation-submit')));
    await tester.pumpAndSettle();

    expect(controller.settings.additionalFunctionsActivated, isFalse);
    expect(find.byKey(const Key('activation-input')), findsOneWidget);
  });

  testWidgets('a valid key unlocks the row and survives a reload', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openSettings(tester);
    await _tapVersion(tester, 10);

    await tester.enterText(
      find.byKey(const Key('activation-input')),
      activationTestVector,
    );
    await tester.tap(find.byKey(const Key('activation-submit')));
    await tester.pumpAndSettle();

    expect(controller.settings.additionalFunctionsActivated, isTrue);

    // Back out of the activation page; the sheet reopens behind it. Tapped by
    // type rather than via pageBack(), which looks for a Cupertino back button
    // this Material AppBar does not have.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mark-watched-menu')), findsOneWidget);

    // The flag is persisted, not just held in memory: a fresh repository over
    // the same preferences still reports it.
    final reloaded = SettingsRepository(await SharedPreferences.getInstance())
        .loadSettings();
    expect(reloaded.additionalFunctionsActivated, isTrue);
  });
}
