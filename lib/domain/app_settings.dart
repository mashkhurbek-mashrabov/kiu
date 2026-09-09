import 'package:flutter/material.dart';

class AppSettings {
  const AppSettings({
    this.playbackRate = 1,
    this.localeTag = 'uz_Cyrl',
    this.timeZoneId = 'Asia/Tashkent',
    this.remindersEnabled = false,
    this.backgroundSyncEnabled = true,
    this.reminderOffsetsMinutes = const [60, 0],
    this.reminderSoundUri,
    this.reminderSoundName,
    this.reminderSoundOverrides = const {},
    this.reminderSoundOverrideNames = const {},
  });

  final double playbackRate;
  final String localeTag;
  final String timeZoneId;
  final bool remindersEnabled;
  final bool backgroundSyncEnabled;
  final List<int> reminderOffsetsMinutes;
  final String? reminderSoundUri;
  final String? reminderSoundName;
  final Map<int, String> reminderSoundOverrides;
  final Map<int, String> reminderSoundOverrideNames;

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
    String? reminderSoundUri,
    String? reminderSoundName,
    Map<int, String>? reminderSoundOverrides,
    Map<int, String>? reminderSoundOverrideNames,
  }) => AppSettings(
    playbackRate: playbackRate ?? this.playbackRate,
    localeTag: localeTag ?? this.localeTag,
    timeZoneId: timeZoneId ?? this.timeZoneId,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    backgroundSyncEnabled: backgroundSyncEnabled ?? this.backgroundSyncEnabled,
    reminderOffsetsMinutes:
        reminderOffsetsMinutes ?? this.reminderOffsetsMinutes,
    reminderSoundUri: reminderSoundUri ?? this.reminderSoundUri,
    reminderSoundName: reminderSoundName ?? this.reminderSoundName,
    reminderSoundOverrides:
        reminderSoundOverrides ?? this.reminderSoundOverrides,
    reminderSoundOverrideNames:
        reminderSoundOverrideNames ?? this.reminderSoundOverrideNames,
  );
}
