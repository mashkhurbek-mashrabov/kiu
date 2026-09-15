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
    canGoBackResult = false;
    goBackCount = 0;
  });

  testWidgets('uses a headerless floating five-action nav pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    expect(find.byType(AppBar), findsNothing);
    // A floating pill, so no docked BottomAppBar at all.
    expect(find.byType(BottomAppBar), findsNothing);
    expect(find.byKey(const Key('nav-bar')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('nav-bar'))).height, 56);
    for (final key in const [
      'nav-back',
      'nav-home',
      'nav-lessons',
      'nav-refresh',
      'actions-menu',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(find.byKey(const Key('nav-forward')), findsNothing);
    // Icon-only: the name is reachable by long press instead.
    expect(
      find.descendant(
        of: find.byKey(const Key('nav-bar')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    // Opens on the lessons page, so Lessons -- not Home -- carries the pill.
    expect(find.byKey(const Key('lessons-selected')), findsOneWidget);
    expect(find.byKey(const Key('home-selected')), findsNothing);
    expect(find.byKey(const Key('page-progress')), findsOneWidget);
  });

  testWidgets('tapping refresh turns the icon a full rotation', (tester) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    await tester.pumpAndSettle();

    double turns() => tester
        .widget<RotationTransition>(
          find.descendant(
            of: find.byKey(const Key('nav-refresh')),
            matching: find.byType(RotationTransition),
          ),
        )
        .turns
        .value;

    expect(turns(), 0);

    await tester.tap(find.byKey(const Key('nav-refresh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Mid-spin: the icon is part way round, not waiting or already done.
    expect(turns(), greaterThan(0));
    expect(turns(), lessThan(1));

    // Settles on a whole turn, so the glyph ends where it started.
    await tester.pumpAndSettle();
    expect(turns(), 1);
  });

  testWidgets('tapping back swings the chevron and settles', (tester) async {
    // Back is disabled until the WebView reports history behind the page.
    canGoBackResult = true;
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    // _canBack is refreshed in onPageFinished, so land a page first. Not the
    // lessons page: that one also kicks off permission onboarding, whose
    // dialog then covers the bar.
    finishPage?.call('https://uz.do-kazankiu.ru/uz/profile/lesson/42');
    await tester.pumpAndSettle();

    Offset offset() => tester
        .widget<SlideTransition>(
          find.descendant(
            of: find.byKey(const Key('nav-back')),
            matching: find.byType(SlideTransition),
          ),
        )
        .position
        .value;

    expect(offset(), Offset.zero);

    await tester.tap(find.byKey(const Key('nav-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    // Swings left -- the direction the page itself is about to move.
    expect(offset().dx, lessThan(0));

    await tester.pumpAndSettle();
    expect(offset(), Offset.zero);
  });

  testWidgets('the selection capsule slides to the slot it marks', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    await tester.pumpAndSettle();

    // Opens on the lessons page, so the capsule starts over that slot.
    Rect capsule() => tester.getRect(
      find.descendant(
        of: find.byKey(const Key('nav-bar')),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    final lessonsSlot = tester.getRect(find.byKey(const Key('nav-lessons')));
    expect(capsule().center.dx, closeTo(lessonsSlot.center.dx, 1));

    // Moving to a course page has to animate it across, not jump it: mid
    // flight it sits between the two slots.
    navigateTo?.call('https://uz.do-kazankiu.ru/uz/profile/my-courses/2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final homeSlot = tester.getRect(find.byKey(const Key('nav-home')));
    final midFlight = capsule().center.dx;
    expect(midFlight, lessThan(lessonsSlot.center.dx));
    expect(midFlight, greaterThan(homeSlot.center.dx));

    await tester.pumpAndSettle();
    expect(capsule().center.dx, closeTo(homeSlot.center.dx, 1));
  });

  testWidgets('the loading bar stays clear of the floating nav pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    final progress = tester.getRect(find.byKey(const Key('page-progress')));
    final bar = tester.getRect(find.byKey(const Key('nav-bar')));
    // The pill paints after the progress bar, so any overlap hides the
    // indicator outright -- which is how it went missing once the bar started
    // floating instead of sitting docked below it.
    expect(progress.overlaps(bar), isFalse);
    expect(progress.bottom, lessThanOrEqualTo(bar.top));
  });

  testWidgets('the nav pill floats clear of both screen edges', (tester) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    final bar = tester.getRect(find.byKey(const Key('nav-bar')));
    final screen = tester.getSize(find.byType(MaterialApp));
    // Inset on both sides, so it reads as a pill rather than a docked bar.
    expect(bar.left, greaterThan(0));
    expect(bar.right, lessThan(screen.width));
    // Off the bottom edge, but only just -- deliberately tighter than iOS.
    final gap = screen.height - bar.bottom;
    expect(gap, greaterThan(0));
    expect(gap, lessThan(24));
  });

  testWidgets('Home falls back to the lessons page before a level is known', (
    tester,
  ) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    loadedUrls.clear();

    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pumpAndSettle();

    expect(loadedUrls.last, contains('/uz/profile/my-online-lessons'));
  });

  testWidgets('Home opens the cached course level in the saved language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'kiu.courseLevel': 2,
      'kiu.locale': 'ru',
    });
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    loadedUrls.clear();

    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pumpAndSettle();

    expect(
      loadedUrls.last,
      'https://uz.do-kazankiu.ru/ru/profile/my-courses/2',
    );
  });

  testWidgets('Lessons always opens the scheduled lessons page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'kiu.courseLevel': 2});
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    loadedUrls.clear();

    await tester.tap(find.byKey(const Key('nav-lessons')));
    await tester.pumpAndSettle();

    expect(loadedUrls.last, contains('/uz/profile/my-online-lessons'));
  });

  testWidgets('highlights Home on a course page', (tester) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
        navigationRequests: ValueNotifier<Uri?>(
          Uri.parse('https://uz.do-kazankiu.ru/uz/profile/my-courses/2'),
        ),
      ),
    );

    expect(find.byKey(const Key('home-selected')), findsOneWidget);
    expect(find.byKey(const Key('lessons-selected')), findsNothing);
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

    final colors = Theme.of(tester.element(find.byKey(const Key('nav-bar'))))
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

    final colors = Theme.of(tester.element(find.byKey(const Key('nav-bar'))))
        .colorScheme;
    expect(colors.brightness, Brightness.light);
    expect(colors.surface, lightSurface);
  });

  // The settings sheet and the nav bar have to read as one surface. Before the
  // redesign the scheme was seeded straight from kiuGreen, so `primary` — which
  // drives the switches, chips, slider and every section caption — came out
  // green against the bar's neutral glass. These assert the roles rather than
  // any one widget's paint, because that is where the green actually entered.
  testWidgets('drives settings chrome from a neutral primary, not brand green', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'kiu.themeMode': 'light'});
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );

    final colors = Theme.of(tester.element(find.byKey(const Key('nav-bar'))))
        .colorScheme;
    expect(colors.primary, isNot(kiuGreen));
    expect(colors.primary, lightInk);
    // The sheet paints on this; a tinted container brings the green wash back.
    expect(colors.surfaceContainerLow, lightSurface);
    expect(colors.surface, const Color(0xFFFFFFFF));
  });

  test('no scheme role still carries the seeded green', () {
    // fromSeed derives every role from kiuGreen, so pinning them by hand is
    // easy to do incompletely — the first pass missed secondaryContainer and
    // the chips stayed green on device. This sweeps all of them instead:
    // anything green-hued with real saturation is a leak.
    bool greenish(Color c) {
      final hsl = HSLColor.fromColor(c);
      return hsl.hue > 80 &&
          hsl.hue < 180 &&
          hsl.saturation > 0.12 &&
          hsl.lightness > 0.05 &&
          hsl.lightness < 0.95;
    }

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final c = kiuTheme(brightness).colorScheme;
      final roles = <String, Color>{
        'primary': c.primary,
        'primaryContainer': c.primaryContainer,
        'secondary': c.secondary,
        'secondaryContainer': c.secondaryContainer,
        'surface': c.surface,
        'surfaceContainer': c.surfaceContainer,
        'surfaceContainerLow': c.surfaceContainerLow,
        'surfaceContainerHigh': c.surfaceContainerHigh,
        'surfaceContainerHighest': c.surfaceContainerHighest,
        'surfaceDim': c.surfaceDim,
        'surfaceBright': c.surfaceBright,
        'onSurface': c.onSurface,
        'onSurfaceVariant': c.onSurfaceVariant,
        'outline': c.outline,
        'outlineVariant': c.outlineVariant,
        'inverseSurface': c.inverseSurface,
        'inversePrimary': c.inversePrimary,
        'surfaceTint': c.surfaceTint,
      };
      final leaks = roles.entries
          .where((e) => greenish(e.value))
          .map((e) => e.key)
          .toList();
      expect(leaks, isEmpty, reason: 'green left in $brightness roles: $leaks');
    }
  });

  testWidgets('keeps brand green available for lesson state', (tester) async {
    // Neutral chrome must not cost the one place green carries meaning: a
    // started lesson / armed call, which has to match the home-screen widget.
    expect(brandGreen(Brightness.light), kiuGreen);
    expect(brandGreen(Brightness.dark), kiuGreenDark);
    // The deep brand green is unreadable on the near-black dark surface, which
    // is why dark mode gets the lightened variant rather than kiuGreen itself.
    expect(brandGreen(Brightness.dark), isNot(kiuGreen));
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
      Theme.of(tester.element(find.byKey(const Key('nav-bar'))))
          .colorScheme
          .surface,
      darkSurface,
    );
    expect(injectedScripts.last, contains("setItem('darkMode'"));
    expect(injectedScripts.last, contains('const dark = true'));
  });

  testWidgets('highlights nothing on another trusted page', (tester) async {
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
    expect(find.byKey(const Key('lessons-selected')), findsNothing);
  });

  testWidgets('highlights Lessons on the Russian lessons page', (tester) async {
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
    expect(find.byKey(const Key('lessons-selected')), findsOneWidget);
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

  testWidgets('a Drive book loads its preview, not the docs viewer', (
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

    await tester.ensureVisible(find.text('Рус тили луғати'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рус тили луғати'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A share link wrapped in the docs viewer renders Drive's sharing page
    // instead of the PDF, so it must use Drive's own /preview endpoint.
    expect(
      loadedUrls.last,
      'https://drive.google.com/file/d/1U6uYlS2ae3QHUYBtW7DXOi4MLjCFjr1M/preview',
    );
  });

  testWidgets('a shared Drive link drops its query and opens the preview', (
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

    await tester.ensureVisible(find.text('Рус тили дарслари'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рус тили дарслари'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The ?usp=sharing a share link carries must not reach the embed.
    expect(
      loadedUrls.last,
      'https://drive.google.com/file/d/1lKshAbXGkmOPuojCpaVz_z5XlAoZTKNw/preview',
    );
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

  testWidgets('battery badge updates on resume after granting in Settings', (
    tester,
  ) async {
    final backgroundAccess = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false;
    final appController = await controller(null, backgroundAccess);
    await openNotificationSettings(tester, appController);
    expect(badgeGranted(tester, 'battery-access'), isFalse);

    // Tapping only starts the settings activity; the badge must not claim the
    // exemption was granted just because the channel call returned.
    final tile = find.byKey(const Key('battery-access'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(backgroundAccess.batterySettingsOpened, 1);
    expect(badgeGranted(tester, 'battery-access'), isFalse);

    // The user grants it in Android settings and comes back.
    backgroundAccess.batteryOptimizationDisabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(badgeGranted(tester, 'battery-access'), isTrue);
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
