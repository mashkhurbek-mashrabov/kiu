import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:kiu/services/notification_service.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<AppController> createController(
  FakeNotificationGateway notifications,
  FakeBackgroundScheduler scheduler, {
  FakeLessonWidgetGateway? lessonWidgets,
}) async {
  final repository = SettingsRepository(await SharedPreferences.getInstance());
  final reconciler = ReminderReconciler(
    repository: repository,
    notifications: notifications,
  );
  return AppController(
    repository: repository,
    syncService: ScheduleSyncService(
      fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
      repository: repository,
      reconciler: reconciler,
    ),
    reconciler: reconciler,
    notifications: notifications,
    scheduler: scheduler,
    lessonWidgets: lessonWidgets,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads safe defaults and persists clamped playback rate', () async {
    final controller = await createController(
      FakeNotificationGateway(),
      FakeBackgroundScheduler(),
    );
    expect(controller.settings.localeTag, 'uz_Cyrl');
    expect(controller.settings.timeZoneId, 'Asia/Tashkent');
    expect(controller.settings.remindersEnabled, isFalse);
    expect(controller.settings.backgroundSyncEnabled, isTrue);
    expect(controller.settings.reminderOffsetsMinutes, [60, 0]);

    await controller.setPlaybackRate(12);
    expect(controller.settings.playbackRate, 4);
    await controller.setPlaybackRate(0.25);
    expect(controller.settings.playbackRate, 0.5);
    final reloaded = SettingsRepository(await SharedPreferences.getInstance())
        .loadSettings();
    expect(reloaded.playbackRate, 0.5);
  });

  test('registers background sync by default during initialization', () async {
    final scheduler = FakeBackgroundScheduler();
    final controller = await createController(
      FakeNotificationGateway(),
      scheduler,
    );
    await controller.initialize();
    expect(scheduler.enabled, isTrue);
  });

  test(
    'reschedules cached reminders during initialization, not just on sync',
    () async {
      SharedPreferences.setMockInitialValues({
        'kiu.reminders': true,
        'kiu.lessonSnapshot':
            '[{"title":"Tafsir","websiteStart":"2026-09-09 19:00"}]',
      });
      final notifications = FakeNotificationGateway();
      final repository = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      final reconciler = ReminderReconciler(
        repository: repository,
        notifications: notifications,
        now: () => DateTime.utc(2026, 9, 9, 12),
      );
      final controller = AppController(
        repository: repository,
        syncService: ScheduleSyncService(
          fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
          repository: repository,
          reconciler: reconciler,
        ),
        reconciler: reconciler,
        notifications: notifications,
        scheduler: FakeBackgroundScheduler(),
      );

      // No synchronize() call and no WebView page load -- initialize()
      // alone must be enough to re-arm reminders scheduled in a prior
      // session, since a cold start can't rely on the WebView reaching
      // the lessons page or on a background WorkManager chain that may
      // have died silently.
      await controller.initialize();

      expect(notifications.scheduled, isNotEmpty);
    },
  );

  test('publishes cached last sync to widget during initialization', () async {
    final lastSync = DateTime.utc(2026, 9, 8, 12);
    SharedPreferences.setMockInitialValues({
      'kiu.lastSyncSuccess': lastSync.toIso8601String(),
      'kiu.lessonSnapshot':
          '[{"title":"Tafsir","websiteStart":"2026-09-09 19:00"}]',
    });
    final widgets = FakeLessonWidgetGateway();
    final controller = await createController(
      FakeNotificationGateway(),
      FakeBackgroundScheduler(),
      lessonWidgets: widgets,
    );

    await controller.initialize();

    expect(widgets.lastSuccessfulSync, lastSync);
    expect(widgets.lessons, hasLength(1));
  });

  test(
    'does not enable reminders when notification permission is denied',
    () async {
      final notifications = FakeNotificationGateway()..permission = false;
      final scheduler = FakeBackgroundScheduler();
      final controller = await createController(notifications, scheduler);

      expect(await controller.setRemindersEnabled(true), isFalse);
      expect(controller.settings.remindersEnabled, isFalse);
      expect(scheduler.enabled, isFalse);
    },
  );

  test('background work is independent from reminder permission', () async {
    final scheduler = FakeBackgroundScheduler();
    final controller = await createController(
      FakeNotificationGateway(),
      scheduler,
    );
    expect(await controller.setRemindersEnabled(true), isTrue);
    expect(scheduler.enabled, isFalse);
    await controller.setBackgroundSyncEnabled(false);
    expect(scheduler.enabled, isFalse);
    await controller.setBackgroundSyncEnabled(true);
    expect(scheduler.enabled, isTrue);
  });

  test('persists main sound and per-reminder override', () async {
    final notifications = FakeNotificationGateway()
      ..selectedSound = const NotificationSound(
        uri: 'content://media/internal/audio/media/42',
        name: 'First sound',
      );
    final controller = await createController(
      notifications,
      FakeBackgroundScheduler(),
    );

    await controller.selectMainReminderSound();
    notifications.selectedSound = const NotificationSound(
      uri: 'content://media/internal/audio/media/7',
      name: 'Second sound',
    );
    await controller.selectReminderSoundOverride(60);

    expect(
      controller.settings.reminderSoundUri,
      'content://media/internal/audio/media/42',
    );
    expect(controller.settings.reminderSoundOverrides, {
      60: 'content://media/internal/audio/media/7',
    });
    expect(controller.settings.reminderSoundName, 'First sound');
    expect(controller.settings.reminderSoundOverrideNames, {
      60: 'Second sound',
    });
    final reloaded = SettingsRepository(await SharedPreferences.getInstance())
        .loadSettings();
    expect(reloaded.reminderSoundUri, controller.settings.reminderSoundUri);
    expect(
      reloaded.reminderSoundOverrides,
      controller.settings.reminderSoundOverrides,
    );
    expect(
      reloaded.reminderSoundOverrideNames,
      controller.settings.reminderSoundOverrideNames,
    );

    await controller.clearReminderSoundOverride(60);
    expect(controller.settings.reminderSoundOverrides, isEmpty);
    expect(controller.settings.reminderSoundOverrideNames, isEmpty);
  });

  test('setLessonCallEnabled overrides in both directions, clearing when it '
      'matches the global switch', () async {
    const lesson = Lesson(title: 'Tahfiz', websiteStart: '2026-09-09 19:00');
    final controller = await createController(
      FakeNotificationGateway(),
      FakeBackgroundScheduler(),
    );

    // Global is off; turning this lesson on needs an explicit override.
    await controller.setLessonCallEnabled(lesson, true);
    expect(controller.settings.callOverrides, {lesson.callKey: true});

    // Setting it back to the (still off) global value removes the entry
    // instead of storing a redundant `false`.
    await controller.setLessonCallEnabled(lesson, false);
    expect(controller.settings.callOverrides, isEmpty);
  });

  test('setCallRingSeconds clamps to the 10-300 range', () async {
    final controller = await createController(
      FakeNotificationGateway(),
      FakeBackgroundScheduler(),
    );

    await controller.setCallRingSeconds(1);
    expect(controller.settings.callRingSeconds, 10);

    await controller.setCallRingSeconds(1000);
    expect(controller.settings.callRingSeconds, 300);
  });

  test('setCallsEnabled refuses and does not persist without notification '
      'permission', () async {
    final notifications = FakeNotificationGateway()..permission = false;
    final controller = await createController(
      notifications,
      FakeBackgroundScheduler(),
    );

    expect(await controller.setCallsEnabled(true), isFalse);
    expect(controller.settings.callsEnabled, isFalse);
    final reloaded = SettingsRepository(await SharedPreferences.getInstance())
        .loadSettings();
    expect(reloaded.callsEnabled, isFalse);
  });

  test('loads legacy per-reminder sounds as overrides', () async {
    SharedPreferences.setMockInitialValues({
      'kiu.reminderSoundUris':
          '{"60":"content://media/internal/audio/media/42"}',
    });
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );

    final settings = repository.loadSettings();

    expect(settings.reminderSoundUri, isNull);
    expect(settings.reminderSoundOverrides, {
      60: 'content://media/internal/audio/media/42',
    });
  });
}
