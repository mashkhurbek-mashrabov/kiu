import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/app_settings.dart';
import '../domain/lesson.dart';
import 'reminder_reconciler.dart' show stableNotificationId;
import 'time_zone_service.dart';

const lessonWidgetProvider = 'KiuLessonWidgetProvider';
const lessonWidgetQualifiedProvider =
    'com.mashkhurbek.kiu.KiuLessonWidgetProvider';

abstract interface class LessonWidgetGateway {
  Future<void> publish(
    List<Lesson> lessons,
    AppSettings settings, {
    DateTime? lastSuccessfulSync,
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
  }) async {
    final payload = buildLessonWidgetPayload(lessons, settings, _timeZones);
    final now = DateTime.now();
    final callPayload = buildLessonCallPayload(
      lessons,
      settings,
      _timeZones,
      now: now,
    );
    await _write({
      'lessons': jsonEncode(payload),
      'calls': jsonEncode(callPayload),
      'callRingSeconds': '${settings.callRingSeconds}',
      'callRingtoneUri': settings.callRingtoneUri ?? '',
      'callIncomingLabel': _label(settings.localeTag, 'callIncoming'),
      'callAnswerLabel': _label(settings.localeTag, 'callAnswer'),
      'callDeclineLabel': _label(settings.localeTag, 'callDecline'),
      'callToggleOnLabel': _label(settings.localeTag, 'callToggleOn'),
      'callToggleOffLabel': _label(settings.localeTag, 'callToggleOff'),
      'callJoinLabel': _label(settings.localeTag, 'callJoin'),
      'widgetStatus': '',
      'widgetIsSyncing': 'false',
      'widgetLastSync': buildLessonWidgetLastSyncLabel(
        lastSuccessfulSync,
        settings,
        _timeZones,
      ),
      ..._sharedLabels(settings),
    });
    await _update();
    await HomeWidget.cancelScheduledWidgetUpdates(
      qualifiedAndroidName: lessonWidgetQualifiedProvider,
    );
    await HomeWidget.scheduleWidgetUpdates(
      buildLessonWidgetUpdateTimes(payload, now),
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
      _ => '',
    };
    await _write({
      'widgetStatus': _label(settings.localeTag, key),
      'widgetIsSyncing': status == ScheduleSyncStatus.syncing
          ? 'true'
          : 'false',
      ..._sharedLabels(settings),
    });
    await _update();
  }

  /// Keys both [publish] and [publishStatus] must keep current. Shared so the
  /// two cannot drift apart when a label is added.
  Map<String, String> _sharedLabels(AppSettings settings) => {
    'syncLabel': _label(settings.localeTag, 'sync'),
    'widgetSubtitle': _label(settings.localeTag, 'subtitle'),
    'emptyLabel': _label(settings.localeTag, 'empty'),
    'widgetDark': widgetDarkFlag(settings),
  };

  /// One platform-channel round trip per key is unavoidable with `home_widget`,
  /// but issuing them together instead of awaiting each in turn keeps a publish
  /// off the critical path of whatever the user is doing.
  Future<void> _write(Map<String, String> values) => Future.wait([
    for (final entry in values.entries)
      HomeWidget.saveWidgetData<String>(entry.key, entry.value),
  ]);

  Future<void> _update() => HomeWidget.updateWidget(
    qualifiedAndroidName: lessonWidgetQualifiedProvider,
  );
}

/// RemoteViews cannot read the app's ThemeData and `values-night` would follow
/// the OS instead of the in-app choice, so the resolved mode travels to Kotlin
/// as data and the provider tints the views itself.
String widgetDarkFlag(AppSettings settings) =>
    resolveDark(settings.themeMode) ? 'true' : 'false';

/// Each entry becomes an AlarmManager wake-up, so a busy term would otherwise
/// arm one alarm per future lesson (60+ measured). Only the soonest handful
/// matter -- the next sync re-arms the rest well before they arrive.
const _maxScheduledWidgetUpdates = 16;

List<DateTime> buildLessonWidgetUpdateTimes(
  List<Map<String, Object?>> payload,
  DateTime now,
) {
  final times =
      payload
          .map(
            (item) =>
                DateTime.fromMillisecondsSinceEpoch(item['start']! as int),
          )
          .where((value) => value.isAfter(now))
          .toList()
        ..sort();
  return times.take(_maxScheduledWidgetUpdates).toList();
}

