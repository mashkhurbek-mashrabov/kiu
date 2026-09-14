import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';
import 'package:kiu/services/update_service.dart';

/// Serves one canned GitHub payload so the checker can be exercised over a real
/// socket without touching the network.
Future<HttpServer> _serve(Object? body, {int status = HttpStatus.ok}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    if (body != null) request.response.write(jsonEncode(body));
    await request.response.close();
  });
  return server;
}

Map<String, dynamic> _release({
  required String body,
  String tag = 'v1.5.0',
  List<Map<String, dynamic>>? assets,
}) => {
  'tag_name': tag,
  'body': body,
  'assets':
      assets ??
      [
        {
          'name': 'KIU-1.5.0+19-arm64-v8a.apk',
          'browser_download_url': 'https://github.com/mashkhurbek-mashrabov/kiu/releases/download/v1.5.0/KIU-1.5.0+19-arm64-v8a.apk',
          'size': 21000000,
        },
        {
          'name': 'KIU-1.5.0+19-x86_64.apk',
          'browser_download_url': 'https://github.com/mashkhurbek-mashrabov/kiu/releases/download/v1.5.0/KIU-1.5.0+19-x86_64.apk',
          'size': 23000000,
        },
      ],
};

Future<UpdateCheckResult> _check(
  Object? payload, {
  int installedBuild = 18,
  int abi = 2,
  int status = HttpStatus.ok,
}) async {
  final server = await _serve(payload, status: status);
  final checker = GitHubUpdateChecker(
    endpoint: 'http://${server.address.host}:${server.port}/',
  );
  final result = await checker.check(installedBuild: installedBuild, abi: abi);
  checker.close();
  await server.close(force: true);
  return result;
}

