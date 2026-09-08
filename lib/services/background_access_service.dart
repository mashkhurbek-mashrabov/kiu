import 'package:flutter/services.dart';

abstract interface class BackgroundAccessGateway {
  Future<bool> isBatteryOptimizationDisabled();
  Future<void> openBatteryOptimizationSettings();
}

class AndroidBackgroundAccessGateway implements BackgroundAccessGateway {
  static const _channel = MethodChannel('com.mashkhurbek.kiu/platform');

  @override
  Future<bool> isBatteryOptimizationDisabled() async =>
      await _channel.invokeMethod<bool>('isBatteryOptimizationDisabled') ??
      false;

  @override
  Future<void> openBatteryOptimizationSettings() =>
      _channel.invokeMethod<void>('openBatteryOptimizationSettings');
}
