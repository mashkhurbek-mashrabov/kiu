import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/core/platform.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/app_version_service.dart';
import 'package:kiu/services/notification_service.dart';
import 'package:kiu/services/permission_onboarding.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:kiu/services/video_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'permission_onboarding_test.dart'
    show ImmediateResumeWaiter, RecordingExplainer, createController;
import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

class _Version implements AppVersionProvider {
  @override
  Future<AppVersion> read() async => const AppVersion(name: '2.4.0', code: 42);
}

class _FakeStreamHttpClient extends Fake implements HttpClient {
  _FakeStreamHttpClient(this.bytes);
  final List<int> bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(bytes);

  @override
  void close({bool force = false}) {}
}

class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest(this.bytes);
  final List<int> bytes;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(bytes);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

class _FakeResponse extends Fake implements HttpClientResponse {
  _FakeResponse(this.bytes);
  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
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
    SharedPreferences.setMockInitialValues({
      'kiu.locale': 'en',
      'kiu.permissionOnboardingShown': true,
    });
    injectedScripts.clear();
    loadedUrls.clear();
    navigateTo = null;
  });

  test('macOS platform flags identify macOS as Apple platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(runsOnMacOS, isTrue);
    expect(runsOnIOS, isFalse);
    expect(runsOnApple, isTrue);
  });

  test(
    'canScheduleExactly is true on macOS without Android exact alarm',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final gateway = LocalNotificationGateway();
      expect(await gateway.canScheduleExactly(), isTrue);
    },
  );

  test('WorkManagerScheduler.scheduleNext does nothing on macOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await expectLater(WorkManagerScheduler.scheduleNext(), completes);
  });

  test('macOS onboarding asks for notifications and nothing else', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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
    expect(access.batteryDialogShown, 0);
    expect(access.overlaySettingsOpened, 0);
    expect(access.fullScreenSettingsOpened, 0);
    expect(waiter.waits, 0);
    expect(controller.settings.callsEnabled, isFalse);
  });

  testWidgets(
    'macOS hides lesson calls, Android permissions and the sound picker',
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
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('macOS offers no in-app APK update check', (tester) async {
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

    expect(find.byKey(const Key('app-version')), findsOneWidget);
    expect(find.byKey(const Key('check-updates')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test(
    'DesktopVideoDownloadGateway enqueues, queries, and removes downloads',
    () async {
      final tempDir = Directory.systemTemp.createTempSync('desktop_video_test');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final gateway = DesktopVideoDownloadGateway(
        baseDirectory: tempDir,
        clientFactory: () => _FakeStreamHttpClient([1, 2, 3, 4, 5]),
      );

      final videoUrl = Uri.parse('https://example.com/videos/1-2.mp4');
      final id = await gateway.enqueue(
        url: videoUrl,
        fileName: '1-2.mp4',
        title: 'Lesson 2',
      );

      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final status = await gateway.query([id]);
        if (status.isNotEmpty && status.first.status == 'done') break;
      }

      final statuses = await gateway.query([id]);
      expect(statuses, hasLength(1));
      expect(statuses.first.status, 'done');
      expect(statuses.first.downloaded, 5);
      expect(statuses.first.total, 5);
      expect(statuses.first.path, isNotNull);
      expect(File(statuses.first.path!).existsSync(), isTrue);

      await gateway.remove([id]);
      expect(File(statuses.first.path!).existsSync(), isFalse);
      final afterRemove = await gateway.query([id]);
      expect(afterRemove, isEmpty);
    },
  );

  testWidgets(
    'macOS keeps the floating nav bar compact and centered on wide screens',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        KiuApp(controller: await _controller(), homeRequests: ValueNotifier(0)),
      );
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byKey(const Key('nav-bar')));
      expect(bar.width, lessThanOrEqualTo(420));
      expect(bar.left, closeTo((1200 - bar.width) / 2, 2));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('macOS uses a visible 4px brand-colored progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(controller: await _controller(), homeRequests: ValueNotifier(0)),
    );

    final indicatorFinder = find.byKey(const Key('page-progress'));
    expect(indicatorFinder, findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(indicatorFinder);
    expect(indicator.minHeight, 4.0);
    expect(indicator.value, isNotNull);
    expect(indicator.value, greaterThan(0.0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
