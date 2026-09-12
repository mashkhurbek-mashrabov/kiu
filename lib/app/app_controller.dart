import 'package:flutter/material.dart';
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
  // Cached rather than queried inline by the UI: unlike [_notifications],
  // [_backgroundAccess] has no fake wired through the widget tests, and an
  // unmocked platform channel call made while building UI never resolves in
  // a widget test. Refreshed explicitly via [refreshFullScreenIntentAccess].
  bool canUseFullScreenIntent = true;
  // Cached for the same reason as [canUseFullScreenIntent] above.
  bool canDrawOverlays = true;
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
    // Cold start must not depend on the WebView reaching the lessons page or
    // on a background WorkManager chain that may have died: re-arm cached
    // reminders against current time/permission state every launch.
    await _rescheduleCached();
    await _refreshWidget();
    notifyListeners();
  }

  Future<void> setPlaybackRate(double value) async {
    settings = settings.copyWith(playbackRate: value.clamp(0.5, 4.0));
    await _repository.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    settings = settings.copyWith(themeMode: value);
    await _repository.saveSettings(settings);
    // The home-screen widget is themed from published data, not from the
    // system night-mode qualifier, so it needs a republish here.
    await _refreshWidget();
    notifyListeners();
  }

  /// Republishes widget data after something outside settings changed how it
  /// should look, e.g. the OS flipped night mode while the app follows it.
  Future<void> refreshWidget() => _refreshWidget();

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

  Future<void> openFullScreenIntentSettings() async {
    await _backgroundAccess.openFullScreenIntentSettings();
    await refreshFullScreenIntentAccess();
  }

  Future<void> refreshFullScreenIntentAccess() async {
    canUseFullScreenIntent = await _backgroundAccess.canUseFullScreenIntent();
    notifyListeners();
  }

  Future<void> openOverlaySettings() async {
    await _backgroundAccess.openOverlaySettings();
    await refreshOverlayAccess();
  }

  Future<void> refreshOverlayAccess() async {
    canDrawOverlays = await _backgroundAccess.canDrawOverlays();
    notifyListeners();
  }

  Future<bool> setCallsEnabled(bool enabled) async {
    if (enabled && !await _notifications.requestNotificationPermission()) {
      return false;
    }
    settings = settings.copyWith(callsEnabled: enabled);
    await _repository.saveSettings(settings);
    await _refreshWidget();
    notifyListeners();
    return true;
  }

  Future<void> setCallRingSeconds(int seconds) async {
    settings = settings.copyWith(callRingSeconds: seconds.clamp(10, 300));
    await _repository.saveSettings(settings);
    await _refreshWidget();
    notifyListeners();
  }

  Future<void> selectCallRingtone() async {
    final sound = await _notifications.selectSound(
      currentSound: settings.callRingtoneUri,
      ringtone: true,
    );
    if (sound == null) return;
    settings = settings.copyWith(
      callRingtoneUri: sound.uri,
      callRingtoneName: sound.name,
    );
    await _repository.saveSettings(settings);
    await _refreshWidget();
    notifyListeners();
  }

  Future<void> setLessonCallEnabled(Lesson lesson, bool enabled) async {
    final overrides = Map<String, bool>.from(settings.callOverrides);
    if (enabled == settings.callsEnabled) {
      overrides.remove(lesson.callKey);
    } else {
      overrides[lesson.callKey] = enabled;
    }
    settings = settings.copyWith(callOverrides: overrides);
    await _repository.saveSettings(settings);
    await _refreshWidget();
    notifyListeners();
  }

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
    settings = settings.copyWith(
      reminderSoundUri: sound.uri,
      reminderSoundName: sound.name,
    );
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
      ..[offsetMinutes] = sound.uri;
    final names = Map<int, String>.from(settings.reminderSoundOverrideNames)
      ..[offsetMinutes] = sound.name;
    settings = settings.copyWith(
      reminderSoundOverrides: sounds,
      reminderSoundOverrideNames: names,
    );
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    notifyListeners();
  }

  Future<void> clearReminderSoundOverride(int offsetMinutes) async {
    final sounds = Map<int, String>.from(settings.reminderSoundOverrides)
      ..remove(offsetMinutes);
    final names = Map<int, String>.from(settings.reminderSoundOverrideNames)
      ..remove(offsetMinutes);
    settings = settings.copyWith(
      reminderSoundOverrides: sounds,
      reminderSoundOverrideNames: names,
    );
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