void main() {
  group('parseUpdateMarker', () {
    test('reads build, mandatory and minBuild', () {
      final marker = parseUpdateMarker(
        'Notes here\n<!-- kiu-update: build=19 mandatory=false minBuild=15 -->',
      );
      expect(marker?.build, 19);
      expect(marker?.mandatory, isFalse);
      expect(marker?.minBuild, 15);
    });

    test('defaults to mandatory when the flag is absent', () {
      expect(
        parseUpdateMarker('<!-- kiu-update: build=19 -->')?.mandatory,
        isTrue,
      );
    });

    test('a missing marker yields null rather than a lockout', () {
      expect(parseUpdateMarker('Just some release notes.'), isNull);
    });

    test('a malformed build yields null rather than a lockout', () {
      expect(parseUpdateMarker('<!-- kiu-update: build=abc -->'), isNull);
      expect(parseUpdateMarker('<!-- kiu-update: mandatory=true -->'), isNull);
      expect(parseUpdateMarker('<!-- kiu-update: build=0 -->'), isNull);
    });

    test('tolerates extra whitespace and surrounding prose', () {
      final marker = parseUpdateMarker(
        '# 1.5.0\n\nStuff.\n\n<!--   kiu-update:   build=20   mandatory=true   -->\n',
      );
      expect(marker?.build, 20);
    });
  });

  group('GitHubUpdateChecker', () {
    test('offers a newer build', () async {
      final result = await _check(
        _release(body: 'Fixes.\n<!-- kiu-update: build=19 -->'),
      );
      expect(result.answered, isTrue);
      expect(result.update?.buildNumber, 19);
      expect(result.update?.versionName, '1.5.0');
      expect(result.update?.mandatory, isTrue);
      expect(result.update?.notes, 'Fixes.');
    });

    // The regression test for the split-APK version-code trap. The arm64 APK
    // of 1.4.0+18 reports a raw versionCode of 2018; MainActivity strips the
    // ABI prefix so the Dart side compares 18 against the marker. If that
    // stripping is ever removed, 2018 > 19 makes the updater silently never
    // fire again.
    test(
      'compares against the stripped build number, not the raw code',
      () async {
        final payload = _release(body: '<!-- kiu-update: build=19 -->');
        expect((await _check(payload, installedBuild: 18)).update, isNotNull);
        expect((await _check(payload, installedBuild: 19)).update, isNull);
        expect((await _check(payload, installedBuild: 20)).update, isNull);
        // What a raw, unstripped arm64 code would look like: it must not be
        // mistaken for a build far ahead of the release.
        expect((await _check(payload, installedBuild: 2018)).update, isNull);
      },
    );

    test('picks the asset matching the running ABI', () async {
      final payload = _release(body: '<!-- kiu-update: build=19 -->');
      final arm = await _check(payload, abi: 2);
      expect(arm.update?.apkUrl, endsWith('-arm64-v8a.apk'));
      expect(arm.update?.apkSize, 21000000);
      final x86 = await _check(payload, abi: 4);
      expect(x86.update?.apkUrl, endsWith('-x86_64.apk'));
    });

    test('offers nothing when no asset matches the ABI', () async {
      final result = await _check(
        _release(
          body: '<!-- kiu-update: build=19 -->',
          assets: [
            {
              'name': 'KIU-1.5.0+19-armeabi-v7a.apk',
              'browser_download_url': 'https://github.com/mashkhurbek-mashrabov/kiu/releases/download/v1.5.0/KIU-1.5.0+19-armeabi-v7a.apk',
              'size': 19000000,
            },
          ],
        ),
      );
      expect(result.answered, isTrue);
      expect(result.update, isNull);
    });

    test('rejects an asset hosted off GitHub', () async {
      final result = await _check(
        _release(
          body: '<!-- kiu-update: build=19 -->',
          assets: [
            {
              'name': 'KIU-1.5.0+19-arm64-v8a.apk',
              'browser_download_url': 'https://evil.example.com/payload.apk',
              'size': 21000000,
            },
          ],
        ),
      );
      expect(result.update, isNull);
    });

    test('minBuild forces an otherwise optional update', () async {
      final payload = _release(
        body: '<!-- kiu-update: build=19 mandatory=false minBuild=18 -->',
      );
      // Below minBuild: forced despite mandatory=false.
      expect(
        (await _check(payload, installedBuild: 17)).update?.mandatory,
        isTrue,
      );
      // At minBuild: stays optional.
      expect(
        (await _check(payload, installedBuild: 18)).update?.mandatory,
        isFalse,
      );
    });

    test('a rate-limited response is unavailable, not "up to date"', () async {
      final result = await _check(
        _release(body: '<!-- kiu-update: build=19 -->'),
        status: HttpStatus.forbidden,
      );
      expect(result.answered, isFalse);
      expect(result.update, isNull);
    });

    test('a malformed payload is unavailable rather than throwing', () async {
      expect((await _check('not a release object')).answered, isFalse);
    });

    test(
      'an unreachable endpoint is unavailable rather than throwing',
      () async {
        // Port 1 is reserved and refuses immediately.
        final checker = GitHubUpdateChecker(endpoint: 'http://127.0.0.1:1/');
        final result = await checker.check(installedBuild: 18, abi: 2);
        checker.close();
        expect(result.answered, isFalse);
      },
    );

    test('a release with no marker is a real "up to date" answer', () async {
      final result = await _check(_release(body: 'Plain notes, no marker.'));
      expect(result.answered, isTrue);
      expect(result.update, isNull);
    });
  });

  group('isGitHubReleaseAsset', () {
    test('accepts GitHub release hosts over https only', () {
      expect(
        isGitHubReleaseAsset(Uri.parse('https://github.com/a/b.apk')),
        isTrue,
      );
      expect(
        isGitHubReleaseAsset(
          Uri.parse('https://objects.githubusercontent.com/a.apk'),
        ),
        isTrue,
      );
      expect(
        isGitHubReleaseAsset(Uri.parse('http://github.com/a/b.apk')),
        isFalse,
      );
      expect(
        isGitHubReleaseAsset(Uri.parse('https://github.com.evil.com/a.apk')),
        isFalse,
      );
    });
  });
}
