import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/notification_service.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

Future<AppController> controller([
  FakeNotificationGateway? notifications,
]) async {
  final repository = SettingsRepository(await SharedPreferences.getInstance());
  final notificationGateway = notifications ?? FakeNotificationGateway();
  final reconciler = ReminderReconciler(
    repository: repository,
    notifications: notificationGateway,
  );
  return AppController(
    repository: repository,
    syncService: ScheduleSyncService(
      fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
      repository: repository,
      reconciler: reconciler,
    ),
    reconciler: reconciler,
    notifications: notificationGateway,
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

  testWidgets('shows cached scheduled lessons from More', (tester) async {
    SharedPreferences.setMockInitialValues({
      'kiu.lessonSnapshot':
          '[{"title":"Aqidah","websiteStart":"2027-09-09 19:00"}]',
    });
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scheduled-lessons-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheduled-lessons-list')), findsOneWidget);
    expect(find.text('Aqidah'), findsOneWidget);
    expect(find.text('19:00 | 09-09-2027'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheduled-lessons-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheduled-lessons-list')), findsNothing);
    expect(find.byKey(const Key('scheduled-lessons-menu')), findsOneWidget);
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

    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(find.text('0.5×'), findsNothing);
    expect(find.text('3×'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).min, 0.5);
    expect(tester.widget<Slider>(find.byType(Slider)).divisions, 70);
  });

  testWidgets('shows main sound and inherited reminder sounds on sound page', (
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

    await tester.tap(find.byKey(const Key('notification-sound-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('main-notification-sound')), findsOneWidget);
    expect(find.byKey(const Key('notification-sound-60')), findsOneWidget);
    expect(find.byKey(const Key('notification-sound-0')), findsOneWidget);
    expect(find.text('Асосий овоз ишлатилади'), findsNWidgets(2));
  });

  testWidgets('shows selected sound name', (tester) async {
    final notifications = FakeNotificationGateway()
      ..selectedSound = const NotificationSound(
        uri: 'content://media/internal/audio/media/42',
        name: 'Morning bell',
      );
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(notifications),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Эслатма созламалари'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-sound-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Овозни танлаш'));
    await tester.pumpAndSettle();

    expect(find.text('Morning bell'), findsOneWidget);
  });
}
