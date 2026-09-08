import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../domain/app_settings.dart';
import '../domain/lesson.dart';
import 'time_zone_service.dart';

const lessonWidgetProvider = 'KiuLessonWidgetProvider';
const lessonWidgetQualifiedProvider =
    'com.mashkhurbek.kiu.KiuLessonWidgetProvider';
const lessonWidgetSuccessMessageDuration = Duration(seconds: 3);

abstract interface class LessonWidgetGateway {
  Future<void> publish(
    List<Lesson> lessons,
    AppSettings settings, {
    DateTime? lastSuccessfulSync,
    bool showSuccessStatus = false,
  });
  Future<void> publishStatus(ScheduleSyncStatus status, AppSettings settings);
}

class HomeLessonWidgetGateway implements LessonWidgetGateway {
  HomeLessonWidgetGateway({TimeZoneService? timeZones})
    : _timeZones = timeZones ?? TimeZoneService();

  final TimeZoneService _timeZones;

  @override
  Future<void> publish(
    List<Lesson> lessons,
    AppSettings settings, {
    DateTime? lastSuccessfulSync,
    bool showSuccessStatus = false,
  }) async {
    final payload = buildLessonWidgetPayload(lessons, settings, _timeZones);
    final now = DateTime.now();
    final statusVisibleUntil = showSuccessStatus
        ? lessonWidgetSuccessStatusExpiry(now)
        : await _readStatusVisibleUntil();
    await HomeWidget.saveWidgetData<String>('lessons', jsonEncode(payload));
    await HomeWidget.saveWidgetData<String>(
      'syncLabel',
      _label(settings.localeTag, 'sync'),
    );
    if (showSuccessStatus) {
      await HomeWidget.saveWidgetData<String>(
        'widgetStatus',
        _label(settings.localeTag, 'updated'),
      );
      await HomeWidget.saveWidgetData<String>(
        'widgetStatusVisibleUntil',
        statusVisibleUntil!.millisecondsSinceEpoch.toString(),
      );
    }
    await HomeWidget.saveWidgetData<String>(
      'widgetLastSync',
      buildLessonWidgetLastSyncLabel(lastSuccessfulSync, settings, _timeZones),
    );
    await HomeWidget.saveWidgetData<String>(
      'emptyLabel',
      _label(settings.localeTag, 'empty'),
    );
    await _update();
    await HomeWidget.cancelScheduledWidgetUpdates(
      qualifiedAndroidName: lessonWidgetQualifiedProvider,
    );
    await HomeWidget.scheduleWidgetUpdates(
      buildLessonWidgetUpdateTimes(
        payload,
        now,
        statusVisibleUntil: statusVisibleUntil,
      ),
      qualifiedAndroidName: lessonWidgetQualifiedProvider,
    );
  }

  @override
  Future<void> publishStatus(
    ScheduleSyncStatus status,
    AppSettings settings,
  ) async {
    final key = switch (status) {
      ScheduleSyncStatus.syncing => 'syncing',
      ScheduleSyncStatus.signInRequired => 'signIn',
      ScheduleSyncStatus.failed => 'failed',
      _ => 'updated',
    };
    await HomeWidget.saveWidgetData<String>(
      'widgetStatus',
      _label(settings.localeTag, key),
    );
    await HomeWidget.saveWidgetData<String>('widgetStatusVisibleUntil', '0');
    await HomeWidget.saveWidgetData<String>(
      'syncLabel',
      _label(settings.localeTag, 'sync'),
    );
    await HomeWidget.saveWidgetData<String>(
      'emptyLabel',
      _label(settings.localeTag, 'empty'),
    );
    await _update();
  }

  Future<void> _update() => HomeWidget.updateWidget(
    qualifiedAndroidName: lessonWidgetQualifiedProvider,
  );

