import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';
import '../domain/lesson.dart';
import '../services/update_service.dart';

class SettingsRepository {
  SettingsRepository(this._preferences);

  final SharedPreferences _preferences;

  static const _playbackRate = 'kiu.playbackRate';
  static const _themeMode = 'kiu.themeMode';
  static const _locale = 'kiu.locale';
  static const _timeZone = 'kiu.timeZone';
  static const _reminders = 'kiu.reminders';
  static const _backgroundSync = 'kiu.backgroundSync';
  static const _offsets = 'kiu.reminderOffsets';
  static const _soundUri = 'kiu.reminderSoundUri';
  static const _soundName = 'kiu.reminderSoundName';
  static const _soundOverrides = 'kiu.reminderSoundOverrides';
  static const _soundOverrideNames = 'kiu.reminderSoundOverrideNames';
  static const _legacySoundUris = 'kiu.reminderSoundUris';
  static const _callsEnabled = 'kiu.callsEnabled';
  static const _callRingSeconds = 'kiu.callRingSeconds';
  static const _callRingtoneUri = 'kiu.callRingtoneUri';
  static const _callRingtoneName = 'kiu.callRingtoneName';
  static const _callOverrides = 'kiu.callOverrides';
  static const _lessons = 'kiu.lessonSnapshot';
  static const _scheduledIds = 'kiu.scheduledNotificationIds';
  static const _lastSuccess = 'kiu.lastSyncSuccess';
  static const _syncStatus = 'kiu.syncStatus';
  static const _webViewUserAgent = 'kiu.webViewUserAgent';
  static const _backgroundExplainerShown = 'kiu.backgroundExplainerShown';
  static const _lastUpdateCheck = 'kiu.lastUpdateCheck';
  static const _skippedUpdateBuild = 'kiu.skippedUpdateBuild';
  static const _pendingUpdate = 'kiu.pendingUpdate';

  AppSettings loadSettings() => AppSettings(
    playbackRate: _preferences.getDouble(_playbackRate) ?? 1,
    themeMode:
        ThemeMode.values.asNameMap()[_preferences.getString(_themeMode)] ??
        ThemeMode.system,
    localeTag: _preferences.getString(_locale) ?? 'uz_Cyrl',
    timeZoneId: _preferences.getString(_timeZone) ?? 'Asia/Tashkent',
    remindersEnabled: _preferences.getBool(_reminders) ?? false,
    backgroundSyncEnabled: _preferences.getBool(_backgroundSync) ?? true,
    reminderOffsetsMinutes: _loadReminderOffsets(),
    reminderSoundUri: _preferences.getString(_soundUri),
    reminderSoundName: _preferences.getString(_soundName),
    reminderSoundOverrides: _loadReminderSoundOverrides(),
    reminderSoundOverrideNames: _loadSoundNames(_soundOverrideNames),
    callsEnabled: _preferences.getBool(_callsEnabled) ?? false,
    callRingSeconds: _preferences.getInt(_callRingSeconds) ?? 60,
    callRingtoneUri: _preferences.getString(_callRingtoneUri),
    callRingtoneName: _preferences.getString(_callRingtoneName),
    callOverrides: _loadCallOverrides(),
  );

  /// A single unparsable entry must not throw out of [loadSettings], which runs
  /// during cold start and in the background isolate. Same tolerant read as
  /// [loadScheduledIds].
  List<int> _loadReminderOffsets() {
    final raw = _preferences.getStringList(_offsets);
    if (raw == null) return const [60, 0];
    return raw.map(int.tryParse).whereType<int>().toList();
  }

  Map<String, bool> _loadCallOverrides() {
    final raw = _preferences.getString(_callOverrides);
    if (raw == null) return const {};
    try {
      final values = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in values.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
    } on FormatException {
      return const {};
    } on TypeError {
      return const {};
    }
  }

  Map<int, String> _loadReminderSoundOverrides() =>
      _loadSoundNames(_soundOverrides, fallbackKey: _legacySoundUris);

