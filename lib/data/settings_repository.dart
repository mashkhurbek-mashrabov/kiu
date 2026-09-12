import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';
import '../domain/lesson.dart';

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
  static const _lastAttempt = 'kiu.lastSyncAttempt';
  static const _lastSuccess = 'kiu.lastSyncSuccess';
  static const _syncStatus = 'kiu.syncStatus';
  static const _webViewUserAgent = 'kiu.webViewUserAgent';
  static const _backgroundExplainerShown = 'kiu.backgroundExplainerShown';

  AppSettings loadSettings() => AppSettings(
    playbackRate: _preferences.getDouble(_playbackRate) ?? 1,
    themeMode:
        ThemeMode.values.asNameMap()[_preferences.getString(_themeMode)] ??
        ThemeMode.system,
    localeTag: _preferences.getString(_locale) ?? 'uz_Cyrl',
    timeZoneId: _preferences.getString(_timeZone) ?? 'Asia/Tashkent',
    remindersEnabled: _preferences.getBool(_reminders) ?? false,
    backgroundSyncEnabled: _preferences.getBool(_backgroundSync) ?? true,
    reminderOffsetsMinutes:
        _preferences.getStringList(_offsets)?.map(int.parse).toList() ??
        const [60, 0],
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
      if (settings.reminderSoundUri != null)
        _preferences.setString(_soundUri, settings.reminderSoundUri!),
      if (settings.reminderSoundName != null)
        _preferences.setString(_soundName, settings.reminderSoundName!),
      _preferences.remove(_legacySoundUris),
      _preferences.setBool(_callsEnabled, settings.callsEnabled),
      _preferences.setInt(_callRingSeconds, settings.callRingSeconds),
      _preferences.setString(
        _callOverrides,
        jsonEncode(settings.callOverrides),
      ),
      if (settings.callRingtoneUri != null)
        _preferences.setString(_callRingtoneUri, settings.callRingtoneUri!),
      if (settings.callRingtoneName != null)
        _preferences.setString(_callRingtoneName, settings.callRingtoneName!),
    ]);
  }

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
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => Lesson.fromJson(item as Map<String, dynamic>))
          .toList();
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

  String get syncStatus => _preferences.getString(_syncStatus) ?? 'idle';

  String? get webViewUserAgent => _preferences.getString(_webViewUserAgent);

  Future<void> saveWebViewUserAgent(String value) =>
      _preferences.setString(_webViewUserAgent, value);

  bool get backgroundExplainerShown =>
      _preferences.getBool(_backgroundExplainerShown) ?? false;

  Future<void> markBackgroundExplainerShown() =>
      _preferences.setBool(_backgroundExplainerShown, true);

  Future<void> recordAttempt() =>
      _preferences.setString(_lastAttempt, DateTime.now().toIso8601String());

  Future<void> recordSuccess(DateTime value) async {
    await _preferences.setString(_lastSuccess, value.toIso8601String());
    await _preferences.setString(_syncStatus, 'success');
  }

  Future<void> recordStatus(String value) =>
      _preferences.setString(_syncStatus, value);
}
