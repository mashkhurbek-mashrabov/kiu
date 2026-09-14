import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import 'update_service.dart';

enum UpdateDownloadStage { idle, downloading, installing, failed }

typedef UpdateDownloadProgress = ({
  UpdateDownloadStage stage,
  int received,
  int total,
});

abstract interface class ApkInstaller {
  /// The directory the APK may be written to.
  ///
  /// Must be Android's `cacheDir`: `Directory.systemTemp` resolves to `/tmp`,
  /// which does not exist on Android, so writing there throws and every real
  /// download fails with an unhelpful error. It is also the directory the
  /// FileProvider's `<cache-path>` exposes, so the installer can read the
  /// result.
  Future<String?> cacheDirectory();

  Future<bool> canInstallPackages();
  Future<void> openInstallPermissionSettings();
  Future<void> installApk(String path);
}

/// Streams a release APK to the cache directory and hands it to the system
/// installer.
///
/// Progress is published through a [ValueNotifier] rather than
/// `notifyListeners()` on the controller: rebuilding `KiuApp` tears down and
/// recreates the WebView, which is exactly what the project forbids for
/// periodic state. One `ValueListenableBuilder` renders the bar.
class UpdateDownloader {
  UpdateDownloader({
    required ApkInstaller installer,
    HttpClient? client,
    Directory? cacheDirectory,
    bool Function(Uri)? isAllowedHost,
  }) : _installer = installer,
       _client = client ?? HttpClient(),
       _cacheDirectory = cacheDirectory,
       _isAllowedHost = isAllowedHost ?? isGitHubReleaseAsset {
    // Without these a stalled socket hangs a *mandatory* gate forever, with no
    // retry and no way into the app.
    _client.connectionTimeout = const Duration(seconds: 20);
  }

  static const _responseTimeout = Duration(seconds: 60);

  /// Applies between chunks, not to the whole transfer: a large APK on a slow
  /// connection is legitimate and must not be cut off, but a connection that
  /// stops delivering has to fail so Retry is offered.
  static const _idleTimeout = Duration(seconds: 60);

  final ApkInstaller _installer;
  final HttpClient _client;
  final Directory? _cacheDirectory;

  /// Which hosts may serve an APK. Defaults to the GitHub allowlist and is
  /// only overridden by tests, which serve the bytes from a loopback socket.
  /// Production never passes this — the default is the security boundary.
  final bool Function(Uri) _isAllowedHost;

  final ValueNotifier<UpdateDownloadProgress> progress = ValueNotifier((
    stage: UpdateDownloadStage.idle,
    received: 0,
    total: 0,
  ));

  bool _inFlight = false;

  /// Downloads [update] and launches the installer. Returns false when the
  /// user still has to act — granting "install unknown apps", or retrying a
  /// failed download.
  Future<bool> download(AppUpdate update) async {
    if (_inFlight) return false;
    _inFlight = true;
    try {
      return await _download(update);
    } on Object {
      progress.value = (
        stage: UpdateDownloadStage.failed,
        received: 0,
        total: update.apkSize,
      );
      return false;
    } finally {
      _inFlight = false;
    }
  }

  Future<bool> _download(AppUpdate update) async {
    final uri = Uri.parse(update.apkUrl);
    // Re-checked here and not only at parse time: this is the call that turns
    // a remote string into executable code on the device.
    if (!_isAllowedHost(uri)) {
      progress.value = (
        stage: UpdateDownloadStage.failed,
        received: 0,
        total: update.apkSize,
      );
      return false;
    }

    if (!await _installer.canInstallPackages()) {
      await _installer.openInstallPermissionSettings();
      progress.value = (
        stage: UpdateDownloadStage.idle,
        received: 0,
        total: update.apkSize,
      );
      return false;
    }

    progress.value = (
      stage: UpdateDownloadStage.downloading,
      received: 0,
      total: update.apkSize,
    );

    // Asked of the platform rather than defaulted to Directory.systemTemp,
    // which is /tmp -- a path that does not exist on Android.
    final resolved =
        _cacheDirectory ??
        switch (await _installer.cacheDirectory()) {
          final path? when path.isNotEmpty => Directory(path),
          _ => null,
        };
    if (resolved == null) {
      throw const FileSystemException('no cache directory for the update');
    }
    final file = File('${resolved.path}/update.apk');
    // A partial file from an interrupted run would otherwise be appended to,
    // producing an APK the installer rejects with an opaque parse error.
    if (file.existsSync()) await file.delete();

    final request = await _client.getUrl(uri);
    final response = await request.close().timeout(_responseTimeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('${response.statusCode}', uri: uri);
    }

    final sink = file.openWrite();
    var received = 0;
    var lastPublished = 0;
    final since = Stopwatch()..start();
    try {
      // Piped rather than `await for` + `sink.add`: awaiting each chunk paused
      // the socket read while that chunk was written to disk, so the network
      // and the flash never overlapped. This was the download being slow on a
      // real phone -- the same file fetched by curl on the same network is an
      // order of magnitude faster.
      await response
          .timeout(_idleTimeout)
          .map((chunk) {
            received += chunk.length;
            // Publishing every ~8 KB chunk meant thousands of notifier writes
            // per download, each rebuilding a Column with text layout. Coarsen
            // to ~100 ms or ~1%, whichever is slower to arrive.
            final step = update.apkSize > 0 ? update.apkSize ~/ 100 : 0;
            if (since.elapsedMilliseconds >= 100 ||
                received - lastPublished >= step) {
              since.reset();
              lastPublished = received;
              progress.value = (
                stage: UpdateDownloadStage.downloading,
                received: received,
                total: update.apkSize,
              );
            }
            return chunk;
          })
          .pipe(sink);
    } on Object {
      // A partial file must never be left for the installer to choke on, and
      // pipe() has already closed the sink by the time this runs.
      if (file.existsSync()) await file.delete();
      rethrow;
    }
    // The throttle can swallow the last chunk; the bar must land on 100%.
    progress.value = (
      stage: UpdateDownloadStage.downloading,
      received: received,
      total: update.apkSize,
    );

    // Size is the one integrity check available without shipping a hash.
    // Android verifies the signature at install, which is the check that
    // actually gates what runs; this only catches a truncated transfer before
    // it becomes a confusing "app not installed" dialog.
    if (update.apkSize > 0 && received != update.apkSize) {
      await file.delete();
      throw const HttpException('truncated download');
    }

    progress.value = (
      stage: UpdateDownloadStage.installing,
      received: received,
      total: update.apkSize,
    );
    await _installer.installApk(file.path);
    return true;
  }

  void reset() =>
      progress.value = (stage: UpdateDownloadStage.idle, received: 0, total: 0);

  void dispose() {
    progress.dispose();
    _client.close(force: true);
  }
}
