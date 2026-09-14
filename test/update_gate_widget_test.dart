import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/core/constants.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/app_version_service.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:kiu/services/update_downloader.dart';
import 'package:kiu/services/update_service.dart';
import 'package:kiu/ui/update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

class _VersionProvider implements AppVersionProvider {
  @override
  Future<AppVersion> read() async =>
      const AppVersion(name: '1.4.0', code: 18, abi: 2);
}

class _FakeChecker implements UpdateChecker {
  _FakeChecker(this.result);

  UpdateCheckResult result;
  int calls = 0;
  int? lastInstalledBuild;
  int? lastAbi;

  @override
  Future<UpdateCheckResult> check({
    required int installedBuild,
    required int abi,
  }) async {
    calls++;
    lastInstalledBuild = installedBuild;
    lastAbi = abi;
    return result;
  }
}

class _FakeInstaller implements ApkInstaller {
  bool allowed = true;
  int permissionPrompts = 0;
  final List<String> installed = [];

  @override
  Future<String?> cacheDirectory() async => null;

  @override
  Future<bool> canInstallPackages() async => allowed;

  @override
  Future<void> openInstallPermissionSettings() async => permissionPrompts++;

  @override
  Future<void> installApk(String path) async => installed.add(path);
}

AppUpdate _update({bool mandatory = true, int build = 19}) => AppUpdate(
  versionName: '1.5.0',
  buildNumber: build,
  mandatory: mandatory,
  notes: 'Shiny new things.',
  apkUrl: 'https://github.com/mashkhurbek-mashrabov/kiu/releases/download/v1.5.0/KIU-1.5.0+19-arm64-v8a.apk',
  apkSize: 1000,
);

Future<AppController> _controller(
  UpdateChecker checker, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final repository = SettingsRepository(await SharedPreferences.getInstance());
  final notifications = FakeNotificationGateway();
  final reconciler = ReminderReconciler(
    repository: repository,
    notifications: notifications,
  );
  return AppController(
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
    backgroundAccess: FakeBackgroundAccessGateway(),
    updateChecker: checker,
  );
}

