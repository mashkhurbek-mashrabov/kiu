import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

abstract interface class NotificationGateway {
  Future<void> initialize({void Function(String? payload)? onTap});
  Future<bool> requestNotificationPermission();
  Future<bool> requestExactAlarmPermission();
  Future<bool> canScheduleExactly();
  Future<NotificationSound?> selectSound({
    String? currentSound,
    bool ringtone = false,
  });
  Future<void> schedule({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required String payload,
    required bool exact,
    required int reminderOffsetMinutes,
    String? soundUri,
  });
  Future<void> cancel(int id);
}

class NotificationSound {
  const NotificationSound({required this.uri, required this.name});

  final String uri;
  final String name;
}

class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const _platform = MethodChannel('com.mashkhurbek.kiu/platform');

  @override
  Future<void> initialize({void Function(String? payload)? onTap}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onTap?.call(response.payload),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestNotificationPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  @override
  Future<bool> requestExactAlarmPermission() async =>
      await _android?.requestExactAlarmsPermission() ?? false;

  @override
  Future<bool> canScheduleExactly() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  @override
  Future<NotificationSound?> selectSound({
    String? currentSound,
    bool ringtone = false,
  }) async {
    try {
      final sound = await _platform.invokeMapMethod<String, String>(
        'selectNotificationSound',
        {
          'currentSound': currentSound,
          'type': ringtone ? 'ringtone' : 'notification',
        },
      );
      final uri = sound?['uri'];
      final name = sound?['name'];
      return uri == null || name == null
          ? null
          : NotificationSound(uri: uri, name: name);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> schedule({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required String payload,
    required bool exact,
    required int reminderOffsetMinutes,
    String? soundUri,
  }) {
    final sound = soundUri == null
        ? null
        : UriAndroidNotificationSound(soundUri);
    return _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          reminderNotificationChannelId(reminderOffsetMinutes, soundUri),
          'KIU lesson reminders',
          channelDescription: 'Upcoming online lesson reminders',
          icon: 'ic_notification',
          importance: Importance.high,
          priority: Priority.high,
          sound: sound,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}

String reminderNotificationChannelId(int offsetMinutes, String? soundUri) =>
    'kiu_lesson_reminder_${offsetMinutes}_${_channelSuffix(soundUri ?? 'default')}';

String _channelSuffix(String value) {
  var hash = 0x811c9dc5;
  for (final byte in value.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(36);
}
