import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/app_settings.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  late SettingsRepository repository;
  late FakeNotificationGateway notifications;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = SettingsRepository(await SharedPreferences.getInstance());
    notifications = FakeNotificationGateway();
  });

  test('schedules selected future offsets with stable IDs', () async {
    final reconciler = ReminderReconciler(
      repository: repository,
      notifications: notifications,
      now: () => DateTime.utc(2026, 9, 9, 12),
    );
    const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
    const settings = AppSettings(
      remindersEnabled: true,
      reminderOffsetsMinutes: [60, 15, 0, 15],
    );
    final result = await reconciler.reconcile([lesson], settings);
    expect(result.scheduledCount, 3);
    expect(notifications.scheduled, hasLength(3));
    expect(notifications.scheduled.values.every((call) => call.exact), isTrue);
    expect(
      notifications.scheduled.values.first.body,
      contains('Asia/Tashkent'),
    );
  });

  test('uses main sound unless reminder has an override', () async {
    final reconciler = ReminderReconciler(
      repository: repository,
      notifications: notifications,
      now: () => DateTime.utc(2026, 9, 9, 12),
    );
    const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
    const settings = AppSettings(
      remindersEnabled: true,
      reminderOffsetsMinutes: [60, 0],
      reminderSoundUri: 'content://media/internal/audio/media/1',
      reminderSoundOverrides: {0: 'content://media/internal/audio/media/2'},
    );

    await reconciler.reconcile([lesson], settings);

    expect(
      notifications.scheduled.values
          .singleWhere((call) => call.reminderOffsetMinutes == 60)
          .soundUri,
      'content://media/internal/audio/media/1',
    );
    expect(
      notifications.scheduled.values
          .singleWhere((call) => call.reminderOffsetMinutes == 0)
          .soundUri,
      'content://media/internal/audio/media/2',
    );
  });

  test('uses separate channels when an offset sound changes', () {
    expect(
      reminderNotificationChannelId(60, 'content://media/internal/audio/1'),
      isNot(
        reminderNotificationChannelId(60, 'content://media/internal/audio/2'),
      ),
    );
    expect(
      reminderNotificationChannelId(60, null),
      isNot(reminderNotificationChannelId(0, null)),
    );
  });

  test('skips elapsed triggers and cancels only owned stale IDs', () async {
    final first = ReminderReconciler(
      repository: repository,
      notifications: notifications,
      now: () => DateTime.utc(2026, 9, 9, 13, 50),
    );
    const settings = AppSettings(
      remindersEnabled: true,
      reminderOffsetsMinutes: [60, 15, 0],
    );
    const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
    await first.reconcile([lesson], settings);
    expect(notifications.scheduled, hasLength(1));
    final ownedId = notifications.scheduled.keys.single;
    await first.reconcile(const [], settings);
    expect(notifications.cancelled, contains(ownedId));
  });

  test(
    'disabled reminders cancel prior requests while preserving snapshot',
    () async {
      await repository.saveScheduledIds({101, 202});
      const lesson = Lesson(title: 'Course', websiteStart: '2026-09-09 19:00');
      final reconciler = ReminderReconciler(
        repository: repository,
        notifications: notifications,
      );
      await reconciler.reconcile([lesson], const AppSettings());
      expect(notifications.cancelled, containsAll([101, 202]));
      expect(repository.loadLessons(), [lesson]);
    },
  );
}
