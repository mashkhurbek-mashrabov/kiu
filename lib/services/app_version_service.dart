import 'dart:async';

import 'package:flutter/services.dart';

import 'update_downloader.dart';

/// The shared platform channel. Every native capability the shell needs hangs
/// off this one channel — alarms must be armable from the WorkManager
/// background isolate, so a second channel bound to `MainActivity` would not
/// exist when it is needed.
const MethodChannel platformChannel = MethodChannel(
  'com.mashkhurbek.kiu/platform',
);

class AppVersion {
  const AppVersion({required this.name, required this.code, this.abi = 0});

  final String name;

  /// The pubspec build number. `MainActivity.getAppVersion` already strips the
  /// `1000 * abi` prefix that `--split-per-abi` adds, so this is 18 for
  /// `1.4.0+18` on every ABI and compares directly against a release marker.
  final int code;

  /// The ABI prefix that was stripped from the raw version code: 2 for
  /// arm64-v8a, 4 for x86_64, 0 for a build with no split. The updater needs it
  /// to pick the matching asset, and it is unrecoverable from [code] alone.
  final int abi;

  String label(String prefix) => '$prefix $name ($code)';
}

abstract interface class AppVersionProvider {
  Future<AppVersion> read();
}

class AndroidAppVersionProvider implements AppVersionProvider {
  static const _channel = platformChannel;

  @override
  Future<AppVersion> read() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getAppVersion',
    );
    final name = result?['versionName'];
    final code = result?['versionCode'];
    if (name is! String || name.isEmpty || code is! int) {
      throw PlatformException(
        code: 'invalid_app_version',
        message: 'Android returned invalid package metadata.',
      );
    }
    final abi = result?['abi'];
    return AppVersion(name: name, code: code, abi: abi is int ? abi : 0);
  }
}

/// Drives the system package installer over the shared [platformChannel].
class AndroidApkInstaller implements ApkInstaller {
  AndroidApkInstaller() {
    // The native side calls back here once the install session reaches a
    // terminal status -- most often because the user declined Android's
    // confirmation prompt, which is the case that used to strand the update
    // gate on "installing" with no way forward.
    platformChannel.setMethodCallHandler((call) async {
      if (call.method != 'installResult') return null;
      final arguments = call.arguments;
      final success = arguments is Map && arguments['success'] == true;
      if (!_results.isClosed) _results.add(success);
      return null;
    });
  }

  /// Broadcast so a listener that arrives late does not throw, and so the
  /// downloader can subscribe once per install attempt.
  final StreamController<bool> _results = StreamController<bool>.broadcast();

  @override
  Stream<bool> get installResults => _results.stream;

  void dispose() => _results.close();

  @override
  Future<String?> cacheDirectory() =>
      platformChannel.invokeMethod<String>('getUpdateCacheDir');

  @override
  Future<bool> canInstallPackages() async =>
      await platformChannel.invokeMethod<bool>('canInstallPackages') ?? false;

  @override
  Future<void> openInstallPermissionSettings() =>
      platformChannel.invokeMethod<void>('openInstallPermissionSettings');

  @override
  Future<void> installApk(String path) =>
      platformChannel.invokeMethod<void>('installApk', {'path': path});
}
