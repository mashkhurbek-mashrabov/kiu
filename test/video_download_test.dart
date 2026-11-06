import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/video_download.dart';
import 'package:kiu/services/video_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<SettingsRepository> repositoryWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsRepository(await SharedPreferences.getInstance());
}

final lessonPage = Uri.parse(
  'https://uz.do-kazankiu.ru/uz/my-course/5/20/video',
);
final videoFile = Uri.parse(
  'https://uz.do-kazankiu.ru/videos/lessons/5/2024-10-02_9f52.mp4',
);

Map<String, Object?> entryJson({String? path}) => {
  'key': '5/20',
  'title': 'Lesson',
  'lessonUrl': lessonPage.toString(),
  'downloadId': 7,
  'savedAt': 0,
  'path': path,
  'bytes': 10,
};

void main() {
  group('videoDownloadKey', () {
    test('is language-free for video pages', () {
      for (final lang in ['uz', 'ru']) {
        expect(
          videoDownloadKey(
            Uri.parse('https://uz.do-kazankiu.ru/$lang/my-course/5/20/video'),
          ),
          '5/20',
        );
      }
    });

    test('is null for iframe lessons, other routes and other hosts', () {
      for (final url in [
        'https://uz.do-kazankiu.ru/ru/my-course/8/99/video-iframe',
        'https://uz.do-kazankiu.ru/uz/profile/my-courses/2',
        'https://evil.example/uz/my-course/5/20/video',
        'http://uz.do-kazankiu.ru/uz/my-course/5/20/video',
      ]) {
        expect(videoDownloadKey(Uri.parse(url)), isNull, reason: url);
      }
    });
  });

  test('isLessonVideoFile accepts only LMS mp4 files under /videos/', () {
    expect(isLessonVideoFile(videoFile), isTrue);
    for (final url in [
      'blob:https://uz.do-kazankiu.ru/abc',
      'https://evil.example/videos/a.mp4',
      'http://uz.do-kazankiu.ru/videos/a.mp4',
      'https://uz.do-kazankiu.ru/uploads/a.mp4',
      'https://uz.do-kazankiu.ru/videos/a.m3u8',
    ]) {
      expect(isLessonVideoFile(Uri.parse(url)), isFalse, reason: url);
    }
  });

  group('loadVideoDownloads', () {
    test('unparsable JSON or the wrong shape is an empty list', () async {
      for (final raw in ['{not json', '{"a":1}', '42']) {
        final repository = await repositoryWith({'kiu.videoDownloads': raw});
        expect(repository.loadVideoDownloads(), isEmpty, reason: raw);
      }
      final wrongType = await repositoryWith({'kiu.videoDownloads': 3});
      expect(wrongType.loadVideoDownloads(), isEmpty);
    });

    test('drops bad entries and keeps the good ones', () async {
      final repository = await repositoryWith({
        'kiu.videoDownloads': jsonEncode([
          entryJson(path: '/files/5-20.mp4'),
          {...entryJson(), 'downloadId': 'seven'},
          {...entryJson(), 'key': '9/9'}, // key does not match the URL
          {
            ...entryJson(),
            'lessonUrl': 'https://evil.example/uz/my-course/5/20/video',
          },
          'garbage',
        ]),
      });
      final loaded = repository.loadVideoDownloads();
      expect(loaded, hasLength(1));
      expect(loaded.single.path, '/files/5-20.mp4');
      expect(loaded.single.done, isTrue);
    });
  });

  group('parseByteRange', () {
    test('whole file without a header', () {
      expect(parseByteRange(null, 100), (0, 99));
    });
    test('open, closed and suffix ranges', () {
      expect(parseByteRange('bytes=10-', 100), (10, 99));
      expect(parseByteRange('bytes=10-19', 100), (10, 19));
      expect(parseByteRange('bytes=10-500', 100), (10, 99));
      expect(parseByteRange('bytes=-30', 100), (70, 99));
    });
    test('unsatisfiable or malformed ranges', () {
      expect(parseByteRange('bytes=100-', 100), isNull);
      expect(parseByteRange('bytes=20-10', 100), isNull);
      expect(parseByteRange('bytes=-0', 100), isNull);
      expect(parseByteRange('items=0-1', 100), isNull);
    });
  });

  group('LocalVideoServer', () {
    late Directory dir;
    late File file;
    late LocalVideoServer server;
    final client = HttpClient();

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kiu-video');
      file = File('${dir.path}/5-20.mp4')
        ..writeAsBytesSync(List.generate(100, (i) => i));
      server = LocalVideoServer(
        pathFor: (key) => key == '5/20' ? file.path : null,
      );
    });

    tearDown(() async {
      await server.close();
      await dir.delete(recursive: true);
    });

    Future<HttpClientResponse> get(Uri url, {String? range}) async {
      final request = await client.getUrl(url);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      return request.close();
    }

    test('serves a range of an indexed file', () async {
      final url = await server.urlFor('5/20');
      expect(url.host, '127.0.0.1');
      final response = await get(url, range: 'bytes=10-19');
      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 10-19/100',
      );
      final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(body, List.generate(10, (i) => i + 10));
    });

    test('refuses a wrong token and an unknown key', () async {
      final url = await server.urlFor('5/20');
      final wrongToken = url.replace(
        path: url.path.replaceFirst(url.pathSegments.first, 'x' * 32),
      );
      expect((await get(wrongToken)).statusCode, HttpStatus.notFound);
      final unknown = await server.urlFor('6/1');
      expect((await get(unknown)).statusCode, HttpStatus.notFound);
    });
  });

  group('VideoDownloadService', () {
    late FakeVideoDownloadGateway gateway;
    late VideoDownloadService service;

    setUp(() async {
      gateway = FakeVideoDownloadGateway();
      service = VideoDownloadService(
        repository: await repositoryWith({}),
        gateway: gateway,
      );
    });

    test('rejects URLs that are not lesson video files', () async {
      for (final url in [
        'https://evil.example/videos/a.mp4',
        'blob:https://uz.do-kazankiu.ru/abc',
      ]) {
        await expectLater(
          service.start(
            key: '5/20',
            title: 'Lesson',
            lessonUrl: lessonPage,
            videoUrl: Uri.parse(url),
          ),
          throwsArgumentError,
        );
      }
      expect(gateway.enqueued, isEmpty);
    });

    test('starts once, tracks progress, then completes', () async {
      for (var i = 0; i < 2; i++) {
        await service.start(
          key: '5/20',
          title: 'Lesson',
          lessonUrl: lessonPage,
          videoUrl: videoFile,
        );
      }
      expect(gateway.enqueued, hasLength(1));
      expect(gateway.enqueued.single.fileName, '5-20.mp4');

      gateway.statuses[1] = (
        id: 1,
        status: 'running',
        downloaded: 25,
        total: 100,
        path: null,
      );
      await service.refresh();
      expect(service.entryFor('5/20')!.fraction, 0.25);
      expect(await service.localUrl('5/20'), isNull);

      final dir = await Directory.systemTemp.createTemp('kiu-video');
      addTearDown(() => dir.delete(recursive: true));
      final path = (File('${dir.path}/5-20.mp4')..writeAsBytesSync([1])).path;
      gateway.statuses[1] = (
        id: 1,
        status: 'done',
        downloaded: 100,
        total: 100,
        path: path,
      );
      await service.refresh();
      final done = service.entryFor('5/20')!;
      expect(done.done, isTrue);
      expect(done.bytes, 100);
      expect(await service.localUrl('5/20'), isNotNull);
    });

    test('drops failed downloads and deletes one or all', () async {
      for (final key in ['5/20', '5/21']) {
        await service.start(
          key: key,
          title: key,
          lessonUrl: Uri.parse(
            'https://uz.do-kazankiu.ru/uz/my-course/$key/video',
          ),
          videoUrl: videoFile,
        );
      }
      gateway.statuses[1] = (
        id: 1,
        status: 'failed',
        downloaded: 0,
        total: 0,
        path: null,
      );
      gateway.statuses[2] = (
        id: 2,
        status: 'running',
        downloaded: 0,
        total: 0,
        path: null,
      );
      await service.refresh();
      expect(service.downloads.value.map((e) => e.key), ['5/21']);
      expect(gateway.removed, [1]);

      await service.delete('5/21');
      expect(service.downloads.value, isEmpty);
      expect(gateway.removed, [1, 2]);

      await service.start(
        key: '5/20',
        title: 'Lesson',
        lessonUrl: lessonPage,
        videoUrl: videoFile,
      );
      await service.deleteAll();
      expect(service.downloads.value, isEmpty);
      expect(gateway.removed, [1, 2, 3]);
    });

    test('the index survives a restart', () async {
      final repository = await repositoryWith({});
      final first = VideoDownloadService(
        repository: repository,
        gateway: gateway,
      );
      await first.start(
        key: '5/20',
        title: 'Lesson',
        lessonUrl: lessonPage,
        videoUrl: videoFile,
      );
      final second = VideoDownloadService(
        repository: repository,
        gateway: gateway,
      );
      expect(second.downloads.value.single.key, '5/20');
      expect(second.downloads.value.single, isA<VideoDownload>());
    });
  });
}
