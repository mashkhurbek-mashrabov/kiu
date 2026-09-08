import 'package:kiu/app/app_controller.dart';
import 'package:kiu/services/notification_service.dart';
import 'package:kiu/services/lesson_widget_service.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/domain/app_settings.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:timezone/timezone.dart' as tz;

class FakeNotificationGateway implements NotificationGateway {
  bool permission = true;
  bool exact = true;
  final Map<int, ScheduledCall> scheduled = {};
  final List<int> cancelled = [];

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

  @override
  Future<void> schedule({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required String payload,
    required bool exact,
  }) async {
    scheduled[id] = ScheduledCall(
      when: when,
      title: title,
      body: body,
      payload: payload,
      exact: exact,
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
  });

  final tz.TZDateTime when;
  final String title;
  final String body;
  final String payload;
  final bool exact;
}

class FakeBackgroundScheduler implements BackgroundScheduler {
  bool enabled = false;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
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

  @override
  Future<List<Lesson>> fetch({String? userAgent}) async {
    this.userAgent = userAgent;
    return lessons;
  }
}

class FakeLessonWidgetGateway implements LessonWidgetGateway {
  List<Lesson>? lessons;
  AppSettings? settings;
  ScheduleSyncStatus? status;
  DateTime? lastSuccessfulSync;
  bool showSuccessStatus = false;

  @override
  Future<void> publish(
    List<Lesson> value,
    AppSettings appSettings, {
    DateTime? lastSuccessfulSync,
    bool showSuccessStatus = false,
  }) async {
    lessons = value;
    settings = appSettings;
    this.lastSuccessfulSync = lastSuccessfulSync;
    this.showSuccessStatus = showSuccessStatus;
  }

  @override
  Future<void> publishStatus(
    ScheduleSyncStatus value,
    AppSettings appSettings,
  ) async {
    status = value;
    settings = appSettings;
  }
}
