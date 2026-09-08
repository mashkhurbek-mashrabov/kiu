import 'package:flutter/material.dart';

class AppSettings {
  const AppSettings({
    this.playbackRate = 1,
    this.localeTag = 'uz_Cyrl',
    this.timeZoneId = 'Asia/Tashkent',
    this.remindersEnabled = false,
    this.backgroundSyncEnabled = true,
    this.reminderOffsetsMinutes = const [60, 0],
  });

  final double playbackRate;
  final String localeTag;
  final String timeZoneId;
  final bool remindersEnabled;
  final bool backgroundSyncEnabled;
  final List<int> reminderOffsetsMinutes;

  Locale get locale {
    final parts = localeTag.split('_');
    return parts.length == 2
        ? Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1])
        : Locale(parts[0]);
  }

  AppSettings copyWith({
    double? playbackRate,
    String? localeTag,
    String? timeZoneId,
    bool? remindersEnabled,
    bool? backgroundSyncEnabled,
    List<int>? reminderOffsetsMinutes,
  }) => AppSettings(
    playbackRate: playbackRate ?? this.playbackRate,
    localeTag: localeTag ?? this.localeTag,
    timeZoneId: timeZoneId ?? this.timeZoneId,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    backgroundSyncEnabled: backgroundSyncEnabled ?? this.backgroundSyncEnabled,
    reminderOffsetsMinutes:
        reminderOffsetsMinutes ?? this.reminderOffsetsMinutes,
  );
}
