import 'package:flutter/services.dart';

abstract interface class BackgroundAccessGateway {
  Future<bool> isBatteryOptimizationDisabled();
  Future<void> openBatteryOptimizationSettings();
  Future<bool> canUseFullScreenIntent();
  Future<void> openFullScreenIntentSettings();
  Future<bool> canDrawOverlays();
  Future<void> openOverlaySettings();
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

  @override
  Future<bool> canUseFullScreenIntent() async {
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ??
          true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> openFullScreenIntentSettings() =>
      _channel.invokeMethod<void>('openFullScreenIntentSettings');

  @override
  Future<bool> canDrawOverlays() async {
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> openOverlaySettings() =>
      _channel.invokeMethod<void>('openOverlaySettings');
}
