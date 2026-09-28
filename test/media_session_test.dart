import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/media_session_service.dart';
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
const homeUrl = 'https://uz.do-kazankiu.ru/uz/';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({});
    injectedScripts.clear();
    loadedUrls.clear();
    navigateTo = null;
    finishPage = null;
    postToBridge = null;
    calls.clear();
    messenger.setMockMethodCallHandler(mediaChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(mediaChannel, null));

  Future<void> mountOn(WidgetTester tester, String url) async {
    await tester.pumpWidget(
      KiuApp(
        controller: await controller(),
        homeRequests: ValueNotifier<int>(0),
      ),
    );
    await tester.pumpAndSettle();
    navigateTo!(url);
    finishPage!(url);
    await tester.pumpAndSettle();
  }

  Future<void> post(WidgetTester tester, Map<String, Object?> message) async {
    postToBridge!(jsonEncode(message));
    await tester.pumpAndSettle();
  }

  /// Delivers a native → Dart call on the media channel.
  Future<void> fromNative(WidgetTester tester, String method, Object? args) =>
      tester.runAsync(
        () => messenger.handlePlatformMessage(
          mediaChannel.name,
          mediaChannel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        ),
      );

  Map<Object?, Object?> lastUpdate() =>
      calls.lastWhere((c) => c.method == 'update').arguments
          as Map<Object?, Object?>;

  testWidgets('videoState reaches the session with the WebView title', (
    tester,
  ) async {
    await mountOn(tester, videoUrl);
    await post(tester, {
      'type': 'videoState',
      'playing': true,
      'seconds': 12.5,
      'duration': 600,
      'rate': 1.5,
      'title': 'Injected by the page',
    });

    final update = lastUpdate();
    expect(update['playing'], isTrue);
    expect(update['position'], 12.5);
    expect(update['duration'], 600.0);
    expect(update['speed'], 1.5);
    // Dart's own title, never the payload's.
    expect(update['title'], fakePageTitle);
    for (final key in const [
      'channelName',
      'playLabel',
      'pauseLabel',
      'rewindLabel',
      'forwardLabel',
      'closeLabel',
    ]) {
      expect(update[key], isA<String>().having((s) => s, key, isNotEmpty));
    }
  });

  testWidgets('malformed state and non-video pages are ignored', (
    tester,
  ) async {
    await mountOn(tester, videoUrl);
    for (final message in <Map<String, Object?>>[
      {'type': 'videoState', 'playing': 'yes', 'seconds': 1},
      {'type': 'videoState', 'playing': true, 'seconds': -1},
      {'type': 'videoState', 'playing': true, 'seconds': '1'},
      {'type': 'videoState', 'playing': true},
    ]) {
      await post(tester, message);
    }
    expect(calls, isEmpty);

    navigateTo!(homeUrl);
    finishPage!(homeUrl);
    await tester.pumpAndSettle();
    await post(tester, {'type': 'videoState', 'playing': true, 'seconds': 1});
    expect(calls, isEmpty);
  });

  testWidgets('bad duration and rate fall back instead of dropping', (
    tester,
  ) async {
    await mountOn(tester, videoUrl);
    await post(tester, {
      'type': 'videoState',
      'playing': false,
      'seconds': 3,
      'duration': 'long',
      'rate': 0,
    });

    expect(lastUpdate()['duration'], 0.0);
    expect(lastUpdate()['speed'], 1.0);
  });

  testWidgets('leaving the video page clears the session', (tester) async {
    await mountOn(tester, videoUrl);
    await post(tester, {'type': 'videoState', 'playing': true, 'seconds': 1});
    calls.clear();

    navigateTo!(homeUrl);
    await tester.pumpAndSettle();

    expect(calls.map((c) => c.method), ['clear']);
  });

  testWidgets('a native command runs only the four known actions', (
    tester,
  ) async {
    await mountOn(tester, videoUrl);
    injectedScripts.clear();

    await fromNative(tester, 'command', 'forward');
    expect(injectedScripts, hasLength(1));
    expect(injectedScripts.single, contains('const action = "forward"'));

    injectedScripts.clear();
    await fromNative(tester, 'command', 'navigate');
    await fromNative(tester, 'command', 42);
    expect(injectedScripts, isEmpty);
  });

  testWidgets('a native command is ignored off a video page', (tester) async {
    await mountOn(tester, homeUrl);
    injectedScripts.clear();

    await fromNative(tester, 'command', 'play');
    expect(injectedScripts, isEmpty);
  });

  testWidgets('PiP hides the nav bar and lays the video out alone', (
    tester,
  ) async {
    await mountOn(tester, videoUrl);
    expect(find.byKey(const Key('nav-bar')), findsOneWidget);
    injectedScripts.clear();

    await fromNative(tester, 'pipChanged', true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-bar')), findsNothing);
    expect(injectedScripts.single, contains('const on = true'));

    await fromNative(tester, 'pipChanged', false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-bar')), findsOneWidget);
  });
}
