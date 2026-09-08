import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants.dart';

class TimeZoneService {
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  List<String> get availableZoneIds {
    initialize();
    return tz.timeZoneDatabase.locations.keys.toList()..sort();
  }

  DateTime parseWebsiteTime(String value) {
    initialize();
    final parts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})$')
        .firstMatch(value);
    if (parts == null) throw FormatException('Invalid LMS date', value);
    final location = tz.getLocation(websiteTimeZone);
    return tz.TZDateTime(
      location,
      int.parse(parts.group(1)!),
      int.parse(parts.group(2)!),
      int.parse(parts.group(3)!),
      int.parse(parts.group(4)!),
      int.parse(parts.group(5)!),
    ).toUtc();
  }

  tz.TZDateTime inZone(DateTime instant, String zoneId) {
    initialize();
    return tz.TZDateTime.from(instant.toUtc(), tz.getLocation(zoneId));
  }

  String display(DateTime instant, String zoneId) {
    final local = inZone(instant, zoneId);
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${DateFormat('yyyy-MM-dd HH:mm').format(local)} '
        '$zoneId (GMT$sign$hours:$minutes)';
  }
}
