import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import '../core/constants.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';
import '../domain/lesson.dart';
import '../services/app_version_service.dart';
import '../services/background_access_service.dart';
import '../services/lesson_widget_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_reconciler.dart';
import '../services/schedule_sync_service.dart';

abstract interface class BackgroundScheduler {
  Future<void> setEnabled(bool enabled);
}

class WorkManagerScheduler implements BackgroundScheduler {
  static const _interval = Duration(minutes: 5);

  static Future<void> scheduleNext() => Workmanager().registerOneOffTask(
    backgroundTaskUniqueName,
    backgroundTaskName,
    initialDelay: _interval,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.update,
  );

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await Workmanager().cancelByUniqueName(backgroundTaskUniqueName);
      await scheduleNext();
    } else {
      await Workmanager().cancelByUniqueName(backgroundTaskUniqueName);
    }
  }
}

class AppController extends ChangeNotifier {
  AppController({
    required SettingsRepository repository,
    required ScheduleSyncService syncService,
    required ReminderReconciler reconciler,
    required NotificationGateway notifications,
    BackgroundScheduler? scheduler,
    AppVersionProvider? appVersionProvider,
    BackgroundAccessGateway? backgroundAccess,
    LessonWidgetGateway? lessonWidgets,
  }) : _repository = repository,
       _syncService = syncService,
       _reconciler = reconciler,
       _notifications = notifications,
       _scheduler = scheduler ?? WorkManagerScheduler(),
       _appVersionProvider = appVersionProvider ?? AndroidAppVersionProvider(),
       _backgroundAccess = backgroundAccess ?? AndroidBackgroundAccessGateway(),
       _lessonWidgets = lessonWidgets,
       settings = repository.loadSettings(),
       lastSuccessfulSync = repository.lastSuccessfulSync;

  final SettingsRepository _repository;
  final ScheduleSyncService _syncService;
  final ReminderReconciler _reconciler;
  final NotificationGateway _notifications;
  final BackgroundScheduler _scheduler;
  final AppVersionProvider _appVersionProvider;
  final BackgroundAccessGateway _backgroundAccess;
  final LessonWidgetGateway? _lessonWidgets;

  AppSettings settings;
  ScheduleSyncStatus syncStatus = ScheduleSyncStatus.idle;
  DateTime? lastSuccessfulSync;
  bool exactTiming = false;
  AppVersion? appVersion;

  List<Lesson> get scheduledLessons => _repository.loadLessons();

  Future<void> initialize() async {
    try {
      appVersion = await _appVersionProvider.read();
    } on PlatformException {
      appVersion = null;
    } on MissingPluginException {
      appVersion = null;
    }
    exactTiming = await _notifications.canScheduleExactly();
    await _scheduler.setEnabled(settings.backgroundSyncEnabled);
    await _refreshWidget();
    notifyListeners();
  }

  Future<void> setPlaybackRate(double value) async {
    settings = settings.copyWith(playbackRate: value.clamp(0.25, 4.0));
    await _repository.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    settings = settings.copyWith(localeTag: value);
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    await _refreshWidget();
    notifyListeners();
  }

  Future<void> setTimeZone(String value) async {
    settings = settings.copyWith(timeZoneId: value);
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    await _refreshWidget();
    notifyListeners();
  }

  Future<bool> setRemindersEnabled(bool enabled) async {
    if (enabled && !await _notifications.requestNotificationPermission()) {
      return false;
    }
    settings = settings.copyWith(remindersEnabled: enabled);
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    notifyListeners();
    return true;
  }

  Future<void> setBackgroundSyncEnabled(bool enabled) async {
    settings = settings.copyWith(backgroundSyncEnabled: enabled);
    await _repository.saveSettings(settings);
    await _scheduler.setEnabled(enabled);
    notifyListeners();
  }

  bool get shouldShowBackgroundExplainer =>
      settings.backgroundSyncEnabled && !_repository.backgroundExplainerShown;

  Future<void> markBackgroundExplainerShown() =>
      _repository.markBackgroundExplainerShown();

  Future<bool> isBatteryOptimizationDisabled() =>
      _backgroundAccess.isBatteryOptimizationDisabled();

  Future<void> openBatteryOptimizationSettings() =>
      _backgroundAccess.openBatteryOptimizationSettings();

  Future<void> setReminderOffsets(List<int> values) async {
    final normalized = values.toSet().where((value) {
      return value >= 0 && value <= 10080;
    }).toList()..sort((a, b) => b.compareTo(a));
    settings = settings.copyWith(reminderOffsetsMinutes: normalized);
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    notifyListeners();
  }

  Future<void> selectMainReminderSound() async {
    final sound = await _notifications.selectSound(
      currentSound: settings.reminderSoundUri,
    );
    if (sound == null) return;
    settings = settings.copyWith(reminderSoundUri: sound);
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    notifyListeners();
  }

  Future<void> selectReminderSoundOverride(int offsetMinutes) async {
    final currentSound =
        settings.reminderSoundOverrides[offsetMinutes] ??
        settings.reminderSoundUri;
    final sound = await _notifications.selectSound(currentSound: currentSound);
    if (sound == null) return;
    final sounds = Map<int, String>.from(settings.reminderSoundOverrides)
      ..[offsetMinutes] = sound;
    settings = settings.copyWith(reminderSoundOverrides: sounds);
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    notifyListeners();
  }

  Future<void> clearReminderSoundOverride(int offsetMinutes) async {
    final sounds = Map<int, String>.from(settings.reminderSoundOverrides)
      ..remove(offsetMinutes);
    settings = settings.copyWith(reminderSoundOverrides: sounds);
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    notifyListeners();
  }

  Future<void> requestExactTiming() async {
    await _notifications.requestExactAlarmPermission();
    exactTiming = await _notifications.canScheduleExactly();
    await _rescheduleCached();
    notifyListeners();
  }

  Future<SyncResult> synchronize({String? userAgent}) async {
    syncStatus = ScheduleSyncStatus.syncing;
    notifyListeners();
    final result = await _syncService.synchronize(userAgent: userAgent);
    syncStatus = result.status;
    if (result.status == ScheduleSyncStatus.success) {
      lastSuccessfulSync = _repository.lastSuccessfulSync;
    }
    exactTiming = await _notifications.canScheduleExactly();
    notifyListeners();
    return result;
  }

  Future<void> _rescheduleCached() =>
      _reconciler.reconcile(_repository.loadLessons(), settings);

  Future<void> _refreshWidget() =>
      _lessonWidgets?.publish(
        _repository.loadLessons(),
        settings,
        lastSuccessfulSync: _repository.lastSuccessfulSync,
      ) ??
      Future<void>.value();
}
