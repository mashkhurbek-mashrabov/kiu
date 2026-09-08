import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

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
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('uses headerless compact five-action bottom bar', (tester) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(BottomAppBar), findsOneWidget);
    expect(tester.getSize(find.byType(BottomAppBar)).height, 60);
    for (final key in const [
      'nav-back',
      'nav-forward',
      'nav-home',
      'nav-refresh',
      'actions-menu',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(find.byKey(const Key('home-selected')), findsOneWidget);
    expect(find.byKey(const Key('page-progress')), findsOneWidget);
  });

  testWidgets('does not highlight Home on another trusted page', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
        navigationRequests: ValueNotifier<Uri?>(
          Uri.parse('https://uz.do-kazankiu.ru/uz/profile/lesson/42'),
        ),
      ),
    );
    expect(find.byKey(const Key('home-selected')), findsNothing);
  });

  testWidgets('lists custom reminder inline with remove action', (
    tester,
  ) async {
    final appController = await controller();
    await appController.setReminderOffsets([75, 45, 60, 15, 0]);
    await tester.pumpWidget(
      KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Эслатма созламалари'));
    await tester.pumpAndSettle();

    final custom = find.text('1 Соат 15 Дақиқа');
    expect(custom, findsOneWidget);
    expect(find.text('45 Дақиқа'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    expect(
      tester.getTopLeft(custom).dy,
      lessThan(tester.getTopLeft(find.text('Махсус вақт')).dy),
    );
    await tester.ensureVisible(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    expect(appController.settings.reminderOffsetsMinutes, isNot(contains(75)));
  });

  testWidgets('notification back returns to main settings', (tester) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Эслатма созламалари'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-settings-back')));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(7));
  });

  testWidgets('shows separate sound controls for enabled reminder times', (
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
    await tester.tap(find.text('Эслатма созламалари'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-sound-60')), findsOneWidget);
    expect(find.byKey(const Key('notification-sound-0')), findsOneWidget);
  });
}