String buildLessonWidgetLastSyncLabel(
  DateTime? lastSuccessfulSync,
  AppSettings settings,
  TimeZoneService timeZones,
) {
  final value = lastSuccessfulSync == null
      ? _label(settings.localeTag, 'never')
      : buildLessonWidgetLastSyncTime(lastSuccessfulSync, settings, timeZones);
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
      final groupKey = buildLessonWidgetGroupKey(start, settings, timeZones);
      payload.add({
        'key': lesson.callKey,
        'title': lesson.title,
        'start': start.millisecondsSinceEpoch,
        'displayStart': buildLessonWidgetLessonTime(start, settings, timeZones),
        'group': _label(settings.localeTag, groupKey),
        'groupKey': groupKey,
        'meetingUrl': lesson.meetingUrl,
        'callEnabled': settings.callEnabledFor(lesson),
      });
    } on FormatException {
      continue;
    }
  }
  payload.sort((a, b) => (a['start']! as int).compareTo(b['start']! as int));
  return payload;
}

/// Future, call-enabled occurrences only, ready for native alarm arming.
/// `requestCode` reuses [stableNotificationId] rather than duplicating the
/// hash on the Kotlin side.
List<Map<String, Object?>> buildLessonCallPayload(
  List<Lesson> lessons,
  AppSettings settings,
  TimeZoneService timeZones, {
  DateTime? now,
}) {
  final cutoff = now ?? DateTime.now();
  final payload = <Map<String, Object?>>[];
  for (final lesson in lessons) {
    if (!settings.callEnabledFor(lesson)) continue;
    DateTime start;
    try {
      start = timeZones.parseWebsiteTime(lesson.websiteStart);
    } on FormatException {
      continue;
    }
    if (!start.isAfter(cutoff)) continue;
    payload.add({
      'key': lesson.callKey,
      'requestCode': stableNotificationId('call|${lesson.callKey}'),
      'title': lesson.title,
      'displayStart': buildLessonWidgetLessonTime(start, settings, timeZones),
      'start': start.millisecondsSinceEpoch,
      'meetingUrl': lesson.meetingUrl,
    });
  }
  payload.sort((a, b) => (a['start']! as int).compareTo(b['start']! as int));
  return payload;
}

String buildLessonWidgetLessonTime(
  DateTime instant,
  AppSettings settings,
  TimeZoneService timeZones,
) {
  final zoned = timeZones.inZone(instant, settings.timeZoneId);
  final time = DateFormat('HH:mm').format(zoned);
  final day = zoned.day.toString().padLeft(2, '0');
  final month = _monthName(settings.localeTag, zoned.month);
  return '$time | $day-$month';
}

String buildLessonWidgetLastSyncTime(
  DateTime instant,
  AppSettings settings,
  TimeZoneService timeZones,
) => DateFormat('HH:mm').format(timeZones.inZone(instant, settings.timeZoneId));

String buildLessonWidgetGroupLabel(
  DateTime instant,
  AppSettings settings,
  TimeZoneService timeZones, {
  DateTime? now,
}) {
  return _label(
    settings.localeTag,
    buildLessonWidgetGroupKey(instant, settings, timeZones, now: now),
  );
}

String buildLessonWidgetGroupKey(
  DateTime instant,
  AppSettings settings,
  TimeZoneService timeZones, {
  DateTime? now,
}) {
  final lesson = timeZones.inZone(instant, settings.timeZoneId);
  final current = timeZones.inZone(now ?? DateTime.now(), settings.timeZoneId);
  final lessonDate = DateTime.utc(lesson.year, lesson.month, lesson.day);
  final currentDate = DateTime.utc(current.year, current.month, current.day);
  final daysAhead = lessonDate.difference(currentDate).inDays;
  return switch (daysAhead) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'others',
  };
}

// Kept as 6-per-row grids: one month per line reads far worse for a lookup
// table that is only ever indexed by month number.
// dart format off
const _monthNamesEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthNamesRu = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];
const _monthNamesUz = [
  'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun',
  'iyul', 'avgust', 'sentyabr', 'oktyabr', 'noyabr', 'dekabr',
];
const _monthNamesUzCyrl = [
  'январ', 'феврал', 'март', 'апрел', 'май', 'июн',
  'июл', 'август', 'сентябр', 'октябр', 'ноябр', 'декабр',
];
// dart format on

String _monthName(String locale, int month) {
  final names = switch (locale) {
    'ru' => _monthNamesRu,
    'en' => _monthNamesEn,
    'uz' => _monthNamesUz,
    _ => _monthNamesUzCyrl,
  };
  return names[month - 1];
}

