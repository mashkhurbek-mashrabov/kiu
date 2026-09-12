import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/domain/app_settings.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:kiu/services/lesson_widget_service.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/time_zone_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);

  test('global switch enables calls for every future occurrence', () {
    const lessons = [
      Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00'),
      Lesson(title: 'Tafsir', websiteStart: '2026-09-09 20:00'),
    ];
    const enabled = AppSettings(callsEnabled: true);
    const disabled = AppSettings();

    expect(
      buildLessonCallPayload(lessons, enabled, TimeZoneService(), now: now),
      hasLength(2),
    );
    expect(
      buildLessonCallPayload(lessons, disabled, TimeZoneService(), now: now),
      isEmpty,
    );
  });

  test('per-occurrence override wins over the global switch either way', () {
    const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
    final offSettings = AppSettings(
      callsEnabled: true,
      callOverrides: {lesson.callKey: false},
    );
    final onSettings = AppSettings(callOverrides: {lesson.callKey: true});

    expect(
      buildLessonCallPayload(
        [lesson],
        offSettings,
        TimeZoneService(),
        now: now,
      ),
      isEmpty,
    );
    expect(
      buildLessonCallPayload([lesson], onSettings, TimeZoneService(), now: now),
      hasLength(1),
    );
  });

  test('past occurrences are excluded', () {
    const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 11:00');
    const settings = AppSettings(callsEnabled: true);

    expect(
      buildLessonCallPayload([lesson], settings, TimeZoneService(), now: now),
      isEmpty,
    );
  });

  test('malformed websiteStart is skipped, not thrown', () {
    const lessons = [
      Lesson(title: 'Broken', websiteStart: 'not-a-date'),
      Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00'),
    ];
    const settings = AppSettings(callsEnabled: true);

    final payload = buildLessonCallPayload(
      lessons,
      settings,
      TimeZoneService(),
      now: now,
    );

    expect(payload, hasLength(1));
    expect(payload.single['title'], 'Tahfiz');
  });

  test('requestCode is stable across rebuilds and distinct per occurrence', () {
    const first = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
    const second = Lesson(title: 'Tahfiz', websiteStart: '2026-09-10 19:00');
    const settings = AppSettings(callsEnabled: true);

    final firstBuild = buildLessonCallPayload(
      [first, second],
      settings,
      TimeZoneService(),
      now: now,
    );
    final secondBuild = buildLessonCallPayload(
      [first, second],
      settings,
      TimeZoneService(),
      now: now,
    );

    expect(firstBuild.first['requestCode'], secondBuild.first['requestCode']);
    expect(
      firstBuild.first['requestCode'],
      isNot(firstBuild.last['requestCode']),
    );
    expect(
      firstBuild.first['requestCode'],
      stableNotificationId('call|${first.callKey}'),
    );
  });
}
