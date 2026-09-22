import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/services/update_downloader.dart';
import 'package:kiu/services/update_service.dart';

/// Drives the whole update path over a real socket: the checker parses a
/// release payload shaped exactly like GitHub's, the downloader streams the
/// bytes to disk, verifies the size and hands the file to the installer.
///
/// The APK bytes are served locally rather than pulled from GitHub so the test
/// stays offline and cannot be broken by the unauthenticated rate limit.
class _RecordingInstaller implements ApkInstaller {
  bool allowed = true;
  final List<String> installed = [];
  int permissionPrompts = 0;

  String? cacheDir;
  int cacheDirectoryCalls = 0;

  @override
  Future<String?> cacheDirectory() async {
    cacheDirectoryCalls++;
    return cacheDir;
  }

  @override
  Future<bool> canInstallPackages() async => allowed;

  @override
  Future<void> openInstallPermissionSettings() async => permissionPrompts++;

  /// What the system installer reports back. Defaults to a successful
  /// install; a test sets it false to stand in for the user declining
  /// Android's confirmation prompt.
  bool installSucceeds = true;

  final StreamController<bool> _results = StreamController<bool>.broadcast();

  @override
  Stream<bool> get installResults => _results.stream;

  @override
  Future<void> installApk(String path) async {
    installed.add(path);
    // The real session reports asynchronously, after the commit returns.
    scheduleMicrotask(() => _results.add(installSucceeds));
  }
}

