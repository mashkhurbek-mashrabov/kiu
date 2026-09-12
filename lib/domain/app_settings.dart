import 'package:flutter/material.dart';

import 'lesson.dart';

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
    this.callsEnabled = false,
    this.callRingSeconds = 60,
    this.callRingtoneUri,
    this.callRingtoneName,
    this.callOverrides = const {},
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
  final bool callsEnabled;
  final int callRingSeconds;
  final String? callRingtoneUri;
  final String? callRingtoneName;
  final Map<String, bool> callOverrides;

  Locale get locale {
    final parts = localeTag.split('_');
    return parts.length == 2
        ? Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1])
        : Locale(parts[0]);
  }

  /// Whether lesson calls should ring for this specific occurrence, honoring
  /// a per-occurrence override over the global switch.
  bool callEnabledFor(Lesson lesson) =>
      callOverrides[lesson.callKey] ?? callsEnabled;

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
    bool? callsEnabled,
    int? callRingSeconds,
    String? callRingtoneUri,
    String? callRingtoneName,
    Map<String, bool>? callOverrides,
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
    callsEnabled: callsEnabled ?? this.callsEnabled,
    callRingSeconds: callRingSeconds ?? this.callRingSeconds,
    callRingtoneUri: callRingtoneUri ?? this.callRingtoneUri,
    callRingtoneName: callRingtoneName ?? this.callRingtoneName,
    callOverrides: callOverrides ?? this.callOverrides,
  );
}
