import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
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
  Future<AppVersion> read() async => const AppVersion(name: '1.2.0', code: 3);
}

void main() {
  testWidgets('More sheet shows the Android package version', (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
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

    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();

    // The version lives in the About section as a settings row: the label and
    // the value are separate, rather than one concatenated footer line.
    expect(find.byKey(const Key('app-version')), findsOneWidget);
    expect(find.text('Версия'), findsOneWidget);
    expect(find.text('1.2.0 (3)'), findsOneWidget);
  });
}
