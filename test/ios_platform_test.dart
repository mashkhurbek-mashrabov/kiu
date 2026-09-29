import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/app_version_service.dart';
import 'package:kiu/services/permission_onboarding.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'permission_onboarding_test.dart'
    show ImmediateResumeWaiter, RecordingExplainer, createController;
import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

class _Version implements AppVersionProvider {
  @override
  Future<AppVersion> read() async => const AppVersion(name: '2.3.0', code: 38);
}

Future<AppController> _controller() async {
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
    appVersionProvider: _Version(),
    backgroundAccess: FakeBackgroundAccessGateway(),
  );
  await controller.initialize();
  return controller;
}

Future<void> _openNotificationSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    KiuApp(controller: await _controller(), homeRequests: ValueNotifier(0)),
  );
  await tester.tap(find.byKey(const Key('actions-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('notification-settings-menu')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({'kiu.locale': 'en'});
    injectedScripts.clear();
    loadedUrls.clear();
    navigateTo = null;
  });

  test('iOS onboarding asks for notifications and nothing else', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final notifications = FakeNotificationGateway()..permission = true;
    final access = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false
      ..overlaysAllowed = false
      ..fullScreenIntentAllowed = false;
    final waiter = ImmediateResumeWaiter();
    final controller = await createController(
      notifications: notifications,
      backgroundAccess: access,
      resumeWaiter: waiter,
    );
    final explainer = RecordingExplainer();

    final result = await controller.runPermissionOnboarding(
      explain: explainer.call,
    );

    expect(explainer.shown, [PermissionKind.notifications]);
    expect(result.notifications, isTrue);
    // No Android screen exists to send the user to, so nothing may open.
    expect(access.batteryDialogShown, 0);
    expect(access.overlaySettingsOpened, 0);
    expect(access.fullScreenSettingsOpened, 0);
    expect(waiter.waits, 0);
    // Calls cannot ring on iOS, so onboarding must never switch them on.
    expect(controller.settings.callsEnabled, isFalse);
  });

  testWidgets(
    'iOS hides lesson calls, Android permissions and the sound picker',
    (tester) async {
      await _openNotificationSettings(tester);

      expect(find.byKey(const Key('lesson-calls-switch')), findsNothing);
      expect(find.byKey(const Key('battery-access')), findsNothing);
      expect(find.byKey(const Key('exact-timing')), findsNothing);
      expect(
        find.byKey(const Key('notification-sound-settings')),
        findsNothing,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Android still shows them', (tester) async {
    await _openNotificationSettings(tester);

    expect(
      find.byKey(const Key('notification-sound-settings')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('lesson-calls-switch')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('lesson-calls-switch')), findsOneWidget);
  });

  testWidgets('iOS offers no in-app update check', (tester) async {
    await tester.pumpWidget(
      KiuApp(controller: await _controller(), homeRequests: ValueNotifier(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('app-version')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // The version row sits right above where the update row would be.
    expect(find.byKey(const Key('app-version')), findsOneWidget);
    expect(find.byKey(const Key('check-updates')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
