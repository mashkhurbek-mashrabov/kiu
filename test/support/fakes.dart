import 'package:flutter/services.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/services/background_access_service.dart';
import 'package:kiu/services/notification_service.dart';
import 'package:kiu/services/lesson_widget_service.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/domain/app_settings.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:timezone/timezone.dart' as tz;

class FakeNotificationGateway implements NotificationGateway {
  bool permission = true;
  bool exact = true;
  NotificationSound? selectedSound;
  final Map<int, ScheduledCall> scheduled = {};
  final List<int> cancelled = [];
  final Set<int> failScheduleIds = {};

  @override
  Future<bool> canScheduleExactly() async => exact;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> initialize({void Function(String? payload)? onTap}) async {}

  @override
  Future<bool> requestExactAlarmPermission() async => exact;

  @override
  Future<bool> requestNotificationPermission() async => permission;

  bool? lastSelectSoundRingtone;

  @override
  Future<NotificationSound?> selectSound({
    String? currentSound,
    bool ringtone = false,
  }) async {
    lastSelectSoundRingtone = ringtone;
    return selectedSound;
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
  }) async {
    if (failScheduleIds.contains(id)) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    scheduled[id] = ScheduledCall(
      when: when,
      title: title,
      body: body,
      payload: payload,
      exact: exact,
      reminderOffsetMinutes: reminderOffsetMinutes,
      soundUri: soundUri,
    );
  }
}

class ScheduledCall {
  const ScheduledCall({
    required this.when,
    required this.title,
    required this.body,
    required this.payload,
    required this.exact,
    required this.reminderOffsetMinutes,
    required this.soundUri,
  });

  final tz.TZDateTime when;
  final String title;
  final String body;
  final String payload;
  final bool exact;
  final int reminderOffsetMinutes;
  final String? soundUri;
}

class FakeBackgroundScheduler implements BackgroundScheduler {
  bool enabled = false;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

class FakeBackgroundAccessGateway implements BackgroundAccessGateway {
  bool batteryOptimizationDisabled = true;
  bool fullScreenIntentAllowed = true;
  bool overlaysAllowed = true;
  int overlaySettingsOpened = 0;

  @override
  Future<bool> isBatteryOptimizationDisabled() async =>
      batteryOptimizationDisabled;

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<bool> canUseFullScreenIntent() async => fullScreenIntentAllowed;

  @override
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<bool> canDrawOverlays() async => overlaysAllowed;

  @override
  Future<void> openOverlaySettings() async => overlaySettingsOpened++;
}

class EmptyCookieProvider implements CookieProvider {
  @override
  Future<Map<String, String>> cookiesFor(Uri uri) async => const {};
}

class CapturingScheduleFetcher extends ScheduleFetcher {
  CapturingScheduleFetcher(this.lessons)
    : super(cookieProvider: EmptyCookieProvider());

  final List<Lesson> lessons;
  String? userAgent;
  String? localeTag;

  @override
  Future<List<Lesson>> fetch({
    String? userAgent,
    String localeTag = 'uz_Cyrl',
  }) async {
    this.userAgent = userAgent;
    this.localeTag = localeTag;
    return lessons;
  }
}

class FakeLessonWidgetGateway implements LessonWidgetGateway {
  List<Lesson>? lessons;
  AppSettings? settings;
  ScheduleSyncStatus? status;
  final List<ScheduleSyncStatus> statusHistory = [];
  DateTime? lastSuccessfulSync;

  @override
  Future<void> publish(
    List<Lesson> value,
    AppSettings appSettings, {
    DateTime? lastSuccessfulSync,
  }) async {
    lessons = value;
    settings = appSettings;
    this.lastSuccessfulSync = lastSuccessfulSync;
    status = null;
  }

  @override
  Future<void> publishStatus(
    ScheduleSyncStatus value,
    AppSettings appSettings,
  ) async {
    status = value;
    statusHistory.add(value);
    settings = appSettings;
  }
}
