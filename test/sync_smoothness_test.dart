import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// A background sync must not repaint the browsing tree. The 10-minute
/// foreground timer fires while the user may be mid-video, and the app used to
/// rebuild the entire MaterialApp -- WebView included -- twice per sync.
Future<AppController> createController(CapturingScheduleFetcher fetcher) async {
  final repository = SettingsRepository(await SharedPreferences.getInstance());
  final notifications = FakeNotificationGateway();
  final reconciler = ReminderReconciler(
    repository: repository,
    notifications: notifications,
  );
  return AppController(
    repository: repository,
    syncService: ScheduleSyncService(
      fetcher: fetcher,
      repository: repository,
      reconciler: reconciler,
    ),
    reconciler: reconciler,
    notifications: notifications,
    scheduler: FakeBackgroundScheduler(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('overlapping syncs coalesce into a single fetch', () async {
    final fetcher = CapturingScheduleFetcher(const [
      Lesson(title: 'Tafsir', websiteStart: '2027-09-09 19:00'),
    ]);
    final controller = await createController(fetcher);

    // Exactly the resume-on-Home race: the lifecycle observer and
    // _pageFinished both start a sync in the same frame.
    final results = await Future.wait([
      controller.synchronize(),
      controller.synchronize(),
    ]);

    expect(fetcher.fetchCount, 1);
    expect(results.first.status, results.last.status);

    // A later sync still runs; the guard coalesces, it does not latch.
    await controller.synchronize();
    expect(fetcher.fetchCount, 2);
  });

  test('a routine sync does not notify the main tree', () async {
    final fetcher = CapturingScheduleFetcher(const []);
    final controller = await createController(fetcher);
    // Settle exactTiming first: the very first sync legitimately rebuilds when
    // it discovers the permission state. Steady-state is what matters here.
    await controller.synchronize();

    var mainTreeRebuilds = 0;
    controller.addListener(() => mainTreeRebuilds++);
    var syncRowRebuilds = 0;
    controller.syncState.addListener(() => syncRowRebuilds++);

    await controller.synchronize();

    expect(
      mainTreeRebuilds,
      0,
      reason: 'a sync must not rebuild the WebView subtree',
    );
    // syncing + terminal status, so the settings row still updates live.
    expect(syncRowRebuilds, greaterThanOrEqualTo(2));
  });

  test('sync state carries the status the settings row renders', () async {
    final fetcher = CapturingScheduleFetcher(const []);
    final controller = await createController(fetcher);
    final seen = <ScheduleSyncStatus>[];
    controller.syncState.addListener(
      () => seen.add(controller.syncState.value.status),
    );

    await controller.synchronize();

    expect(seen.first, ScheduleSyncStatus.syncing);
    expect(seen.last, ScheduleSyncStatus.success);
  });

  test('an exact-alarm permission change still rebuilds', () async {
    // The one piece of sync-adjacent state the main tree does render.
    final fetcher = CapturingScheduleFetcher(const []);
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    final notifications = FakeNotificationGateway()..exact = false;
    final reconciler = ReminderReconciler(
      repository: repository,
      notifications: notifications,
    );
    final controller = AppController(
      repository: repository,
      syncService: ScheduleSyncService(
        fetcher: fetcher,
        repository: repository,
        reconciler: reconciler,
      ),
      reconciler: reconciler,
      notifications: notifications,
      scheduler: FakeBackgroundScheduler(),
    );
    await controller.synchronize();

    var rebuilds = 0;
    controller.addListener(() => rebuilds++);
    notifications.exact = true;
    await controller.synchronize();

    expect(rebuilds, 1);
  });
}