void main() {
  late HttpServer server;
  late Directory cache;
  late List<int> apkBytes;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('kiu-update-e2e');
    // A stand-in for the release APK. Real bytes, real length -- what matters
    // here is that the stream reaches disk intact and the size check agrees.
    apkBytes = List<int>.generate(256 * 1024, (i) => i % 256);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.endsWith('.bin')) {
        request.response.statusCode = HttpStatus.notFound;
      } else if (request.uri.path.endsWith('.apk')) {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(apkBytes);
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'tag_name': 'v1.5.0',
            'body':
                '## Changes\r\n\r\n- Add in-app updates.\r\n\r\n'
                '<!-- kiu-update: build=19 mandatory=true -->',
            'assets': [
              {
                'name': 'KIU-1.5.0+19-arm64-v8a.apk',
                'browser_download_url': 'https://github.com/x/releases/download/v1.5.0/KIU-1.5.0+19-arm64-v8a.apk',
                'size': apkBytes.length,
              },
              {
                'name': 'KIU-1.5.0+19-x86_64.apk',
                'browser_download_url': 'https://github.com/x/releases/download/v1.5.0/KIU-1.5.0+19-x86_64.apk',
                'size': apkBytes.length,
              },
            ],
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  // The production allowlist only admits GitHub over https, so the loopback
  // server serving the APK bytes needs an explicit override. Scoped to
  // localhost: the point is to exercise the download, not to widen the rule.
  bool allowLoopback(Uri uri) => uri.host == server.address.host;

  String endpoint() => 'http://${server.address.host}:${server.port}/';

  String localApk(String abi) =>
      'http://${server.address.host}:${server.port}/KIU-1.5.0+19-$abi.apk';

  test(
    'check to install, for the x86_64 build actually on the emulator',
    () async {
      // The emulator runs the x86_64 split, whose raw versionCode is 4018.
      // MainActivity reports that as build 18 / abi 4.
      final checker = GitHubUpdateChecker(endpoint: endpoint());
      final result = await checker.check(installedBuild: 18, abi: 4);
      checker.close();

      expect(result.answered, isTrue);
      final update = result.update;
      expect(update, isNotNull);
      expect(update!.buildNumber, 19);
      expect(update.mandatory, isTrue, reason: 'the gate must engage');
      expect(update.versionName, '1.5.0');
      expect(update.apkUrl, endsWith('-x86_64.apk'));
      // The marker must not leak into what the user reads.
      expect(update.notes, isNot(contains('kiu-update')));
      expect(update.notes, contains('Add in-app updates.'));

      final installer = _RecordingInstaller();
      final downloader = UpdateDownloader(
        installer: installer,
        cacheDirectory: cache,
        isAllowedHost: allowLoopback,
      );
      // Point at the local copy; the host allowlist is covered separately.
      final downloaded = await downloader.download(
        AppUpdate(
          versionName: update.versionName,
          buildNumber: update.buildNumber,
          mandatory: update.mandatory,
          notes: update.notes,
          apkUrl: localApk('x86_64'),
          apkSize: update.apkSize,
        ),
      );

      expect(downloaded, isTrue);
      expect(installer.installed, hasLength(1));
      final file = File(installer.installed.single);
      expect(file.existsSync(), isTrue);
      expect(
        file.lengthSync(),
        apkBytes.length,
        reason: 'the whole APK must reach disk',
      );
      expect(downloader.progress.value.stage, UpdateDownloadStage.installing);
      downloader.dispose();
    },
  );

  test(
    'a truncated download is rejected before it reaches the installer',
    () async {
      final installer = _RecordingInstaller();
      final downloader = UpdateDownloader(
        installer: installer,
        cacheDirectory: cache,
        isAllowedHost: allowLoopback,
      );
      // Declare a size larger than what the server sends.
      final ok = await downloader.download(
        AppUpdate(
          versionName: '1.5.0',
          buildNumber: 19,
          mandatory: true,
          notes: '',
          apkUrl: localApk('x86_64'),
          apkSize: apkBytes.length + 4096,
        ),
      );

      expect(ok, isFalse);
      expect(
        installer.installed,
        isEmpty,
        reason: 'a short APK must never reach the installer',
      );
      expect(downloader.progress.value.stage, UpdateDownloadStage.failed);
      expect(
        File('${cache.path}/update.apk').existsSync(),
        isFalse,
        reason: 'the partial file is cleaned up',
      );
      downloader.dispose();
    },
  );

  test('a stale update.apk is replaced, not appended to', () async {
    File('${cache.path}/update.apk').writeAsBytesSync(List.filled(9999, 7));
    final installer = _RecordingInstaller();
    final downloader = UpdateDownloader(
      installer: installer,
      cacheDirectory: cache,
      isAllowedHost: allowLoopback,
    );
    await downloader.download(
      AppUpdate(
        versionName: '1.5.0',
        buildNumber: 19,
        mandatory: true,
        notes: '',
        apkUrl: localApk('x86_64'),
        apkSize: apkBytes.length,
      ),
    );

    expect(File('${cache.path}/update.apk').lengthSync(), apkBytes.length);
    expect(installer.installed, hasLength(1));
    downloader.dispose();
  });

  test('without install permission nothing is downloaded', () async {
    final installer = _RecordingInstaller()..allowed = false;
    final downloader = UpdateDownloader(
      installer: installer,
      cacheDirectory: cache,
      isAllowedHost: allowLoopback,
    );
    final ok = await downloader.download(
      AppUpdate(
        versionName: '1.5.0',
        buildNumber: 19,
        mandatory: true,
        notes: '',
        apkUrl: localApk('x86_64'),
        apkSize: apkBytes.length,
      ),
    );

    expect(ok, isFalse);
    expect(installer.permissionPrompts, 1);
    expect(installer.installed, isEmpty);
    // Idle, not failed: the user has something to do, and the gate keeps
    // offering the button rather than showing an error.
    expect(downloader.progress.value.stage, UpdateDownloadStage.idle);
    downloader.dispose();
  });

  // Regression: the downloader used to default to Directory.systemTemp, which
  // is /tmp -- a path that does not exist on Android. Every real download
  // failed with an unhelpful "could not download" while every test passed,
  // because the tests injected a cache directory. The platform is now the
  // source of truth, and this pins that it is actually consulted.
  test('the cache directory comes from the platform', () async {
    final installer = _RecordingInstaller()..cacheDir = cache.path;
    final downloader = UpdateDownloader(
      installer: installer,
      isAllowedHost: allowLoopback,
    );
    final ok = await downloader.download(
      AppUpdate(
        versionName: '1.5.0',
        buildNumber: 19,
        mandatory: true,
        notes: '',
        apkUrl: localApk('x86_64'),
        apkSize: apkBytes.length,
      ),
    );

    expect(installer.cacheDirectoryCalls, 1);
    expect(ok, isTrue);
    expect(installer.installed.single, '${cache.path}/update.apk');
    downloader.dispose();
  });

  test(
    'a platform with no cache directory fails instead of writing to /tmp',
    () async {
      final installer = _RecordingInstaller();
      final downloader = UpdateDownloader(
        installer: installer,
        isAllowedHost: allowLoopback,
      );
      final ok = await downloader.download(
        AppUpdate(
          versionName: '1.5.0',
          buildNumber: 19,
          mandatory: true,
          notes: '',
          apkUrl: localApk('x86_64'),
          apkSize: apkBytes.length,
        ),
      );

      expect(ok, isFalse);
      expect(installer.installed, isEmpty);
      expect(downloader.progress.value.stage, UpdateDownloadStage.failed);
      downloader.dispose();
    },
  );

  // Regression for slow downloads on a real phone: progress used to publish on
  // every ~8 KB chunk, rebuilding a Column with text layout thousands of times
  // per download while the socket read waited on each disk write.
  test('progress is published far less often than there are chunks', () async {
    final installer = _RecordingInstaller()..cacheDir = cache.path;
    final downloader = UpdateDownloader(
      installer: installer,
      isAllowedHost: allowLoopback,
    );
    var publishes = 0;
    downloader.progress.addListener(() => publishes++);

    await downloader.download(
      AppUpdate(
        versionName: '1.5.2',
        buildNumber: 21,
        mandatory: true,
        notes: '',
        apkUrl: localApk('x86_64'),
        apkSize: apkBytes.length,
      ),
    );

    // 256 KB at ~8 KB per chunk is ~32 reads; the cap is generous but still
    // far below one publish per chunk.
    expect(publishes, lessThan(20), reason: 'publishes=$publishes');
    // Whatever the throttle swallowed, the bar must land on the full size.
    expect(downloader.progress.value.received, apkBytes.length);
    expect(downloader.progress.value.total, apkBytes.length);
    downloader.dispose();
  });

  test('a non-200 response fails without leaving a partial file', () async {
    final installer = _RecordingInstaller()..cacheDir = cache.path;
    final downloader = UpdateDownloader(
      installer: installer,
      isAllowedHost: allowLoopback,
    );
    final ok = await downloader.download(
      AppUpdate(
        versionName: '1.5.2',
        buildNumber: 21,
        mandatory: true,
        notes: '',
        // Served by the same socket, but this path 404s.
        apkUrl: 'http://${server.address.host}:${server.port}/missing.bin',
        apkSize: 1024,
      ),
    );

    expect(ok, isFalse);
    expect(installer.installed, isEmpty);
    expect(downloader.progress.value.stage, UpdateDownloadStage.failed);
    expect(File('${cache.path}/update.apk').existsSync(), isFalse);
    downloader.dispose();
  });

  test('an off-allowlist APK host is refused', () async {
    final installer = _RecordingInstaller();
    // No override here on purpose: this case must exercise the real
    // production allowlist, or it proves nothing.
    final downloader = UpdateDownloader(
      installer: installer,
      cacheDirectory: cache,
    );
    final ok = await downloader.download(
      const AppUpdate(
        versionName: '1.5.0',
        buildNumber: 19,
        mandatory: true,
        notes: '',
        apkUrl: 'https://evil.example.com/payload.apk',
        apkSize: 1024,
      ),
    );

    expect(ok, isFalse);
    expect(installer.installed, isEmpty);
    downloader.dispose();
  });

  test('declining the system installer leaves a retryable failure', () async {
    // The freeze this covers: the APK downloaded, the system prompt appeared,
    // the user dismissed it -- and the gate sat on "installing" with no button
    // and, being mandatory, no way back into the app until a force-stop.
    final installer = _RecordingInstaller()..installSucceeds = false;
    final downloader = UpdateDownloader(
      installer: installer,
      cacheDirectory: cache,
      isAllowedHost: allowLoopback,
    );

    final ok = await downloader.download(
      AppUpdate(
        versionName: '1.5.0',
        buildNumber: 19,
        mandatory: true,
        notes: '',
        apkUrl: localApk('x86_64'),
        apkSize: apkBytes.length,
      ),
    );

    expect(ok, isFalse);
    expect(installer.installed, hasLength(1), reason: 'the install was tried');
    expect(
      downloader.progress.value.stage,
      UpdateDownloadStage.failed,
      reason: 'anything but `installing`, which offers the user no way out',
    );
    downloader.dispose();
  });

  test('a successful install is not reported as a failure', () async {
    final installer = _RecordingInstaller()..installSucceeds = true;
    final downloader = UpdateDownloader(
      installer: installer,
      cacheDirectory: cache,
      isAllowedHost: allowLoopback,
    );

    final ok = await downloader.download(
      AppUpdate(
        versionName: '1.5.0',
        buildNumber: 19,
        mandatory: true,
        notes: '',
        apkUrl: localApk('x86_64'),
        apkSize: apkBytes.length,
      ),
    );

    expect(ok, isTrue);
    expect(downloader.progress.value.stage, UpdateDownloadStage.installing);
    downloader.dispose();
  });
}