String _label(String locale, String key) => switch ((locale, key)) {
  ('ru', 'sync') => 'Обновить',
  ('ru', 'subtitle') => 'Запланированные онлайн-занятия',
  ('ru', 'syncing') => 'Синхронизация…',
  ('ru', 'signIn') => 'Откройте KIU и войдите',
  ('ru', 'failed') => 'Ошибка синхронизации',
  ('ru', 'empty') => 'Нет запланированных уроков',
  ('ru', 'lastSync') => 'Последняя синхронизация',
  ('ru', 'never') => 'Никогда',
  ('ru', 'today') => 'Сегодня',
  ('ru', 'tomorrow') => 'Завтра',
  ('ru', 'others') => 'Другие',
  ('ru', 'callIncoming') => 'Урок начинается',
  ('ru', 'callAnswer') => 'Ответить',
  ('ru', 'callDecline') => 'Отклонить',
  ('ru', 'callToggleOn') => 'Включить звонок для этого урока',
  ('ru', 'callToggleOff') => 'Отключить звонок для этого урока',
  ('ru', 'callJoin') => 'Присоединиться к уроку',
  ('en', 'sync') => 'Sync',
  ('en', 'subtitle') => 'Scheduled online lessons',
  ('en', 'syncing') => 'Synchronizing…',
  ('en', 'signIn') => 'Open KIU and sign in',
  ('en', 'failed') => 'Synchronization failed',
  ('en', 'empty') => 'No scheduled lessons',
  ('en', 'lastSync') => 'Last sync',
  ('en', 'never') => 'Never',
  ('en', 'today') => 'Today',
  ('en', 'tomorrow') => 'Tomorrow',
  ('en', 'others') => 'Others',
  ('en', 'callIncoming') => 'Lesson starting',
  ('en', 'callAnswer') => 'Join',
  ('en', 'callDecline') => 'Dismiss',
  ('en', 'callToggleOn') => 'Turn on the call for this lesson',
  ('en', 'callToggleOff') => 'Turn off the call for this lesson',
  ('en', 'callJoin') => 'Join the lesson',
  ('uz', 'sync') => 'Yangilash',
  ('uz', 'subtitle') => 'Rejalashtirilgan onlayn darslar',
  ('uz', 'syncing') => 'Sinxronlanmoqda…',
  ('uz', 'signIn') => 'KIU ilovasini ochib tizimga kiring',
  ('uz', 'failed') => 'Sinxronlash xatosi',
  ('uz', 'empty') => 'Rejalashtirilgan darslar yo‘q',
  ('uz', 'lastSync') => 'Oxirgi sinxronlash',
  ('uz', 'never') => 'Hali yo‘q',
  ('uz', 'today') => 'Bugun',
  ('uz', 'tomorrow') => 'Ertaga',
  ('uz', 'others') => 'Boshqalar',
  ('uz', 'callIncoming') => 'Dars boshlanmoqda',
  ('uz', 'callAnswer') => 'Qo‘shilish',
  ('uz', 'callDecline') => 'Rad etish',
  ('uz', 'callToggleOn') => 'Bu dars uchun qo‘ng‘iroqni yoqish',
  ('uz', 'callToggleOff') => 'Bu dars uchun qo‘ng‘iroqni o‘chirish',
  ('uz', 'callJoin') => 'Darsga qo‘shilish',
  (_, 'sync') => 'Янгилаш',
  (_, 'subtitle') => 'Режалаштирилган онлайн дарслар',
  (_, 'syncing') => 'Синхронланмоқда…',
  (_, 'signIn') => 'KIU иловасини очиб тизимга киринг',
  (_, 'failed') => 'Синхронлаш хатоси',
  (_, 'empty') => 'Режалаштирилган дарслар йўқ',
  (_, 'lastSync') => 'Охирги синхронлаш',
  (_, 'never') => 'Ҳали йўқ',
  (_, 'today') => 'Бугун',
  (_, 'tomorrow') => 'Эртага',
  (_, 'others') => 'Бошқалар',
  (_, 'callIncoming') => 'Дарс бошланмоқда',
  (_, 'callAnswer') => 'Қўшилиш',
  (_, 'callDecline') => 'Рад этиш',
  (_, 'callToggleOn') => 'Бу дарс учун қўнғироқни ёқиш',
  (_, 'callToggleOff') => 'Бу дарс учун қўнғироқни ўчириш',
  (_, 'callJoin') => 'Дарсга қўшилиш',
  _ => '',
};
