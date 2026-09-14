import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';

/// A release newer than the installed build, ready to download.
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.buildNumber,
    required this.mandatory,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  final String versionName;
  final int buildNumber;

  /// Whether the app must be blocked until this is installed. Comes from the
  /// release marker, defaulting to true, and is forced true when the release
  /// declares a `minBuild` above the installed build.
  final bool mandatory;
  final String notes;
  final String apkUrl;

  /// Declared asset size in bytes, used both to show progress and to reject a
  /// truncated download before it reaches the installer.
  ///
  /// [apkUrl] must be the stable `browser_download_url`, never a URL the
  /// download resolved to: GitHub redirects that to a signed, time-limited
  /// asset URL, which would be dead by the time a persisted copy is read back.
  final int apkSize;

  Map<String, dynamic> toJson() => {
    'versionName': versionName,
    'buildNumber': buildNumber,
    'mandatory': mandatory,
    'notes': notes,
    'apkUrl': apkUrl,
    'apkSize': apkSize,
  };

  /// Rebuilds a stored update, or returns null for anything unusable.
  ///
  /// Tolerant by design: this is read on the launch path, where a throw is an
  /// unrecoverable crash the user cannot clear without reinstalling. Same
  /// discipline as `Lesson.tryFromJson`.
  static AppUpdate? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final versionName = value['versionName'];
    final buildNumber = value['buildNumber'];
    final notes = value['notes'];
    final apkUrl = value['apkUrl'];
    final apkSize = value['apkSize'];
    if (versionName is! String || versionName.isEmpty) return null;
    if (buildNumber is! int || buildNumber <= 0) return null;
    if (apkUrl is! String || apkUrl.isEmpty) return null;
    if (apkSize is! int || apkSize < 0) return null;
    final uri = Uri.tryParse(apkUrl);
    // Re-checked on the way out of storage, not just on the way in: the
    // download is installed as code, and prefs are not a trust boundary.
    if (uri == null || !isGitHubReleaseAsset(uri)) return null;
    return AppUpdate(
      versionName: versionName,
      buildNumber: buildNumber,
      // Absent or malformed means mandatory, matching the marker default.
      mandatory: value['mandatory'] != false,
      notes: notes is String ? notes : '',
      apkUrl: apkUrl,
      apkSize: apkSize,
    );
  }
}

/// The outcome of one check.
///
/// "Up to date" and "could not reach GitHub" are deliberately distinct: the
/// first is an answer worth recording against the throttle, the second must not
/// silence the updater for the next six hours just because the user happened to
/// open the app on a train.
class UpdateCheckResult {
  const UpdateCheckResult._(this.update, this.answered);

  /// GitHub replied. [update] is null when the installed build is current.
  const UpdateCheckResult.answered(AppUpdate? update) : this._(update, true);

  /// No usable reply — offline, timed out, rate limited, or malformed.
  const UpdateCheckResult.unavailable() : this._(null, false);

  final AppUpdate? update;
  final bool answered;
}

abstract interface class UpdateChecker {
  /// Never throws: the caller can gate the whole app on this result, so a
  /// failure has to arrive as [UpdateCheckResult.unavailable] rather than an
  /// exception that could propagate into a launch crash.
  Future<UpdateCheckResult> check({
    required int installedBuild,
    required int abi,
  });
}

/// Parses the trailing marker that carries what the GitHub release body cannot
/// express on its own:
///
/// ```
/// <!-- kiu-update: build=19 mandatory=true minBuild=15 -->
/// ```
///
/// Deliberately tolerant. A missing or unparsable marker yields null, which
/// means *no update offered* rather than a lockout — a typo in a release body
/// must never brick every install. Only `build` is required.
({int build, bool mandatory, int? minBuild})? parseUpdateMarker(String body) {
  final match = RegExp(
    r'<!--\s*kiu-update:(.*?)-->',
    dotAll: true,
  ).firstMatch(body);
  if (match == null) return null;
  final fields = <String, String>{};
  for (final pair in match.group(1)!.trim().split(RegExp(r'\s+'))) {
    final index = pair.indexOf('=');
    if (index > 0) {
      fields[pair.substring(0, index)] = pair.substring(index + 1);
    }
  }
  final build = int.tryParse(fields['build'] ?? '');
  if (build == null || build <= 0) return null;
  return (
    build: build,
    // Absent or malformed means mandatory: the safe default for this app is to
    // push the user forward, and an optional release must say so explicitly.
    mandatory: fields['mandatory']?.toLowerCase() != 'false',
    minBuild: int.tryParse(fields['minBuild'] ?? ''),
  );
}

