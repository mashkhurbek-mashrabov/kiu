import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/core/constants.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
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

const videoUrl = 'https://uz.do-kazankiu.ru/uz/my-course/25/609/video';
const rutubeUrl = 'https://uz.do-kazankiu.ru/uz/my-course/8/17/video-iframe';

final resumeRow = find.byKey(const Key('resume-last-video-menu'));

Future<SettingsRepository> repositoryWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsRepository(await SharedPreferences.getInstance());
}

void main() {
  group('isVideoLessonUri', () {
    test('accepts both player kinds under either language', () {
      for (final url in const [
        videoUrl,
        rutubeUrl,
        'https://uz.do-kazankiu.ru/ru/my-course/25/609/VIDEO',
      ]) {
        expect(isVideoLessonUri(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('rejects other hosts, http, other pages and other shapes', () {
      for (final url in const [
        'http://uz.do-kazankiu.ru/uz/my-course/25/609/video',
        'https://evil.example/uz/my-course/25/609/video',
        'https://test.do-kazankiu.ru/uz/my-course/25/609/video',
        'https://uz.do-kazankiu.ru/uz/my-course/25/609/test',
        'https://uz.do-kazankiu.ru/uz/my-course/25/609',
        'https://uz.do-kazankiu.ru/uz/my-course/25/609/video/extra',
        'https://uz.do-kazankiu.ru/en/my-course/25/609/video',
        'https://uz.do-kazankiu.ru/uz/my-course/0/609/video',
        'https://uz.do-kazankiu.ru/uz/my-course/x/609/video',
      ]) {
        expect(isVideoLessonUri(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });

  group('SettingsRepository.lastVideo', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('round-trips url and position', () async {
      final repository = await repositoryWith({});
      expect(repository.lastVideo, isNull);

      await repository.saveLastVideo(Uri.parse(videoUrl), 123.4);

      expect(repository.lastVideo?.url, Uri.parse(videoUrl));
      expect(repository.lastVideo?.seconds, 123.4);
    });

    test('reads anything unusable as nothing to resume', () async {
      for (final Object value in [
        'not json',
        42,
        '[1, 2]',
        jsonEncode({'url': videoUrl}),
        jsonEncode({'url': videoUrl, 'seconds': '12'}),
        jsonEncode({'url': videoUrl, 'seconds': -1}),
        // Parses to infinity, which the finite check must reject.
        '{"url": "$videoUrl", "seconds": 1e400}',
        jsonEncode({'url': 42, 'seconds': 12}),
        jsonEncode({
          'url': 'https://evil.example/uz/my-course/25/609/video',
          'seconds': 12,
        }),
        jsonEncode({
          'url': 'https://uz.do-kazankiu.ru/uz/profile/my-online-lessons',
          'seconds': 12,
        }),
      ]) {
        final repository = await repositoryWith({'kiu.lastVideo': value});
        expect(repository.lastVideo, isNull, reason: '$value');
      }
    });
  });

  group('resume row', () {
    setUp(() {
      WebViewPlatform.instance = FakeWebViewPlatform();
      SharedPreferences.setMockInitialValues({});
      injectedScripts.clear();
      loadedUrls.clear();
      navigateTo = null;
      finishPage = null;
      postToBridge = null;
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

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('actions-menu')));
      await tester.pumpAndSettle();
    }

    Future<void> progress(WidgetTester tester, String url, num seconds) async {
      finishPage!(url);
      await tester.pumpAndSettle();
      postToBridge!(jsonEncode({'type': 'videoProgress', 'seconds': seconds}));
      await tester.pumpAndSettle();
    }

    testWidgets('is hidden until a video position is saved', (tester) async {
      await mount(tester);
      await openSettings(tester);

      expect(resumeRow, findsNothing);
    });

    testWidgets('appears with the saved position after playback', (
      tester,
    ) async {
      await mount(tester);
      await progress(tester, videoUrl, 3725.9);
      expect(
        injectedScripts.any((script) => script.contains('videoProgress')),
        isTrue,
      );

      await openSettings(tester);

      expect(resumeRow, findsOneWidget);
      expect(find.text('1:02:05'), findsOneWidget);
    });

    testWidgets('ignores progress reported from a non-video page', (
      tester,
    ) async {
      await mount(tester);
      await progress(tester, 'https://uz.do-kazankiu.ru/uz/', 42);
      await openSettings(tester);

      expect(resumeRow, findsNothing);
    });

    testWidgets('tapping it reopens the video and seeks on load', (
      tester,
    ) async {
      await mount(tester);
      await progress(tester, rutubeUrl, 303.6);
      await openSettings(tester);
      expect(find.text('5:03'), findsOneWidget);
      loadedUrls.clear();

      await tester.tap(resumeRow);
      await tester.pumpAndSettle();
      expect(loadedUrls, [rutubeUrl]);

      injectedScripts.clear();
      finishPage!(rutubeUrl);
      await tester.pumpAndSettle();
      expect(
        injectedScripts.where((s) => s.contains('const target = 303.6')),
        hasLength(1),
      );

      // Consumed by that load: the next one must not seek again.
      injectedScripts.clear();
      finishPage!(rutubeUrl);
      await tester.pumpAndSettle();
      expect(injectedScripts.any((s) => s.contains('const target')), isFalse);
    });
  });
}
