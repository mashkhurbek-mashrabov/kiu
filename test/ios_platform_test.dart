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

Future<AppController> _controller({bool alarmKit = false}) async {
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
    // Stands in for the AlarmKit question; false is iOS before 26.
    iosPlatform: (method) async => alarmKit && method == 'lessonCallsAvailable',
  );
  await controller.initialize();
  return controller;
}

Future<void> _openNotificationSettings(
  WidgetTester tester, {
  bool alarmKit = false,
}) async {
  await tester.pumpWidget(
    KiuApp(
      controller: await _controller(alarmKit: alarmKit),
      homeRequests: ValueNotifier(0),
    ),
  );
  await tester.tap(find.byKey(const Key('actions-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('notification-settings-menu')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
    // Onboarding already done, so the first-open permission flow on iOS does
    // not put its explainer over the sheets these tests open.
    SharedPreferences.setMockInitialValues({
      'kiu.locale': 'en',
      'kiu.permissionOnboardingShown': true,
    });
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

  group('iOS onboarding and AlarmKit', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<({AppController controller, List<String> asked})> onboard({
      required bool alarmKit,
      required bool granted,
      bool notifications = true,
    }) async {
      final asked = <String>[];
      final controller = await createController(
        notifications: FakeNotificationGateway()..permission = notifications,
        backgroundAccess: FakeBackgroundAccessGateway(),
        resumeWaiter: ImmediateResumeWaiter(),
        iosPlatform: (method) async {
          asked.add(method);
          return switch (method) {
            'alarmKitAvailable' => alarmKit,
            'requestAlarmKitAuthorization' => granted,
            'requestLessonCallAuthorization' => granted,
            _ => false,
          };
        },
      );
      await controller.runPermissionOnboarding(
        explain: RecordingExplainer().call,
      );
      return (controller: controller, asked: asked);
    }

    test('iOS 26 with AlarmKit allowed switches calls on', () async {
      final run = await onboard(alarmKit: true, granted: true);
      expect(run.asked, contains('requestAlarmKitAuthorization'));
      expect(run.controller.settings.callsEnabled, isTrue);
    });

    test('a declined AlarmKit prompt leaves calls off', () async {
      final run = await onboard(alarmKit: true, granted: false);
      expect(run.controller.settings.callsEnabled, isFalse);
    });

    test('before iOS 26 AlarmKit is never asked for', () async {
      final run = await onboard(alarmKit: false, granted: true);
      expect(run.asked, isNot(contains('requestAlarmKitAuthorization')));
      expect(run.controller.settings.callsEnabled, isFalse);
    });

    test('no alarm prompt after notifications were refused', () async {
      final run = await onboard(
        alarmKit: true,
        granted: true,
        notifications: false,
      );
      expect(run.asked, isNot(contains('requestAlarmKitAuthorization')));
      expect(run.controller.settings.callsEnabled, isFalse);
    });
  });

  testWidgets('a fresh iOS install asks for permissions on first open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'kiu.locale': 'en'});
    await tester.pumpWidget(
      KiuApp(controller: await _controller(), homeRequests: ValueNotifier(0)),
    );
    await tester.pumpAndSettle();

    // The login page never reaches Home, yet the explainer is already up.
    expect(
      find.text('So KIU can tell you before a lesson starts.'),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android still waits for the first Home page', (tester) async {
    SharedPreferences.setMockInitialValues({'kiu.locale': 'en'});
    await tester.pumpWidget(
      KiuApp(controller: await _controller(), homeRequests: ValueNotifier(0)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('So KIU can tell you before a lesson starts.'),
      findsNothing,
    );
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

  testWidgets('iOS with AlarmKit offers calls, without Android-only knobs', (
    tester,
  ) async {
    await _openNotificationSettings(tester, alarmKit: true);
    await tester.scrollUntilVisible(
      find.byKey(const Key('lesson-calls-switch')),
      200,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.byKey(const Key('lesson-calls-switch')), findsOneWidget);
    // Ring duration sets how long the fallback and in-app screen ring; a
    // system ringtone cannot be picked on iOS.
    expect(find.byKey(const Key('call-ring-duration')), findsOneWidget);
    expect(find.byKey(const Key('call-ringtone')), findsNothing);
    expect(find.byKey(const Key('battery-access')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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