/// Maps Flutter's split-APK ABI prefix onto the asset suffix used by
/// `flutter build apk --split-per-abi`. See [abiFromVersionCode].
const Map<int, String> abiNames = {2: 'arm64-v8a', 4: 'x86_64'};

/// Recovers which ABI's APK is installed from its raw version code.
///
/// `--split-per-abi` builds each APK with `1000 * abi + buildNumber`, so the
/// arm64 APK of `1.4.0+18` reports 2018 and the x86_64 one 4018. Note that
/// `MainActivity.getAppVersion` already strips the offset before the Dart side
/// sees it, so this is only for a caller holding the raw value.
int abiFromVersionCode(int versionCode) => versionCode ~/ 1000;

class GitHubUpdateChecker implements UpdateChecker {
  GitHubUpdateChecker({HttpClient? client, String? endpoint})
    : _client = client ?? HttpClient(),
      _endpoint = endpoint ?? latestReleaseApiUrl;

  final HttpClient _client;
  final String _endpoint;

  @override
  Future<UpdateCheckResult> check({
    required int installedBuild,
    required int abi,
  }) async {
    try {
      return await _check(installedBuild: installedBuild, abi: abi);
    } on Object {
      // A socket error, a timeout and a malformed payload all leave the app
      // exactly as it was rather than propagating into the gate.
      return const UpdateCheckResult.unavailable();
    }
  }

  Future<UpdateCheckResult> _check({
    required int installedBuild,
    required int abi,
  }) async {
    final request = await _client.getUrl(Uri.parse(_endpoint));
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      // 403/429 is the unauthenticated rate limit (60/hour per IP). Drain the
      // body so the connection can be reused rather than left dangling.
      await response.drain<void>();
      return const UpdateCheckResult.unavailable();
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const UpdateCheckResult.unavailable();
    }

    final marker = parseUpdateMarker(
      decoded['body'] is String ? decoded['body'] as String : '',
    );
    // A release with no marker, or one no newer than what is installed, is a
    // genuine "you are current" — the request succeeded, so it counts against
    // the throttle.
    if (marker == null) return const UpdateCheckResult.answered(null);
    final minBuild = marker.minBuild;
    if (marker.build <= installedBuild) {
      return const UpdateCheckResult.answered(null);
    }

    final asset = _selectAsset(decoded['assets'], abi);
    if (asset == null) return const UpdateCheckResult.answered(null);

    return UpdateCheckResult.answered(
      AppUpdate(
        versionName: _versionName(decoded) ?? '${marker.build}',
        buildNumber: marker.build,
        // A minBuild above what is installed forces the update even when the
        // release is otherwise optional, so a known-broken build can be
        // retired without editing the releases published after it.
        mandatory:
            marker.mandatory || (minBuild != null && installedBuild < minBuild),
        notes: _stripMarker(decoded['body']),
        apkUrl: asset.url,
        apkSize: asset.size,
      ),
    );
  }

  /// Picks the asset built for the running ABI. Returns null when the release
  /// has no APK for it — offering one that cannot install is worse than
  /// staying quiet, especially behind a mandatory gate.
  ({String url, int size})? _selectAsset(Object? assets, int abi) {
    final suffix = abiNames[abi];
    if (assets is! List || suffix == null) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      final size = asset['size'];
      if (name is! String || url is! String || size is! int) continue;
      if (!name.endsWith('-$suffix.apk')) continue;
      final uri = Uri.tryParse(url);
      // Host-allowlisted for the same reason cookies are: the payload comes
      // from a remote document, and this one ends up installed as code.
      if (uri == null || !isGitHubReleaseAsset(uri)) continue;
      return (url: url, size: size);
    }
    return null;
  }

  String? _versionName(Map<String, dynamic> release) {
    for (final key in ['tag_name', 'name']) {
      final value = release[key];
      if (value is String && value.isNotEmpty) {
        return value.startsWith('v') ? value.substring(1) : value;
      }
    }
    return null;
  }

  String _stripMarker(Object? body) => body is String
      ? body
            .replaceAll(RegExp(r'<!--\s*kiu-update:.*?-->', dotAll: true), '')
            .trim()
      : '';

  void close() => _client.close(force: true);
}
