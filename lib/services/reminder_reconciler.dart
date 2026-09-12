import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';
import '../domain/lesson.dart';
import 'lesson_widget_service.dart';
import 'notification_service.dart';
import 'time_zone_service.dart';

const _notificationDeliveryGrace = Duration(hours: 1);

class ReminderReconcileResult {
  const ReminderReconcileResult({
    required this.scheduledCount,
    required this.exact,
  });

  final int scheduledCount;
  final bool exact;
}

class ReminderReconciler {
  ReminderReconciler({
    required SettingsRepository repository,
    required NotificationGateway notifications,
    TimeZoneService? timeZones,
    DateTime Function()? now,
  }) : _repository = repository,
       _notifications = notifications,
       _timeZones = timeZones ?? TimeZoneService(),
       _now = now ?? DateTime.now;

  final SettingsRepository _repository;
  final NotificationGateway _notifications;
  final TimeZoneService _timeZones;
  final DateTime Function() _now;

  Future<ReminderReconcileResult> reconcile(
    List<Lesson> lessons,
    AppSettings settings,
  ) async {
    await _repository.saveLessons(lessons);
    await _repository.pruneCallOverrides({
      for (final lesson in lessons) lesson.callKey,
    });
    final previousIds = _repository.loadScheduledIds();
    final nextIds = <int>{};
    final exact =
        settings.remindersEnabled && await _notifications.canScheduleExactly();
    final now = _now().toUtc();

    if (settings.remindersEnabled) {
      final offsets = settings.reminderOffsetsMinutes.toSet().where(
        (offset) => offset >= 0 && offset <= 10080,
      );
      for (final lesson in lessons) {
        DateTime start;
        try {
          start = _timeZones.parseWebsiteTime(lesson.websiteStart);
        } on FormatException {
          continue;
        }
        for (final offset in offsets) {
          final trigger = start.subtract(Duration(minutes: offset));
          final id = stableNotificationId('${lesson.key}|$offset');
          if (!trigger.isAfter(now)) {
            // Android may deliver inexact alarms after their trigger. Keep an
            // already-scheduled alarm long enough for its receiver to run.
            // ponytail: one-hour cap prevents obsolete late notifications.
            if (previousIds.contains(id) &&
                trigger.add(_notificationDeliveryGrace).isAfter(now)) {
              nextIds.add(id);
            }
            continue;
          }
          try {
            await _notifications.schedule(
              id: id,
              when: _timeZones.inZone(trigger, settings.timeZoneId),
              title: lesson.title,
              body: _notificationBody(settings, start, offset),
              payload: homeUrl,
              exact: exact,
              reminderOffsetMinutes: offset,
              soundUri:
                  settings.reminderSoundOverrides[offset] ??
                  settings.reminderSoundUri,
            );
            // ponytail: one failed alarm (e.g. a revoked custom sound URI)
            // must not abort the whole batch and strand every later lesson
            // unscheduled; only mark ids that actually made it to the OS.
            nextIds.add(id);
          } on PlatformException catch (error) {
            // A silent `continue` here previously hid systemic failures
            // (e.g. every offset sharing one revoked sound URI, or exact
            // alarm permission dropped mid-session): sync would report
            // success with scheduledCount 0 and nobody could tell why
            // reminders stopped firing. Surface it instead.
            debugPrint(
              'ReminderReconciler: failed to schedule "${lesson.title}" '
              '(+$offset min): $error',
            );
            continue;
          }
        }
      }
    }

    for (final staleId in previousIds.difference(nextIds)) {
      await _notifications.cancel(staleId);
    }
    await _repository.saveScheduledIds(nextIds);
    return ReminderReconcileResult(
      scheduledCount: nextIds.length,
      exact: exact,
    );
  }

  String _notificationBody(AppSettings settings, DateTime start, int offset) {
    final locale = settings.localeTag;
    final date = buildLessonWidgetLessonTime(start, settings, _timeZones);
    final timing = switch (locale) {
      'ru' =>
        offset == 0 ? 'Начинается сейчас' : 'Через ${_offset(locale, offset)}',
      'en' =>
        offset == 0 ? 'Starts now' : 'Starts in ${_offset(locale, offset)}',
      'uz' =>
        offset == 0
            ? 'Hozir boshlanadi'
            : '${_offset(locale, offset)}dan keyin boshlanadi',
      _ =>
        offset == 0
            ? 'Ҳозир бошланади'
            : '${_offset(locale, offset)}дан кейин бошланади',
    };
    return '$date\n$timing';
  }

  String _offset(String locale, int minutes) {
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return switch (locale) {
        'ru' => '$hours ч',
        'en' => '$hours h',
        'uz' => '$hours soat',
        _ => '$hours соат',
      };
    }
    return switch (locale) {
      'ru' => '$minutes мин',
      'en' => '$minutes min',
      'uz' => '$minutes daqiqa',
      _ => '$minutes дақиқа',
    };
  }
}

int stableNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final byte in value.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
