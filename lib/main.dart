import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'core/constants.dart';
import 'data/settings_repository.dart';
import 'domain/lesson.dart';
import 'services/notification_service.dart';
import 'services/lesson_widget_service.dart';
import 'services/reminder_reconciler.dart';
import 'services/schedule_fetcher.dart';
import 'services/schedule_sync_service.dart';
import 'services/time_zone_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != backgroundTaskName) return true;
    return _runBackgroundSync();
  });
}

@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null || uri.scheme != 'kiu') return;
  if (uri.host == 'widget-sync') {
    await _runBackgroundSync(force: true);
  } else if (uri.host == 'widget-call-toggle') {
    await _toggleLessonCall(uri);
  }
}

Future<void> _toggleLessonCall(Uri uri) async {
  final key = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  if (key == null || key.isEmpty) return;
  final enabled = uri.queryParameters['on'] == '1';
  WidgetsFlutterBinding.ensureInitialized();
  TimeZoneService.initialize();
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final repository = SettingsRepository(preferences);
  var settings = repository.loadSettings();
  final overrides = Map<String, bool>.from(settings.callOverrides);
  if (enabled == settings.callsEnabled) {
    overrides.remove(key);
  } else {
    overrides[key] = enabled;
  }
  settings = settings.copyWith(callOverrides: overrides);
  await repository.saveSettings(settings);
  await HomeLessonWidgetGateway().publish(
    repository.loadLessons(),
    settings,
    lastSuccessfulSync: repository.lastSuccessfulSync,
  );
}

Future<bool> _runBackgroundSync({bool force = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  TimeZoneService.initialize();
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final repository = SettingsRepository(preferences);
  if (!force && !repository.loadSettings().backgroundSyncEnabled) return true;
  var succeeded = true;
  try {
    final notifications = LocalNotificationGateway();
    await notifications.initialize();
    final lessonWidgets = HomeLessonWidgetGateway();
    final fetcher = ScheduleFetcher(cookieProvider: AndroidCookieProvider());
    final reconciler = ReminderReconciler(
      repository: repository,
      notifications: notifications,
    );
    final result = await ScheduleSyncService(
      fetcher: fetcher,
      repository: repository,
      reconciler: reconciler,
      lessonWidgets: lessonWidgets,
    ).synchronize();
    fetcher.close();
    succeeded = result.status != ScheduleSyncStatus.failed;
  } finally {
    // ponytail: this "periodic" task is really a self-chaining one-off
    // (WorkManager's real PeriodicWorkRequest can't go below 15 min). The
    // chain only survives if the next hop is always scheduled -- otherwise
    // a single throw here (e.g. plugin init failing in the background
    // isolate) permanently kills every future reminder with no recovery
    // until the app is reopened.
    if (!force) await WorkManagerScheduler.scheduleNext();
  }
  return succeeded;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TimeZoneService.initialize();
  await Workmanager().initialize(callbackDispatcher);
  await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);

  final preferences = await SharedPreferences.getInstance();
  final repository = SettingsRepository(preferences);
  final notifications = LocalNotificationGateway();
  final homeRequests = ValueNotifier<int>(0);
  final navigationRequests = ValueNotifier<Uri?>(
    await HomeWidget.initiallyLaunchedFromHomeWidget(),
  );
  HomeWidget.widgetClicked.listen((uri) {
    if (uri != null && isTrustedHttps(uri)) {
      navigationRequests.value = uri;
    }
  });
  await notifications.initialize(onTap: (_) => homeRequests.value++);
  final fetcher = ScheduleFetcher(cookieProvider: AndroidCookieProvider());
  final lessonWidgets = HomeLessonWidgetGateway();
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
      lessonWidgets: lessonWidgets,
    ),
    reconciler: reconciler,
    notifications: notifications,
    lessonWidgets: lessonWidgets,
  );
  await controller.initialize();
  runApp(
    KiuApp(
      controller: controller,
      homeRequests: homeRequests,
      navigationRequests: navigationRequests,
    ),
  );
}
