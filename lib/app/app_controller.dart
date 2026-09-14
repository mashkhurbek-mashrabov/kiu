import 'dart:async';

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
import '../services/update_service.dart';

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
    UpdateChecker? updateChecker,
  }) : _repository = repository,
       _syncService = syncService,
       _reconciler = reconciler,
       _notifications = notifications,
       _scheduler = scheduler ?? WorkManagerScheduler(),
       _appVersionProvider = appVersionProvider ?? AndroidAppVersionProvider(),
       _backgroundAccess = backgroundAccess ?? AndroidBackgroundAccessGateway(),
       _lessonWidgets = lessonWidgets,
       _updateChecker = updateChecker,
       settings = repository.loadSettings(),
       lastSuccessfulSync = repository.lastSuccessfulSync,
       lastUpdateCheck = repository.lastUpdateCheck;

  final SettingsRepository _repository;
  final ScheduleSyncService _syncService;
  final ReminderReconciler _reconciler;
  final NotificationGateway _notifications;
  final BackgroundScheduler _scheduler;
  final AppVersionProvider _appVersionProvider;
  final BackgroundAccessGateway _backgroundAccess;
  final LessonWidgetGateway? _lessonWidgets;
  final UpdateChecker? _updateChecker;

  AppSettings settings;
  ScheduleSyncStatus syncStatus = ScheduleSyncStatus.idle;
  DateTime? lastSuccessfulSync;
  DateTime? lastUpdateCheck;

  /// Sync progress is published here rather than through [notifyListeners] so
  /// the 10-minute background sync cannot rebuild the whole app -- including
  /// the WebView -- while the user is reading or watching a lesson. Only the
  /// settings sheet renders this.
  late final ValueNotifier<
    ({ScheduleSyncStatus status, DateTime? lastSuccessfulSync})
  >
  syncState = ValueNotifier((
    status: ScheduleSyncStatus.idle,
    lastSuccessfulSync: lastSuccessfulSync,
  ));

  /// The update offer, rendered by the gate and the settings row.
  ///
  /// A [ValueNotifier] for the same reason as [syncState]: a routine check
  /// firing on resume must not rebuild `KiuApp` and tear down the WebView.
  /// A *mandatory* update is the one exception -- see [checkForUpdate].
  late final ValueNotifier<AppUpdate?> availableUpdate = ValueNotifier(null);

  /// Published separately so the settings row can re-render the "last checked"
  /// time without the whole tree rebuilding.
  late final ValueNotifier<DateTime?> updateCheckState = ValueNotifier(
    lastUpdateCheck,
  );

  Future<void>? _inFlightUpdateCheck;
  static const _updateCheckInterval = Duration(hours: 6);

  Future<SyncResult>? _inFlightSync;
  bool exactTiming = false;
  // Cached rather than queried inline by the UI: unlike [_notifications],
  // [_backgroundAccess] has no fake wired through the widget tests, and an
  // unmocked platform channel call made while building UI never resolves in
  // a widget test. Refreshed explicitly via [refreshBackgroundAccess].
  bool canUseFullScreenIntent = true;
  // Cached for the same reason as [canUseFullScreenIntent] above.
  bool canDrawOverlays = true;
  // Same caching rationale. Defaults to true so the settings row does not
  // flash a red "not granted" badge during the channel round trip.
  bool batteryOptimizationDisabled = true;
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
    // Unawaited on purpose: a slow or hanging GitHub request must never hold
    // up cold start. The gate appears when the answer arrives.
    unawaited(checkForUpdate());
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

  /// Re-queries every permission the user can only change in Android settings.
  ///
  /// Opening a settings screen returns as soon as the activity starts, long
  /// before the user grants anything, so the open* methods cannot refresh
  /// their own state. Resuming is the first moment the answer can differ.
  Future<void> refreshBackgroundAccess() async {
    final results = await Future.wait([
      _backgroundAccess.isBatteryOptimizationDisabled(),
      _backgroundAccess.canUseFullScreenIntent(),
      _backgroundAccess.canDrawOverlays(),
    ]);
    batteryOptimizationDisabled = results[0];
    canUseFullScreenIntent = results[1];
    canDrawOverlays = results[2];
    notifyListeners();
  }

  Future<void> openBatteryOptimizationSettings() =>
      _backgroundAccess.openBatteryOptimizationSettings();

  Future<void> openFullScreenIntentSettings() =>
      _backgroundAccess.openFullScreenIntentSettings();

  Future<void> openOverlaySettings() => _backgroundAccess.openOverlaySettings();

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

  /// Drops the custom main reminder sound, falling back to the system default.
  Future<void> clearReminderSound() async {
    settings = settings.copyWith(
      reminderSoundUri: null,
      reminderSoundName: null,
    );
    await _repository.saveSettings(settings);
    await _rescheduleCached();
    notifyListeners();
  }

  /// Drops the custom call ringtone, falling back to the system default.
  Future<void> clearCallRingtone() async {
    settings = settings.copyWith(callRingtoneUri: null, callRingtoneName: null);
    await _repository.saveSettings(settings);
    await _refreshWidget();
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

  /// Coalesces overlapping syncs. Resuming the app while Home is open used to
  /// start one sync from the lifecycle observer and a second from
  /// `_pageFinished`, running two fetches, two reconciles, and two widget
  /// publishes at once on the page the user is looking at.
  Future<SyncResult> synchronize({String? userAgent}) {
    return _inFlightSync ??= _synchronize(userAgent: userAgent)
        .whenComplete(() {
          _inFlightSync = null;
        });
  }

  Future<SyncResult> _synchronize({String? userAgent}) async {
    _setSyncStatus(ScheduleSyncStatus.syncing);
    final result = await _syncService.synchronize(userAgent: userAgent);
    if (result.status == ScheduleSyncStatus.success) {
      lastSuccessfulSync = _repository.lastSuccessfulSync;
    }
    final previousExactTiming = exactTiming;
    exactTiming = await _notifications.canScheduleExactly();
    _setSyncStatus(result.status);
    // Only an exact-alarm permission flip changes anything the main tree
    // renders; a routine sync must not rebuild it (and the WebView with it).
    if (exactTiming != previousExactTiming) notifyListeners();
    return result;
  }

  /// Asks GitHub whether a newer release exists.
  ///
  /// Throttled to [_updateCheckInterval] unless [force], so the resume hook can
  /// fire freely without hammering the unauthenticated API (60 req/hour/IP).
  /// Overlapping calls coalesce the way [synchronize] does -- cold start and a
  /// resume in the same second must not produce two requests.
  Future<void> checkForUpdate({bool force = false}) {
    return _inFlightUpdateCheck ??= _checkForUpdate(force: force)
        .whenComplete(() {
          _inFlightUpdateCheck = null;
        });
  }

  Future<void> _checkForUpdate({required bool force}) async {
    final checker = _updateChecker;
    final version = appVersion;
    if (checker == null || version == null) return;
    final last = lastUpdateCheck;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _updateCheckInterval) {
      return;
    }

    final result = await checker.check(
      installedBuild: version.code,
      abi: version.abi,
    );

    // Only a real answer advances the timestamp. Recording a failed check would
    // silence the updater for six hours every time the user opens the app
    // offline -- and would show a "last checked" time that never happened.
    if (!result.answered) return;
    lastUpdateCheck = DateTime.now();
    await _repository.recordUpdateCheck(lastUpdateCheck!);
    updateCheckState.value = lastUpdateCheck;

    final update = result.update;
    // A dismissed optional build stays dismissed; a mandatory one ignores it.
    if (update != null &&
        !update.mandatory &&
        update.buildNumber <= _repository.skippedUpdateBuild) {
      return;
    }
    availableUpdate.value = update;
    // The gate is main-tree state that KiuApp itself renders, so this one
    // transition has to rebuild -- unlike every other notifier here.
    if (update != null && update.mandatory) notifyListeners();
  }

  /// Dismisses an optional update so it stops prompting on every resume.
  Future<void> skipUpdate(AppUpdate update) async {
    if (update.mandatory) return;
    await _repository.skipUpdateBuild(update.buildNumber);
    availableUpdate.value = null;
  }

  void _setSyncStatus(ScheduleSyncStatus status) {
    syncStatus = status;
    syncState.value = (status: status, lastSuccessfulSync: lastSuccessfulSync);
  }

  @override
  void dispose() {
    syncState.dispose();
    availableUpdate.dispose();
    updateCheckState.dispose();
    super.dispose();
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
