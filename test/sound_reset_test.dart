import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/app_settings.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Clearing a custom sound has to survive a save/load round trip. Both the
/// `?? this.value` in copyWith and the `if (value != null)` in saveSettings
/// used to swallow an explicit null, so a reset silently resurrected the old
/// sound on the next launch.
Future<AppController> createController(SettingsRepository repository) async {
  final notifications = FakeNotificationGateway();
  return AppController(
    repository: repository,
    syncService: ScheduleSyncService(
      fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
      repository: repository,
      reconciler: ReminderReconciler(
        repository: repository,
        notifications: notifications,
      ),
    ),
    reconciler: ReminderReconciler(
      repository: repository,
      notifications: notifications,
    ),
    notifications: notifications,
    scheduler: FakeBackgroundScheduler(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('copyWith distinguishes omitted from explicit null', () {
    test('omitting a sound keeps the current value', () {
      const settings = AppSettings(
        reminderSoundUri: 'content://custom',
        reminderSoundName: 'Custom',
      );
      final next = settings.copyWith(playbackRate: 2);
      expect(next.reminderSoundUri, 'content://custom');
      expect(next.reminderSoundName, 'Custom');
    });

    test('passing null clears the value', () {
      const settings = AppSettings(
        reminderSoundUri: 'content://custom',
        reminderSoundName: 'Custom',
        callRingtoneUri: 'content://ring',
        callRingtoneName: 'Ring',
      );
      final cleared = settings.copyWith(
        reminderSoundUri: null,
        reminderSoundName: null,
        callRingtoneUri: null,
        callRingtoneName: null,
      );
      expect(cleared.reminderSoundUri, isNull);
      expect(cleared.reminderSoundName, isNull);
      expect(cleared.callRingtoneUri, isNull);
      expect(cleared.callRingtoneName, isNull);
    });
  });

  test('a cleared sound stays cleared across a reload', () async {
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    await repository.saveSettings(
      const AppSettings(
        reminderSoundUri: 'content://custom',
        reminderSoundName: 'Custom',
        callRingtoneUri: 'content://ring',
        callRingtoneName: 'Ring',
      ),
    );
    expect(repository.loadSettings().reminderSoundUri, 'content://custom');

    await repository.saveSettings(
      repository.loadSettings().copyWith(
        reminderSoundUri: null,
        reminderSoundName: null,
        callRingtoneUri: null,
        callRingtoneName: null,
      ),
    );

    final reloaded = repository.loadSettings();
    expect(reloaded.reminderSoundUri, isNull);
    expect(reloaded.reminderSoundName, isNull);
    expect(reloaded.callRingtoneUri, isNull);
    expect(reloaded.callRingtoneName, isNull);
  });

  test('controller reset methods clear and persist', () async {
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    await repository.saveSettings(
      const AppSettings(
        reminderSoundUri: 'content://custom',
        reminderSoundName: 'Custom',
        callRingtoneUri: 'content://ring',
        callRingtoneName: 'Ring',
      ),
    );
    final controller = await createController(repository);

    await controller.clearReminderSound();
    expect(controller.settings.reminderSoundUri, isNull);
    expect(repository.loadSettings().reminderSoundUri, isNull);
    // Clearing one sound must not disturb the other.
    expect(controller.settings.callRingtoneUri, 'content://ring');

    await controller.clearCallRingtone();
    expect(controller.settings.callRingtoneUri, isNull);
    expect(repository.loadSettings().callRingtoneUri, isNull);
  });
}
