import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/app_version_service.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:kiu/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

class _V implements AppVersionProvider {
  @override
  Future<AppVersion> read() async =>
      const AppVersion(name: '1.5.0', code: 19, abi: 4);
}

class _C implements UpdateChecker {
  @override
  Future<UpdateCheckResult> check({
    required int installedBuild,
    required int abi,
  }) async => const UpdateCheckResult.answered(null);
}

void main() {
  testWidgets('the up-to-date bar shows while the sheet is still open', (
    tester,
  ) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    final notif = FakeNotificationGateway();
    final rec = ReminderReconciler(repository: repo, notifications: notif);
    final controller = AppController(
      repository: repo,
      syncService: ScheduleSyncService(
        fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
        repository: repo,
        reconciler: rec,
      ),
      reconciler: rec,
      notifications: notif,
      scheduler: FakeBackgroundScheduler(),
      appVersionProvider: _V(),
      backgroundAccess: FakeBackgroundAccessGateway(),
      updateChecker: _C(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('check-updates')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-updates')));
    await tester.pumpAndSettle();

    // The answer appears in the row itself, with the sheet still open. A
    // snack bar renders at the bottom of the screen, which on a short device
    // is behind this 88%-height sheet -- the user saw nothing until they
    // backed out.
    expect(find.byKey(const Key('check-updates')), findsOneWidget);
    expect(find.text('Сизда энг сўнгги версия'), findsOneWidget);
  });
}
