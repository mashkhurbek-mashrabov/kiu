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
       _isAllowedHost = isAllowedHost ?? isGitHubReleaseAsset;

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
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('${response.statusCode}', uri: uri);
    }

    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        progress.value = (
          stage: UpdateDownloadStage.downloading,
          received: received,
          total: update.apkSize,
        );
      }
    } finally {
      await sink.close();
    }

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
