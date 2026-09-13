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
    expect(notifications.scheduled.values.first.body, contains('19:00'));
    expect(
      notifications.scheduled.values.first.body,
      isNot(contains('Asia/Tashkent')),
    );
  });

  group('reminder body is localized from the ARB files', () {
    Future<Map<int, String>> bodiesFor(String localeTag) async {
      final gateway = FakeNotificationGateway();
      final reconciler = ReminderReconciler(
        repository: repository,
        notifications: gateway,
        now: () => DateTime.utc(2026, 9, 9, 12),
      );
      await reconciler.reconcile(
        const [Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00')],
        AppSettings(
          remindersEnabled: true,
          localeTag: localeTag,
          reminderOffsetsMinutes: const [60, 45, 0],
        ),
      );
      return {
        for (final call in gateway.scheduled.values)
          call.reminderOffsetMinutes: call.body,
      };
    }

    test('English uses whole-hour and minute units', () async {
      final bodies = await bodiesFor('en');
      expect(bodies[60], contains('Starts in 1 h'));
      expect(bodies[45], contains('Starts in 45 min'));
      expect(bodies[0], contains('Starts now'));
    });

    test('Russian', () async {
      final bodies = await bodiesFor('ru');
      expect(bodies[60], contains('Начинается через 1 ч'));
      expect(bodies[0], contains('Начинается сейчас'));
    });

    test('Latin Uzbek', () async {
      final bodies = await bodiesFor('uz');
      expect(bodies[60], contains('1 soatdan keyin boshlanadi'));
      expect(bodies[0], contains('Hozir boshlanadi'));
    });

    test('Cyrillic Uzbek is the default', () async {
      final bodies = await bodiesFor('uz_Cyrl');
      expect(bodies[60], contains('1 соатдан кейин бошланади'));
      expect(bodies[0], contains('Ҳозир бошланади'));
    });

    test('every body still leads with the lesson time', () async {
      final bodies = await bodiesFor('en');
      expect(bodies.values.every((body) => body.startsWith('19:00')), isTrue);
    });
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
    'does not cancel a due inexact alarm before Android delivers it',
    () async {
      var now = DateTime.utc(2026, 9, 9, 12, 59);
      final reconciler = ReminderReconciler(
        repository: repository,
        notifications: notifications..exact = false,
        now: () => now,
      );
      const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 18:01');
      const settings = AppSettings(
        remindersEnabled: true,
        reminderOffsetsMinutes: [1],
      );

      await reconciler.reconcile([lesson], settings);
      final id = stableNotificationId('${lesson.key}|1');
      expect(notifications.scheduled, contains(id));

      now = DateTime.utc(2026, 9, 9, 13, 0, 1);
      await reconciler.reconcile([lesson], settings);

      expect(notifications.cancelled, isNot(contains(id)));

      now = DateTime.utc(2026, 9, 9, 14, 0, 1);
      await reconciler.reconcile([lesson], settings);

      expect(notifications.cancelled, contains(id));
    },
  );

  test(
    'one failed schedule call does not strand other lessons unscheduled',
    () async {
      final reconciler = ReminderReconciler(
        repository: repository,
        notifications: notifications,
        now: () => DateTime.utc(2026, 9, 9, 12),
      );
      const failingLesson = Lesson(
        title: 'Broken sound',
        websiteStart: '2026-09-09 19:00',
      );
      const okLesson = Lesson(
        title: 'Tahfiz',
        websiteStart: '2026-09-09 20:00',
      );
      const settings = AppSettings(
        remindersEnabled: true,
        reminderOffsetsMinutes: [0],
      );
      notifications.failScheduleIds.add(
        stableNotificationId('${failingLesson.key}|0'),
      );

      final result = await reconciler.reconcile([
        failingLesson,
        okLesson,
      ], settings);

      expect(result.scheduledCount, 1);
      expect(notifications.scheduled, hasLength(1));
      expect(notifications.scheduled.values.single.title, okLesson.title);
      // The failed id must not be persisted as "scheduled", so the next
      // reconcile pass retries it instead of treating it as stale/owned.
      expect(
        repository.loadScheduledIds(),
        isNot(contains(stableNotificationId('${failingLesson.key}|0'))),
      );
    },
  );

  test(
    'reconcile prunes call overrides for lessons no longer scheduled',
    () async {
      const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
      const stale = Lesson(title: 'Gone', websiteStart: '2026-09-08 19:00');
      await repository.saveSettings(
        AppSettings(
          callOverrides: {lesson.callKey: true, stale.callKey: false},
        ),
      );
      final reconciler = ReminderReconciler(
        repository: repository,
        notifications: notifications,
        now: () => DateTime.utc(2026, 9, 9, 12),
      );

      await reconciler.reconcile([lesson], const AppSettings());

      expect(repository.loadSettings().callOverrides, {lesson.callKey: true});
    },
  );

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
