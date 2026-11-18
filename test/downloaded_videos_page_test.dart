import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/l10n/app_localizations.dart';
import 'package:kiu/services/video_download_service.dart';
import 'package:kiu/ui/downloaded_videos_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late FakeVideoDownloadGateway gateway;
  late VideoDownloadService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    gateway = FakeVideoDownloadGateway();
    service = VideoDownloadService(
      repository: SettingsRepository(await SharedPreferences.getInstance()),
      gateway: gateway,
    );
  });

  Future<void> addDownload(String key, String title) => service.start(
    key: key,
    title: title,
    lessonUrl: Uri.parse('https://uz.do-kazankiu.ru/uz/my-course/$key/video'),
    videoUrl: Uri.parse('https://uz.do-kazankiu.ru/videos/lessons/$key.mp4'),
  );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: DownloadedVideosPage(service: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state with no downloads', (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const Key('downloaded-videos-empty')), findsOneWidget);
    expect(find.byKey(const Key('delete-all-videos')), findsNothing);
  });

  testWidgets('groups videos by course, sorted by name', (tester) async {
    await addDownload('32/650', '10. Ўнинчи');
    await addDownload('32/642', '2. Иккинчи');
    await addDownload('5/20', 'Арбаъин 1');
    await service.rememberCourseNames({'32': 'Ақийдатут-Таҳовийя'});
    await pumpPage(tester);

    final named = find.byKey(const Key('downloaded-course-32'));
    final unnamed = find.byKey(const Key('downloaded-course-5'));
    expect(
      find.descendant(of: named, matching: find.text('АҚИЙДАТУТ-ТАҲОВИЙЯ')),
      findsOneWidget,
    );
    // No name learned yet: the course id stands in.
    expect(
      find.descendant(of: unnamed, matching: find.text('COURSE 5')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(named).dy,
      lessThan(tester.getTopLeft(unnamed).dy),
    );
    expect(
      tester.getTopLeft(find.text('2. Иккинчи')).dy,
      lessThan(tester.getTopLeft(find.text('10. Ўнинчи')).dy),
    );
    service.dispose();
  });

  testWidgets('deletes one video after confirming', (tester) async {
    await addDownload('5/20', 'Arbain 1');
    await addDownload('5/21', 'Arbain 2');
    await pumpPage(tester);
    expect(find.text('Arbain 1'), findsOneWidget);
    expect(find.text('Arbain 2'), findsOneWidget);

    // Cancelling the dialog keeps it.
    await tester.tap(find.byKey(const Key('delete-video-5/20')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Arbain 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-video-5/20')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Arbain 1'), findsNothing);
    expect(find.text('Arbain 2'), findsOneWidget);
    expect(gateway.removed, [1]);
    // Stops the progress poll before the binding checks for pending timers.
    service.dispose();
  });

  testWidgets('deletes all videos after confirming', (tester) async {
    await addDownload('5/20', 'Arbain 1');
    await addDownload('5/21', 'Arbain 2');
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('delete-all-videos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloaded-videos-empty')), findsOneWidget);
    expect(gateway.removed, unorderedEquals([1, 2]));
    service.dispose();
  });
}