  Map<int, String> _loadSoundNames(String key, {String? fallbackKey}) {
    final raw =
        _preferences.getString(key) ??
        (fallbackKey == null ? null : _preferences.getString(fallbackKey));
    if (raw == null) return const {};
    try {
      final values = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in values.entries)
          if (int.tryParse(entry.key) case final offset?)
            if (entry.value is String && (entry.value as String).isNotEmpty)
              offset: entry.value as String,
      };
    } on FormatException {
      return const {};
    } on TypeError {
      return const {};
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await Future.wait([
      _preferences.setDouble(_playbackRate, settings.playbackRate),
      _preferences.setString(_themeMode, settings.themeMode.name),
      _preferences.setString(_locale, settings.localeTag),
      _preferences.setString(_timeZone, settings.timeZoneId),
      _preferences.setBool(_reminders, settings.remindersEnabled),
      _preferences.setBool(_backgroundSync, settings.backgroundSyncEnabled),
      _preferences.setStringList(
        _offsets,
        settings.reminderOffsetsMinutes.map((value) => '$value').toList(),
      ),
      _preferences.setString(
        _soundOverrides,
        jsonEncode({
          for (final entry in settings.reminderSoundOverrides.entries)
            '${entry.key}': entry.value,
        }),
      ),
      _preferences.setString(
        _soundOverrideNames,
        jsonEncode({
          for (final entry in settings.reminderSoundOverrideNames.entries)
            '${entry.key}': entry.value,
        }),
      ),
      // Write-or-remove, never skip: skipping would make a cleared sound
      // silently resurrect the previous value on the next load.
      _writeOrRemove(_soundUri, settings.reminderSoundUri),
      _writeOrRemove(_soundName, settings.reminderSoundName),
      _preferences.remove(_legacySoundUris),
      _preferences.setBool(_callsEnabled, settings.callsEnabled),
      _preferences.setInt(_callRingSeconds, settings.callRingSeconds),
      _preferences.setString(
        _callOverrides,
        jsonEncode(settings.callOverrides),
      ),
      _writeOrRemove(_callRingtoneUri, settings.callRingtoneUri),
      _writeOrRemove(_callRingtoneName, settings.callRingtoneName),
    ]);
  }

  Future<bool> _writeOrRemove(String key, String? value) => value == null
      ? _preferences.remove(key)
      : _preferences.setString(key, value);

  /// Drops call overrides for occurrences no longer in the schedule so the
  /// map cannot grow without bound as recurring lessons churn.
  Future<void> pruneCallOverrides(Set<String> liveKeys) async {
    final overrides = _loadCallOverrides();
    final pruned = {
      for (final entry in overrides.entries)
        if (liveKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (pruned.length == overrides.length) return;
    await _preferences.setString(_callOverrides, jsonEncode(pruned));
  }

  List<Lesson> loadLessons() {
    final raw = _preferences.getString(_lessons);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(Lesson.tryFromJson)
          .whereType<Lesson>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveLessons(List<Lesson> lessons) => _preferences.setString(
    _lessons,
    jsonEncode(lessons.map((lesson) => lesson.toJson()).toList()),
  );

  Set<int> loadScheduledIds() =>
      (_preferences.getStringList(_scheduledIds) ?? const [])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();

  Future<void> saveScheduledIds(Set<int> ids) => _preferences.setStringList(
    _scheduledIds,
    ids.map((id) => '$id').toList()..sort(),
  );

  DateTime? get lastSuccessfulSync =>
      DateTime.tryParse(_preferences.getString(_lastSuccess) ?? '');

  String? get webViewUserAgent => _preferences.getString(_webViewUserAgent);

  Future<void> saveWebViewUserAgent(String value) =>
      _preferences.setString(_webViewUserAgent, value);

  bool get backgroundExplainerShown =>
      _preferences.getBool(_backgroundExplainerShown) ?? false;

  Future<void> markBackgroundExplainerShown() =>
      _preferences.setBool(_backgroundExplainerShown, true);

  /// When the updater last got an answer from GitHub. `tryParse` rather than
  /// `parse`: this is read on the path that gates the whole app, and a corrupt
  /// value must degrade to "never checked", not throw.
  DateTime? get lastUpdateCheck =>
      DateTime.tryParse(_preferences.getString(_lastUpdateCheck) ?? '');

  Future<void> recordUpdateCheck(DateTime value) =>
      _preferences.setString(_lastUpdateCheck, value.toIso8601String());

  /// The build the user dismissed, so an optional update stops nagging. Never
  /// consulted for a mandatory one.
  int get skippedUpdateBuild => _preferences.getInt(_skippedUpdateBuild) ?? 0;

  Future<void> skipUpdateBuild(int build) =>
      _preferences.setInt(_skippedUpdateBuild, build);

  /// The update found by the last check, so a mandatory one survives a restart
  /// -- otherwise closing the app is a way around the gate.
  ///
  /// Decoded tolerantly: this runs on the launch path, where a throw is an
  /// unrecoverable crash with no way for the user to clear the bad value.
  AppUpdate? get pendingUpdate {
    final raw = _preferences.getString(_pendingUpdate);
    if (raw == null) return null;
    try {
      return AppUpdate.tryFromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> savePendingUpdate(AppUpdate? update) => update == null
      ? _preferences.remove(_pendingUpdate)
      : _preferences.setString(_pendingUpdate, jsonEncode(update.toJson()));

  Future<void> recordSuccess(DateTime value) async {
    await _preferences.setString(_lastSuccess, value.toIso8601String());
    await _preferences.setString(_syncStatus, 'success');
  }

  Future<void> recordStatus(String value) =>
      _preferences.setString(_syncStatus, value);
}
