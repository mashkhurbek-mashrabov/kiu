import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:kiu/ui/widgets/settings_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

Future<AppController> controller() async {
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
  );
}

void main() {
  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({'kiu.locale': 'en'});
    injectedScripts.clear();
    loadedUrls.clear();
    navigateTo = null;
  });

  testWidgets('long help text is behind a tooltip, not shown inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-settings-menu')));
    await tester.pumpAndSettle();

    const help = 'Rings a full-screen call when a lesson starts.';
    // The prose lives only in the Tooltip's message until it is asked for, so
    // the row itself stays a single short line.
    expect(find.text(help), findsNothing);

    expect(
      find.descendant(
        of: find.byKey(const Key('lesson-calls-switch')),
        matching: find.byType(InfoHint),
      ),
      findsOneWidget,
    );

    final hintIcon = find.descendant(
      of: find.byKey(const Key('lesson-calls-switch')),
      matching: find.byIcon(Icons.info_outline_rounded),
    );
    await tester.ensureVisible(hintIcon);
    await tester.pumpAndSettle();
    await tester.tap(hintIcon);
    await tester.pumpAndSettle();

    expect(find.text(help), findsOneWidget);
  });

  testWidgets('tapping the info icon does not toggle the row it belongs to', (
    tester,
  ) async {
    final appController = await controller();
    await tester.pumpWidget(
      KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-settings-menu')));
    await tester.pumpAndSettle();

    expect(appController.settings.callsEnabled, isFalse);
    final hintIcon = find.descendant(
      of: find.byKey(const Key('lesson-calls-switch')),
      matching: find.byIcon(Icons.info_outline_rounded),
    );
    await tester.ensureVisible(hintIcon);
    await tester.pumpAndSettle();
    await tester.tap(hintIcon);
    await tester.pumpAndSettle();

    // Reading the help must not arm lesson calls as a side effect.
    expect(appController.settings.callsEnabled, isFalse);
  });
}
