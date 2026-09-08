import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';
import '../domain/lesson.dart';

class SettingsRepository {
  SettingsRepository(this._preferences);

  final SharedPreferences _preferences;

  static const _playbackRate = 'kiu.playbackRate';
  static const _locale = 'kiu.locale';
  static const _timeZone = 'kiu.timeZone';
  static const _reminders = 'kiu.reminders';
  static const _backgroundSync = 'kiu.backgroundSync';
  static const _offsets = 'kiu.reminderOffsets';
  static const _soundUris = 'kiu.reminderSoundUris';
  static const _lessons = 'kiu.lessonSnapshot';
  static const _scheduledIds = 'kiu.scheduledNotificationIds';
  static const _lastAttempt = 'kiu.lastSyncAttempt';
  static const _lastSuccess = 'kiu.lastSyncSuccess';
  static const _syncStatus = 'kiu.syncStatus';
  static const _webViewUserAgent = 'kiu.webViewUserAgent';
  static const _backgroundExplainerShown = 'kiu.backgroundExplainerShown';

  AppSettings loadSettings() => AppSettings(
    playbackRate: _preferences.getDouble(_playbackRate) ?? 1,
    localeTag: _preferences.getString(_locale) ?? 'uz_Cyrl',
    timeZoneId: _preferences.getString(_timeZone) ?? 'Asia/Tashkent',
    remindersEnabled: _preferences.getBool(_reminders) ?? false,
    backgroundSyncEnabled: _preferences.getBool(_backgroundSync) ?? true,
    reminderOffsetsMinutes:
        _preferences.getStringList(_offsets)?.map(int.parse).toList() ??
        const [60, 0],
    reminderSoundUris: _loadReminderSoundUris(),
  );

  Map<int, String> _loadReminderSoundUris() {
    final raw = _preferences.getString(_soundUris);
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
      _preferences.setString(_locale, settings.localeTag),
      _preferences.setString(_timeZone, settings.timeZoneId),
      _preferences.setBool(_reminders, settings.remindersEnabled),
      _preferences.setBool(_backgroundSync, settings.backgroundSyncEnabled),
      _preferences.setStringList(
        _offsets,
        settings.reminderOffsetsMinutes.map((value) => '$value').toList(),
      ),
      _preferences.setString(
        _soundUris,
        jsonEncode({
          for (final entry in settings.reminderSoundUris.entries)
            '${entry.key}': entry.value,
        }),
      ),
    ]);
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
