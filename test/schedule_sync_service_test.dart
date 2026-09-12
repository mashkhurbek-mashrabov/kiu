import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  test(
    'persists matching WebView user agent and publishes successful snapshot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      const lessons = [
        Lesson(title: 'Tafsir', websiteStart: '2027-09-09 19:00'),
      ];
      final fetcher = CapturingScheduleFetcher(lessons);
      final widgets = FakeLessonWidgetGateway();
      final notifications = FakeNotificationGateway();
      final service = ScheduleSyncService(
        fetcher: fetcher,
        repository: repository,
        reconciler: ReminderReconciler(
          repository: repository,
          notifications: notifications,
        ),
        lessonWidgets: widgets,
      );

      final result = await service.synchronize(userAgent: 'WebView UA');

      expect(result.status, ScheduleSyncStatus.success);
      expect(fetcher.userAgent, 'WebView UA');
      expect(repository.webViewUserAgent, 'WebView UA');
      expect(widgets.lessons, lessons);
      expect(widgets.lastSuccessfulSync, repository.lastSuccessfulSync);
      expect(widgets.statusHistory, [ScheduleSyncStatus.syncing]);
      expect(widgets.status, isNull);
    },
  );

  test('fetches the schedule in the saved app language', () async {
    SharedPreferences.setMockInitialValues({'kiu.locale': 'ru'});
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    final fetcher = CapturingScheduleFetcher(const []);
    final notifications = FakeNotificationGateway();
    final service = ScheduleSyncService(
      fetcher: fetcher,
      repository: repository,
      reconciler: ReminderReconciler(
        repository: repository,
        notifications: notifications,
      ),
    );

    await service.synchronize();

    expect(fetcher.localeTag, 'ru');
    expect(homeUrlFor(fetcher.localeTag!), contains('/ru/'));
  });
}
