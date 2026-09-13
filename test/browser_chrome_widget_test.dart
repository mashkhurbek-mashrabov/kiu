import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/core/theme.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/notification_service.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:kiu/ui/widgets/settings_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

Future<AppController> controller([
  FakeNotificationGateway? notifications,
  FakeBackgroundAccessGateway? backgroundAccess,
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
    backgroundAccess: backgroundAccess,
  );
}

/// Finds a [SettingsSection] caption, which renders upper-cased.
Finder findCaption(String label) => find.text(label.toUpperCase());

void main() {
  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
    injectedScripts.clear();
    loadedUrls.clear();
    navigateTo = null;
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

  testWidgets('paints the dark surface when dark mode is saved', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'kiu.themeMode': 'dark'});
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    final colors = Theme.of(tester.element(find.byType(BottomAppBar)))
        .colorScheme;
    expect(colors.brightness, Brightness.dark);
    expect(colors.surface, darkSurface);
  });

  testWidgets('paints the light surface when light mode is saved', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'kiu.themeMode': 'light'});
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    final colors = Theme.of(tester.element(find.byType(BottomAppBar)))
        .colorScheme;
    expect(colors.brightness, Brightness.light);
    expect(colors.surface, lightSurface);
  });

  testWidgets('switches appearance from More', (tester) async {
    final appController = await controller();
    await tester.pumpWidget(
      KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
    );

    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    // Appearance is a three-segment control in the sheet now, so the mode is
    // one tap away rather than a row that opens its own dialog.
    final darkSegment = find.descendant(
      of: find.byKey(const Key('theme-mode-menu')),
      matching: find.byIcon(Icons.dark_mode_rounded),
    );
    await tester.ensureVisible(darkSegment);
    await tester.pumpAndSettle();
    await tester.tap(darkSegment);
    await tester.pumpAndSettle();

    expect(appController.settings.themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(BottomAppBar))).colorScheme.surface,
      darkSurface,
    );
    expect(injectedScripts.last, contains("setItem('darkMode'"));
    expect(injectedScripts.last, contains('const dark = true'));
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

  testWidgets('highlights Home on the Russian lessons page', (tester) async {
    SharedPreferences.setMockInitialValues({'kiu.locale': 'ru'});
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
        navigationRequests: ValueNotifier<Uri?>(
          Uri.parse('https://uz.do-kazankiu.ru/ru/profile/my-online-lessons'),
        ),
      ),
    );
    expect(find.byKey(const Key('home-selected')), findsOneWidget);
  });

  testWidgets('opens the lessons page in the saved language', (tester) async {
    SharedPreferences.setMockInitialValues({'kiu.locale': 'ru'});
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    expect(
      loadedUrls.single,
      'https://uz.do-kazankiu.ru/ru/profile/my-online-lessons',
    );
  });

  testWidgets('reloads the current page when the language changes', (
    tester,
  ) async {
    final appController = await controller();
    await tester.pumpWidget(
      KiuApp(
        controller: appController,
        homeRequests: ValueNotifier<int>(0),
        navigationRequests: ValueNotifier<Uri?>(
          Uri.parse('https://uz.do-kazankiu.ru/uz/profile/lesson/42'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-ru')));
    await tester.pumpAndSettle();

    expect(appController.settings.localeTag, 'ru');
    // Same page, Russian prefix: the user keeps their place.
    expect(loadedUrls.last, 'https://uz.do-kazankiu.ru/ru/profile/lesson/42');
  });

  testWidgets('switches the exam platform language too', (tester) async {
    final appController = await controller();
    await tester.pumpWidget(
      KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
    );
    // The exam host is reached by a link in the LMS menu, so drive the same
    // page callback a real navigation there would.
    navigateTo!('https://test.do-kazankiu.ru/uz/tests');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-ru')));
    await tester.pumpAndSettle();

    expect(loadedUrls.last, 'https://test.do-kazankiu.ru/ru/tests');
  });

  testWidgets('leaves the exam platform free of injected scripts', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    injectedScripts.clear();
    navigateTo!('https://test.do-kazankiu.ru/uz/tests');
    await tester.pumpAndSettle();

    // Theme, playback and the KiuBridge stay LMS-only: the exam host shares a
    // session with the LMS, so anything injected there is a real leak path.
    expect(injectedScripts, isEmpty);
  });

  testWidgets('never sends an English prefix to the site', (tester) async {
    SharedPreferences.setMockInitialValues({'kiu.locale': 'ru'});
    final appController = await controller();
    await tester.pumpWidget(
      KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
    );

    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-en')));
    await tester.pumpAndSettle();

    expect(appController.settings.localeTag, 'en');
    // App UI turns English, but the servers only understand uz/ru and would
    // blindly persist a bogus `lang=en` cookie.
    expect(loadedUrls.last, contains('/uz/'));
    expect(loadedUrls, everyElement(isNot(contains('/en/'))));
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
    expect(find.text('19:00 | 09-сентябр'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheduled-lessons-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheduled-lessons-list')), findsNothing);
    expect(find.byKey(const Key('scheduled-lessons-menu')), findsOneWidget);
  });

  testWidgets('opens Useful links with test platforms, books and apps', (
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
    await tester.ensureVisible(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();

    // Section captions render upper-cased, so match them case-insensitively
    // rather than pinning the test to the display transform.
    expect(find.text('Фойдали ҳаволалар'), findsOneWidget);
    expect(findCaption('Тест платформалари'), findsOneWidget);
    expect(find.text('nurul-izoh.com'), findsOneWidget);
    expect(findCaption('PDF китоблар'), findsOneWidget);
    expect(find.text('Nurul Izoh'), findsOneWidget);
    expect(find.text('Mabdaul qiroat 2'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Riyozus solihiyn'), 300);
    await tester.pumpAndSettle();

    expect(findCaption('Иловалар'), findsOneWidget);
    expect(find.text('Riyozus solihiyn'), findsOneWidget);
  });

  testWidgets('tapping a PDF book opens the in-app viewer', (tester) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nurul Izoh'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(AppBar, 'Nurul Izoh'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(find.byKey(const Key('pdf-loading')), findsOneWidget);
    expect(loadedUrls.last, startsWith('https://docs.google.com/viewer?url='));
  });

  testWidgets(
    'toggles a lesson call from the phone icon in Scheduled lessons',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'kiu.lessonSnapshot':
            '[{"title":"Aqidah","websiteStart":"2027-09-09 19:00"}]',
      });
      final appController = await controller();
      await tester.pumpWidget(
        KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
      );
      await tester.tap(find.byKey(const Key('actions-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scheduled-lessons-menu')));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const Key('scheduled-lesson-call-0'));
      // Calls are off globally by default, so the icon starts struck through.
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: toggle, matching: find.byType(Icon)),
            )
            .icon,
        Icons.phone_disabled,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Icon>(
              find.descendant(of: toggle, matching: find.byType(Icon)),
            )
            .icon,
        Icons.call,
      );
      final lesson = appController.scheduledLessons.single;
      expect(appController.settings.callEnabledFor(lesson), isTrue);
    },
  );

  testWidgets('shows custom reminders as chips that can be removed', (
    tester,
  ) async {
    final appController = await controller();
    // The chip row is only interactive while reminders are on, which is what
    // the offsets are for in the first place.
    await appController.setRemindersEnabled(true);
    await appController.setReminderOffsets([75, 45, 60, 15, 0]);
    await tester.pumpWidget(
      KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-settings-menu')));
    await tester.pumpAndSettle();

    // Custom offsets share the chip row with the presets rather than living in
    // their own list below the form.
    final custom = find.byKey(const Key('reminder-custom-75'));
    expect(custom, findsOneWidget);
    expect(find.byKey(const Key('reminder-custom-45')), findsOneWidget);
    expect(find.text('1 Соат 15 Дақиқа'), findsOneWidget);
    expect(find.text('45 Дақиқа'), findsOneWidget);
    // Presets stay selectable alongside them.
    expect(find.byKey(const Key('reminder-offset-60')), findsOneWidget);

    await tester.ensureVisible(custom);
    await tester.pumpAndSettle();
    // The chip's delete button renders outside the keyed chip subtree, so
    // reach it by its tooltip.
    await tester.tap(find.byTooltip('Ўчириш').first);
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
    await tester.tap(find.byKey(const Key('notification-settings-menu')));
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
    await tester.tap(find.byKey(const Key('notification-settings-menu')));
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
    await tester.tap(find.byKey(const Key('notification-settings-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-sound-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Овозни танлаш'));
    await tester.pumpAndSettle();

    expect(find.text('Morning bell'), findsOneWidget);
  });

  Future<void> openNotificationSettings(
    WidgetTester tester,
    AppController appController,
  ) async {
    await tester.pumpWidget(
      KiuApp(controller: appController, homeRequests: ValueNotifier<int>(0)),
    );
    await tester.tap(find.byKey(const Key('actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-settings-menu')));
    await tester.pumpAndSettle();
  }

  /// Reads the granted/not-granted badge from a permission row.
  bool badgeGranted(WidgetTester tester, String key) => tester
      .widget<PermissionBadge>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(PermissionBadge),
        ),
      )
      .granted;

  testWidgets('overlay access badge reads not granted while missing', (
    tester,
  ) async {
    final backgroundAccess = FakeBackgroundAccessGateway()
      ..overlaysAllowed = false;
    final appController = await controller(null, backgroundAccess);
    await appController.setCallsEnabled(true);
    await openNotificationSettings(tester, appController);

    expect(badgeGranted(tester, 'overlay-access-tile'), isFalse);
  });

  testWidgets('overlay access badge reads granted once allowed', (
    tester,
  ) async {
    final backgroundAccess = FakeBackgroundAccessGateway()
      ..overlaysAllowed = true;
    final appController = await controller(null, backgroundAccess);
    await appController.setCallsEnabled(true);
    await openNotificationSettings(tester, appController);

    expect(badgeGranted(tester, 'overlay-access-tile'), isTrue);
  });

  testWidgets('hides call-only permissions while calls are off', (
    tester,
  ) async {
    final backgroundAccess = FakeBackgroundAccessGateway()
      ..overlaysAllowed = false;
    final appController = await controller(null, backgroundAccess);
    await openNotificationSettings(tester, appController);

    expect(find.byKey(const Key('overlay-access-tile')), findsNothing);
    expect(find.byKey(const Key('full-screen-access')), findsNothing);
    // The two that are not call-specific stay listed either way.
    expect(find.byKey(const Key('battery-access')), findsOneWidget);
    expect(find.byKey(const Key('exact-timing')), findsOneWidget);
  });

  testWidgets('tapping the overlay access row opens Android settings', (
    tester,
  ) async {
    final backgroundAccess = FakeBackgroundAccessGateway()
      ..overlaysAllowed = false;
    final appController = await controller(null, backgroundAccess);
    await appController.setCallsEnabled(true);
    await openNotificationSettings(tester, appController);

    final tile = find.byKey(const Key('overlay-access-tile'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(backgroundAccess.overlaySettingsOpened, 1);
  });

  testWidgets('every permission row shows its granted state', (tester) async {
    // A granted permission used to be indistinguishable from an absent row.
    final backgroundAccess = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false
      ..fullScreenIntentAllowed = true
      ..overlaysAllowed = false;
    final appController = await controller(null, backgroundAccess);
    await appController.setCallsEnabled(true);
    await openNotificationSettings(tester, appController);

    expect(badgeGranted(tester, 'battery-access'), isFalse);
    expect(badgeGranted(tester, 'full-screen-access'), isTrue);
    expect(badgeGranted(tester, 'overlay-access-tile'), isFalse);
  });

  testWidgets('tapping the battery row opens Android settings', (tester) async {
    final backgroundAccess = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false;
    final appController = await controller(null, backgroundAccess);
    await openNotificationSettings(tester, appController);

    final tile = find.byKey(const Key('battery-access'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(backgroundAccess.batterySettingsOpened, 1);
  });

  testWidgets('scheduled lessons page can sync and shows the last sync', (
    tester,
  ) async {
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

    final syncBar = find.byKey(const Key('scheduled-lessons-sync'));
    expect(syncBar, findsOneWidget);
    // Never synced yet, so the bar reports that rather than a timestamp.
    expect(
      find.descendant(
        of: syncBar,
        matching: find.text('Охирги синхронлаш: Ҳали йўқ'),
      ),
      findsOneWidget,
    );

    await tester.tap(syncBar);
    await tester.pumpAndSettle();

    // The list is still there: syncing rebuilds the sheet in place.
    expect(find.byKey(const Key('scheduled-lessons-list')), findsOneWidget);
  });

  testWidgets('Useful links returns to the settings sheet, not the WebView', (
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
    await tester.ensureVisible(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('useful-links-menu')));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Back must land back in Settings rather than dropping to the WebView.
    expect(find.byKey(const Key('useful-links-menu')), findsOneWidget);
  });
}
