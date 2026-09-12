import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/services/time_zone_service.dart';

void main() {
  final service = TimeZoneService();

  test('interprets LMS wall time in Asia/Tashkent', () {
    final instant = service.parseWebsiteTime('2026-09-09 19:00');
    expect(instant, DateTime.utc(2026, 9, 9, 14));
    expect(service.inZone(instant, 'America/New_York').hour, 10);
    expect(service.inZone(instant, 'Europe/London').hour, 15);
  });

  test('uses DST offset at the lesson date', () {
    final summer = service.inZone(DateTime.utc(2026, 7, 1, 12), 'Europe/London');
    final winter = service.inZone(DateTime.utc(2026, 12, 1, 12), 'Europe/London');
    expect(summer.timeZoneOffset, const Duration(hours: 1));
    expect(winter.timeZoneOffset, Duration.zero);
  });

  test('rejects invalid LMS date', () {
    expect(() => service.parseWebsiteTime('09/09/2026'), throwsFormatException);
  });
}
