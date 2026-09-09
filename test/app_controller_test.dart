import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
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