  Future<DateTime?> _readStatusVisibleUntil() async {
    final raw = await HomeWidget.getWidgetData<String>(
      'widgetStatusVisibleUntil',
    );
    final milliseconds = int.tryParse(raw ?? '');
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}

DateTime lessonWidgetSuccessStatusExpiry(DateTime now) =>
    now.add(lessonWidgetSuccessMessageDuration);

List<DateTime> buildLessonWidgetUpdateTimes(
  List<Map<String, Object?>> payload,
  DateTime now, {
  DateTime? statusVisibleUntil,
}) {
  final times = payload
      .map((item) => DateTime.fromMillisecondsSinceEpoch(item['start']! as int))
      .where((value) => value.isAfter(now))
      .toList();
  if (statusVisibleUntil?.isAfter(now) ?? false) {
    times.add(statusVisibleUntil!);
  }
  times.sort();
  return times;
}

String buildLessonWidgetLastSyncLabel(
  DateTime? lastSuccessfulSync,
  AppSettings settings,
  TimeZoneService timeZones,
) {
  final value = lastSuccessfulSync == null
      ? _label(settings.localeTag, 'never')
      : timeZones.display(lastSuccessfulSync, settings.timeZoneId);
  return '${_label(settings.localeTag, 'lastSync')}: $value';
}

List<Map<String, Object?>> buildLessonWidgetPayload(
  List<Lesson> lessons,
  AppSettings settings,
  TimeZoneService timeZones,
) {
  final payload = <Map<String, Object?>>[];
  for (final lesson in lessons) {
    try {
      final start = timeZones.parseWebsiteTime(lesson.websiteStart);
      payload.add({
        'title': lesson.title,
        'start': start.millisecondsSinceEpoch,
        'displayStart': timeZones.display(start, settings.timeZoneId),
        'meetingUrl': lesson.meetingUrl,
      });
    } on FormatException {
      continue;
    }
  }
  payload.sort((a, b) => (a['start']! as int).compareTo(b['start']! as int));
  return payload;
}

String _label(String locale, String key) => switch ((locale, key)) {
  ('ru', 'sync') => 'Обновить',
  ('ru', 'syncing') => 'Синхронизация…',
  ('ru', 'signIn') => 'Откройте KIU и войдите',
  ('ru', 'failed') => 'Ошибка синхронизации',
  ('ru', 'empty') => 'Нет запланированных уроков',
  ('ru', 'lastSync') => 'Последняя синхронизация',
  ('ru', 'never') => 'Никогда',
  ('ru', _) => 'Обновлено',
  ('en', 'sync') => 'Sync',
  ('en', 'syncing') => 'Synchronizing…',
  ('en', 'signIn') => 'Open KIU and sign in',
  ('en', 'failed') => 'Synchronization failed',
  ('en', 'empty') => 'No scheduled lessons',
  ('en', 'lastSync') => 'Last sync',
  ('en', 'never') => 'Never',
  ('en', _) => 'Updated',
  ('uz', 'sync') => 'Yangilash',
  ('uz', 'syncing') => 'Sinxronlanmoqda…',
  ('uz', 'signIn') => 'KIU ilovasini ochib tizimga kiring',
  ('uz', 'failed') => 'Sinxronlash xatosi',
  ('uz', 'empty') => 'Rejalashtirilgan darslar yo‘q',
  ('uz', 'lastSync') => 'Oxirgi sinxronlash',
  ('uz', 'never') => 'Hali yo‘q',
  ('uz', _) => 'Yangilandi',
  (_, 'sync') => 'Янгилаш',
  (_, 'syncing') => 'Синхронланмоқда…',
  (_, 'signIn') => 'KIU иловасини очиб тизимга киринг',
  (_, 'failed') => 'Синхронлаш хатоси',
  (_, 'empty') => 'Режалаштирилган дарслар йўқ',
  (_, 'lastSync') => 'Охирги синхронлаш',
  (_, 'never') => 'Ҳали йўқ',
  _ => 'Янгиланди',
};
