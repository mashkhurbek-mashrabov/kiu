import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/domain/app_settings.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:kiu/services/lesson_widget_service.dart';
import 'package:kiu/services/time_zone_service.dart';

void main() {
  test('widget payload is chronological and uses absolute lesson instants', () {
    const lessons = [
      Lesson(
        title: 'Second',
        websiteStart: '2026-09-09 20:00',
        meetingUrl: 'https://meet.example/second',
      ),
      Lesson(title: 'First', websiteStart: '2026-09-09 19:00'),
    ];
    const settings = AppSettings(timeZoneId: 'Europe/London');
    final payload = buildLessonWidgetPayload(
      lessons,
      settings,
      TimeZoneService(),
    );

    expect(payload.map((item) => item['title']), ['First', 'Second']);
    expect(
      payload.first['start'],
      DateTime.utc(2026, 9, 9, 14).millisecondsSinceEpoch,
    );
    expect(payload.first['displayStart'], '15:00 | 09-сентябр');
    expect(payload.last['meetingUrl'], 'https://meet.example/second');
    expect(payload.first['key'], lessons.last.callKey);
    expect(payload.first['callEnabled'], isFalse);
  });

  test('widget dark flag follows the in-app appearance choice', () {
    expect(
      widgetDarkFlag(const AppSettings(themeMode: ThemeMode.dark)),
      'true',
    );
    expect(
      widgetDarkFlag(const AppSettings(themeMode: ThemeMode.light)),
      'false',
    );
    // System mode resolves against the platform, which reports light in tests.
    expect(widgetDarkFlag(const AppSettings()), 'false');
  });

  test('payload carries per-occurrence call state', () {
    const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
    final settings = AppSettings(callOverrides: {lesson.callKey: true});

    final payload = buildLessonWidgetPayload(
      [lesson],
      settings,
      TimeZoneService(),
    );

    expect(payload.single['key'], lesson.callKey);
    expect(payload.single['callEnabled'], isTrue);
  });

  test('widget last sync uses selected time zone', () {
    const settings = AppSettings(localeTag: 'en', timeZoneId: 'Europe/London');

    final label = buildLessonWidgetLastSyncLabel(
      DateTime.utc(2026, 9, 9, 14),
      settings,
      TimeZoneService(),
    );

    expect(label, 'Last sync: 15:00');
  });

  test('widget groups lessons by selected time zone', () {
    const settings = AppSettings(localeTag: 'en', timeZoneId: 'Asia/Tashkent');
    final timeZones = TimeZoneService();
    final now = DateTime.utc(2026, 9, 9, 19);

    expect(
      buildLessonWidgetGroupLabel(
        DateTime.utc(2026, 9, 9, 20),
        settings,
        timeZones,
        now: now,
      ),
      'Today',
    );
    expect(
      buildLessonWidgetGroupKey(
        DateTime.utc(2026, 9, 9, 20),
        settings,
        timeZones,
        now: now,
      ),
      'today',
    );
    expect(
      buildLessonWidgetGroupLabel(
        DateTime.utc(2026, 9, 10, 20),
        settings,
        timeZones,
        now: now,
      ),
      'Tomorrow',
    );
    expect(
      buildLessonWidgetGroupLabel(
        DateTime.utc(2026, 9, 11, 20),
        settings,
        timeZones,
        now: now,
      ),
      'Others',
    );
  });

  test('widget redraws at upcoming lesson starts', () {
    final now = DateTime.utc(2026, 9, 9, 14);
    final updates = buildLessonWidgetUpdateTimes([
      {'start': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch},
    ], now);

    expect(updates, hasLength(1));
    expect(
      updates.single.isAtSameMomentAs(now.add(const Duration(minutes: 5))),
      isTrue,
    );
  });
}