void main() {
  setUp(() => WebViewPlatform.instance = FakeWebViewPlatform());

  testWidgets('a mandatory update replaces the browser entirely', (
    tester,
  ) async {
    final checker = _FakeChecker(UpdateCheckResult.answered(_update()));
    final controller = await _controller(checker);
    await controller.initialize();
    await tester.pumpWidget(
      KiuApp(
        controller: controller,
        homeRequests: ValueNotifier<int>(0),
        updateDownloader: UpdateDownloader(installer: _FakeInstaller()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateGate), findsOneWidget);
    expect(find.text('Янгиланиш талаб қилинади'), findsOneWidget);
    // The browser must be gone, not merely covered.
    expect(find.byKey(const Key('actions-menu')), findsNothing);
  });

  testWidgets('release notes start collapsed and expand on tap', (
    tester,
  ) async {
    final checker = _FakeChecker(UpdateCheckResult.answered(_update()));
    final controller = await _controller(checker);
    await controller.initialize();
    await tester.pumpWidget(
      KiuApp(
        controller: controller,
        homeRequests: ValueNotifier<int>(0),
        updateDownloader: UpdateDownloader(installer: _FakeInstaller()),
      ),
    );
    await tester.pumpAndSettle();

    // The gate's job is to get the user updated, so the notes must not push
    // the action button down the screen before it is asked for.
    expect(find.byKey(const Key('update-notes')), findsOneWidget);
    expect(find.text('Shiny new things.'), findsNothing);
    expect(find.byKey(const Key('update-now')), findsOneWidget);

    await tester.tap(find.byKey(const Key('update-notes')));
    await tester.pumpAndSettle();
    expect(find.text('Shiny new things.'), findsOneWidget);
  });

  testWidgets('an optional update does not gate the app', (tester) async {
    final checker = _FakeChecker(
      UpdateCheckResult.answered(_update(mandatory: false)),
    );
    final controller = await _controller(checker);
    await controller.initialize();
    await tester.pumpWidget(
      KiuApp(
        controller: controller,
        homeRequests: ValueNotifier<int>(0),
        updateDownloader: UpdateDownloader(installer: _FakeInstaller()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateGate), findsNothing);
    expect(find.byKey(const Key('actions-menu')), findsOneWidget);
  });

  testWidgets('no update leaves the browser alone', (tester) async {
    final checker = _FakeChecker(const UpdateCheckResult.answered(null));
    final controller = await _controller(checker);
    await controller.initialize();
    await tester.pumpWidget(
      KiuApp(
        controller: controller,
        homeRequests: ValueNotifier<int>(0),
        updateDownloader: UpdateDownloader(installer: _FakeInstaller()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateGate), findsNothing);
    expect(find.byKey(const Key('actions-menu')), findsOneWidget);
  });

  testWidgets('the About section shows version and last check', (tester) async {
    final checker = _FakeChecker(const UpdateCheckResult.answered(null));
    final controller = await _controller(checker);
    await controller.initialize();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-version')), findsOneWidget);
    expect(find.text('1.4.0 (18)'), findsOneWidget);
    expect(find.byKey(const Key('check-updates')), findsOneWidget);
    // Contact sits in the main sheet next to Useful links, not two taps down
    // inside it: questions and problem reports are common enough to earn a row.
    expect(find.byKey(const Key('contact-developer')), findsOneWidget);
    expect(find.text(contactHandle), findsOneWidget);
  });

  testWidgets('the gate offers a retry after a failed download', (
    tester,
  ) async {
    final checker = _FakeChecker(UpdateCheckResult.answered(_update()));
    final controller = await _controller(checker);
    await controller.initialize();
    // No permission: the downloader routes to settings and stays idle rather
    // than stranding the user behind a dead gate.
    final installer = _FakeInstaller()..allowed = false;
    final downloader = UpdateDownloader(installer: installer);
    await tester.pumpWidget(
      KiuApp(
        controller: controller,
        homeRequests: ValueNotifier<int>(0),
        updateDownloader: downloader,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('update-now')));
    await tester.pumpAndSettle();

    expect(installer.permissionPrompts, 1);
    expect(installer.installed, isEmpty);
    // Still actionable.
    expect(find.byKey(const Key('update-now')), findsOneWidget);
  });

  group('pending update persistence', () {
    // Regression for the gate being escapable by restarting: availableUpdate
    // used to be memory-only, so killing the app cleared it and the throttle
    // then suppressed the check that would have found it again.
    test('a stored mandatory update gates on launch with no network', () async {
      final checker = _FakeChecker(const UpdateCheckResult.unavailable());
      final controller = await _controller(
        checker,
        prefs: {'kiu.pendingUpdate': jsonEncode(_update().toJson())},
      );
      await controller.initialize();

      expect(controller.availableUpdate.value, isNotNull);
      expect(controller.availableUpdate.value!.mandatory, isTrue);
    });

    test('a stored update already installed is dropped', () async {
      final checker = _FakeChecker(const UpdateCheckResult.unavailable());
      // _VersionProvider reports build 18; a stored build 18 is not newer.
      final controller = await _controller(
        checker,
        prefs: {'kiu.pendingUpdate': jsonEncode(_update(build: 18).toJson())},
      );
      await controller.initialize();

      expect(controller.availableUpdate.value, isNull);
    });

    test('a malformed stored update does not throw on launch', () async {
      final checker = _FakeChecker(const UpdateCheckResult.unavailable());
      final controller = await _controller(
        checker,
        prefs: {'kiu.pendingUpdate': 'not json at all'},
      );
      // The launch path must survive this: a throw here is unrecoverable.
      await controller.initialize();

      expect(controller.availableUpdate.value, isNull);
    });

    test('an off-allowlist stored URL is rejected', () async {
      final checker = _FakeChecker(const UpdateCheckResult.unavailable());
      final controller = await _controller(
        checker,
        prefs: {
          'kiu.pendingUpdate': jsonEncode({
            'versionName': '1.5.2',
            'buildNumber': 21,
            'mandatory': true,
            'notes': '',
            'apkUrl': 'https://evil.example.com/payload.apk',
            'apkSize': 100,
          }),
        },
      );
      await controller.initialize();

      expect(controller.availableUpdate.value, isNull);
    });

    test('an "up to date" answer clears the stored update', () async {
      final checker = _FakeChecker(UpdateCheckResult.answered(_update()));
      final controller = await _controller(checker);
      await controller.initialize();
      await controller.checkForUpdate(force: true);
      expect(controller.availableUpdate.value, isNotNull);

      checker.result = const UpdateCheckResult.answered(null);
      await controller.checkForUpdate(force: true);

      expect(controller.availableUpdate.value, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('kiu.pendingUpdate'), isNull);
    });
  });

  testWidgets('the contact link is listed once, in the main sheet', (
    tester,
  ) async {
    // It used to appear both here and inside Useful links, which put the same
    // destination two taps away from itself.
    final checker = _FakeChecker(const UpdateCheckResult.answered(null));
    final controller = await _controller(checker);
    await controller.initialize();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('contact-developer')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();

    expect(
      find.text(contactHandle),
      findsNothing,
      reason: 'Useful links must not repeat the contact row',
    );
  });

  testWidgets('the gate closes an open settings sheet', (tester) async {
    // The gate swaps the widget behind `home:`, which does not pop routes: an
    // open settings sheet is a pushed route and used to stay on top of the
    // block, leaving the user to swipe it away by hand.
    final checker = _FakeChecker(const UpdateCheckResult.answered(null));
    final controller = await _controller(checker);
    await controller.initialize();
    await tester.pumpWidget(
      KiuApp(
        controller: controller,
        homeRequests: ValueNotifier<int>(0),
        updateDownloader: UpdateDownloader(installer: _FakeInstaller()),
      ),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-updates')), findsOneWidget);

    // A mandatory update arrives while the sheet is open.
    checker.result = UpdateCheckResult.answered(_update());
    await controller.checkForUpdate(force: true);
    await tester.pumpAndSettle();

    expect(find.byType(UpdateGate), findsOneWidget);
    expect(
      find.byKey(const Key('check-updates')),
      findsNothing,
      reason: 'the sheet must be gone, not merely behind the gate',
    );
  });

  group('checkForUpdate', () {
    test('passes the stripped build and the ABI to the checker', () async {
      final checker = _FakeChecker(const UpdateCheckResult.answered(null));
      final controller = await _controller(checker);
      await controller.initialize();
      await controller.checkForUpdate(force: true);

      expect(checker.lastInstalledBuild, 18);
      expect(checker.lastAbi, 2);
    });

    test('the throttle window is 30 minutes', () async {
      final checker = _FakeChecker(const UpdateCheckResult.answered(null));
      // 29 minutes ago: still inside the window.
      final controller = await _controller(
        checker,
        prefs: {
          'kiu.lastUpdateCheck': DateTime.now()
              .subtract(const Duration(minutes: 29))
              .toIso8601String(),
        },
      );
      await controller.initialize();
      await controller.checkForUpdate();
      expect(checker.calls, 0, reason: '29 min is inside the window');

      // 31 minutes ago: a launch must ask GitHub again.
      final later = await _controller(
        checker,
        prefs: {
          'kiu.lastUpdateCheck': DateTime.now()
              .subtract(const Duration(minutes: 31))
              .toIso8601String(),
        },
      );
      await later.initialize();
      await later.checkForUpdate();
      expect(checker.calls, greaterThan(0), reason: '31 min is outside it');
    });

    test('throttles repeat checks but honors force', () async {
      final checker = _FakeChecker(const UpdateCheckResult.answered(null));
      final controller = await _controller(checker);
      await controller.initialize();
      final afterInit = checker.calls;

      await controller.checkForUpdate();
      expect(checker.calls, afterInit, reason: 'within the 6h window');

      await controller.checkForUpdate(force: true);
      expect(checker.calls, afterInit + 1);
    });

    test(
      'an unavailable check does not advance the last-checked time',
      () async {
        final checker = _FakeChecker(const UpdateCheckResult.unavailable());
        final controller = await _controller(checker);
        await controller.initialize();
        await controller.checkForUpdate(force: true);

        expect(controller.lastUpdateCheck, isNull);
        expect(controller.updateCheckState.value, isNull);
      },
    );

    test('a skipped optional build stops being offered', () async {
      final checker = _FakeChecker(
        UpdateCheckResult.answered(_update(mandatory: false)),
      );
      final controller = await _controller(checker);
      await controller.initialize();
      await controller.checkForUpdate(force: true);
      expect(controller.availableUpdate.value, isNotNull);

      await controller.skipUpdate(controller.availableUpdate.value!);
      expect(controller.availableUpdate.value, isNull);

      await controller.checkForUpdate(force: true);
      expect(
        controller.availableUpdate.value,
        isNull,
        reason: 'the dismissed build must not come back',
      );
    });

    test('a mandatory build ignores a previous skip', () async {
      final checker = _FakeChecker(
        UpdateCheckResult.answered(_update(mandatory: false)),
      );
      final controller = await _controller(checker);
      await controller.initialize();
      await controller.checkForUpdate(force: true);
      await controller.skipUpdate(controller.availableUpdate.value!);

      checker.result = UpdateCheckResult.answered(_update());
      await controller.checkForUpdate(force: true);
      expect(controller.availableUpdate.value?.mandatory, isTrue);
    });
  });
}
