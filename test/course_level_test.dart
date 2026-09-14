import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<(AppController, SettingsRepository)> build() async {
  final repository = SettingsRepository(await SharedPreferences.getInstance());
  final notifications = FakeNotificationGateway();
  final reconciler = ReminderReconciler(
    repository: repository,
    notifications: notifications,
  );
  return (
    AppController(
      repository: repository,
      syncService: ScheduleSyncService(
        // No cookies, so the fetcher reports 'auth' and the sync lands on
        // signInRequired -- the same signal a real sign-out produces.
        fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
        repository: repository,
        reconciler: reconciler,
      ),
      reconciler: reconciler,
      notifications: notifications,
      scheduler: FakeBackgroundScheduler(),
    ),
    repository,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SettingsRepository.courseLevel', () {
    test('round-trips a level and clears on null', () async {
      final repository = SettingsRepository(
        await SharedPreferences.getInstance(),
      );

      expect(repository.courseLevel, isNull);
      await repository.saveCourseLevel(2);
      expect(repository.courseLevel, 2);
      await repository.saveCourseLevel(null);
      expect(repository.courseLevel, isNull);
    });

    test('reads a stored non-positive level as unknown', () async {
      SharedPreferences.setMockInitialValues({'kiu.courseLevel': 0});
      final repository = SettingsRepository(
        await SharedPreferences.getInstance(),
      );

      expect(repository.courseLevel, isNull);
    });

    test('reads a stored value of the wrong type as unknown', () async {
      // Tolerant read: this sits on the launch path, where a throw would be an
      // unrecoverable crash with no way for the user to clear the bad value.
      SharedPreferences.setMockInitialValues({'kiu.courseLevel': 'two'});
      final repository = SettingsRepository(
        await SharedPreferences.getInstance(),
      );

      expect(repository.courseLevel, isNull);
    });
  });

  group('AppController.recordCourseLevel', () {
    test('persists the first level it is given', () async {
      final (controller, repository) = await build();

      await controller.recordCourseLevel(2);

      expect(repository.courseLevel, 2);
      expect(controller.courseLevel, 2);
    });

    test('notifies only when the level actually changes', () async {
      final (controller, _) = await build();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.recordCourseLevel(2);
      await controller.recordCourseLevel(2);

      expect(notifications, 1);
    });
  });

  group('sign-out', () {
    test('clears the cached level so the next login re-scrapes', () async {
      final (controller, repository) = await build();
      await controller.recordCourseLevel(2);

      final result = await controller.synchronize();

      expect(result.status, ScheduleSyncStatus.signInRequired);
      expect(repository.courseLevel, isNull);
      expect(controller.courseLevel, isNull);
    });

    test('leaves the level alone while already signed out', () async {
      final (controller, repository) = await build();
      await controller.synchronize();
      // A level scraped after the app already knows it is signed out must
      // survive a second failing sync -- only the transition clears.
      await controller.recordCourseLevel(3);

      await controller.synchronize();

      expect(repository.courseLevel, 3);
    });
  });
}
