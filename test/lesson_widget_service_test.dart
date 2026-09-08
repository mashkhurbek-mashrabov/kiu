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
    expect(payload.first['displayStart'], contains('Europe/London'));
    expect(payload.last['meetingUrl'], 'https://meet.example/second');
  });
}
