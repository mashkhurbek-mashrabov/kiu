import 'package:flutter/services.dart';

class AppVersion {
  const AppVersion({required this.name, required this.code});

  final String name;
  final int code;

  String label(String prefix) => '$prefix $name ($code)';
}

abstract interface class AppVersionProvider {
  Future<AppVersion> read();
}

class AndroidAppVersionProvider implements AppVersionProvider {
  static const _channel = MethodChannel('com.mashkhurbek.kiu/platform');

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
    return AppVersion(name: name, code: code);
  }
}
