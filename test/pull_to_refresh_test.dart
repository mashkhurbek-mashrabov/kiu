import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:kiu/web/js_scripts.dart';
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

/// Posts one `pullRefresh` message the way the injected script would.
void pull(String phase, [double distance = 0]) => postToBridge!(
  jsonEncode({'type': 'pullRefresh', 'phase': phase, 'distance': distance}),
);

final indicator = find.byKey(const Key('pull-refresh-indicator'));

void main() {
  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
    injectedScripts.clear();
    loadedUrls.clear();
    navigateTo = null;
    finishPage = null;
    postToBridge = null;
    reloadCount = 0;
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('injects the pull handler once the LMS page loads', (
    tester,
  ) async {
    await mount(tester);
    finishPage!('https://uz.do-kazankiu.ru/uz/');
    await tester.pumpAndSettle();

    expect(
      injectedScripts.any((script) => script.contains('pullRefresh')),
      isTrue,
    );
  });

  testWidgets('shows the indicator while pulling and hides it on release', (
    tester,
  ) async {
    await mount(tester);
    pull('move', 40);
    await tester.pump();
    expect(indicator, findsOneWidget);

    pull('end');
    await tester.pumpAndSettle();
    expect(indicator, findsNothing);
  });

  testWidgets('reloads only when released past the threshold', (tester) async {
    await mount(tester);

    // Short pull: released before the threshold, so nothing reloads.
    pull('move', 40);
    await tester.pump();
    pull('end');
    await tester.pumpAndSettle();
    expect(reloadCount, 0);

    // Full pull: released past the threshold.
    pull('move', 120);
    await tester.pump();
    pull('end');
    await tester.pumpAndSettle();
    expect(reloadCount, 1);
  });

  testWidgets('a cancelled pull does not reload', (tester) async {
    await mount(tester);
    pull('move', 120);
    await tester.pump();
    pull('cancel');
    await tester.pumpAndSettle();

    expect(reloadCount, 0);
    expect(indicator, findsNothing);
  });

  testWidgets('an abandoned pull clears the indicator instead of sticking', (
    tester,
  ) async {
    await mount(tester);
    // A drag that reports movement and then goes silent: the finger left the
    // WebView, so no `end` ever arrives.
    pull('move', 120);
    await tester.pump();
    expect(indicator, findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(indicator, findsNothing);
    expect(reloadCount, 0);
  });

  testWidgets('the script reports a release even when it never armed', (
    tester,
  ) async {
    final script = pullToRefreshScript();
    // The `end` handler must post on both paths; returning silently when the
    // gesture never armed is what left the indicator on screen.
    expect(script.contains("wasArmed ? 'end' : 'cancel'"), isTrue);
  });

  testWidgets('the script binds its listeners only once per page', (
    tester,
  ) async {
    await mount(tester);
    final script = pullToRefreshScript();

    expect(script.contains('__kiuPullBound'), isTrue);
    expect(script.contains('KiuBridge.postMessage'), isTrue);
  });
}
