import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Future<AppVersion> read() async => const AppVersion(name: '2.1.0', code: 34);
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

/// Opens settings and walks in to the activation page.
Future<void> _openActivationPage(WidgetTester tester) async {
  await _openSettings(tester);
  await _tapVersion(tester, 10);
}

Future<void> _submitKey(WidgetTester tester, String key) async {
  await tester.enterText(find.byKey(const Key('activation-input')), key);
  await tester.tap(find.byKey(const Key('activation-submit')));
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

  testWidgets('a user ID is minted on first launch and shown on the page', (
    tester,
  ) async {
    final controller = await _controller();
    final id = controller.userId;
    expect(id, isNotNull);
    expect(id!.length, userIdLength);

    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openActivationPage(tester);

    expect(find.byKey(const Key('activation-user-id')), findsOneWidget);
    // Shown in its grouped form, which is what the user reads out.
    expect(find.text(formatUserId(id)), findsOneWidget);
    expect(find.byKey(const Key('activation-contact')), findsOneWidget);
  });

  testWidgets('the user ID survives a restart', (tester) async {
    final first = await _controller();
    final id = first.userId;
    // A second controller over the same preferences must not re-mint: a new ID
    // would silently kill the key the user already has.
    final second = await _controller();
    expect(second.userId, id);
  });

  testWidgets('tapping the user ID row copies the raw ID', (tester) async {
    final controller = await _controller();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openActivationPage(tester);
    await tester.tap(find.byKey(const Key('activation-user-id')));
    await tester.pumpAndSettle();

    // The unformatted ID: the dashes are for reading, and the developer pastes
    // whatever arrives straight into the generator.
    expect(copied, controller.userId);
    expect(copied, isNot(contains('-')));
  });

  testWidgets('a key issued for another install is rejected', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openActivationPage(tester);

    // The sharing case: a perfectly well-formed key, just not for this device.
    final foreign = activationKeyFor(
      controller.userId == 'A2B3C4' ? 'D5E6F7' : 'A2B3C4',
    );
    await _submitKey(tester, foreign);

    expect(controller.settings.additionalFunctionsActivated, isFalse);
    expect(find.byKey(const Key('activation-input')), findsOneWidget);
  });

  testWidgets('a key for this install unlocks the row and persists', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await _openActivationPage(tester);
    await _submitKey(tester, activationKeyFor(controller.userId!));

    expect(controller.settings.additionalFunctionsActivated, isTrue);

    // Back out of the activation page; the sheet reopens behind it.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mark-watched-menu')), findsOneWidget);

    final reloaded = SettingsRepository(await SharedPreferences.getInstance())
        .loadSettings();
    expect(reloaded.additionalFunctionsActivated, isTrue);
  });

  group('pre-2.1.0 activation reset', () {
    testWidgets('clears an activation granted by an unbound key', (
      tester,
    ) async {
      // An install upgrading from 2.0.0: activated, but with no reset marker
      // and no user ID.
      SharedPreferences.setMockInitialValues({
        'kiu.additionalFunctionsActivated': true,
      });
      final controller = await _controller();

      expect(controller.settings.additionalFunctionsActivated, isFalse);
      expect(controller.userId, isNotNull);
    });

    testWidgets('does not clear an activation earned after the reset', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'kiu.additionalFunctionsActivated': true,
      });
      final first = await _controller();
      expect(first.settings.additionalFunctionsActivated, isFalse);

      // Activate properly, then relaunch: the marker is set, so the reset must
      // not fire a second time and undo it.
      final unlocked = await first.activateAdditionalFunctions(
        activationKeyFor(first.userId!),
      );
      expect(unlocked, isTrue);

      final second = await _controller();
      expect(second.settings.additionalFunctionsActivated, isTrue);
      expect(second.userId, first.userId);
    });
  });
}
