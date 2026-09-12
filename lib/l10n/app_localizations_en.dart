// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'KIU';

  @override
  String get back => 'Back';

  @override
  String get forward => 'Forward';

  @override
  String get home => 'Home';

  @override
  String get refresh => 'Refresh';

  @override
  String get actions => 'Actions';

  @override
  String get version => 'Version';

  @override
  String get videoSpeed => 'Video speed';

  @override
  String get customSpeed => 'Custom speed';

  @override
  String get markWatched => 'Mark as watched';

  @override
  String get markWatchedQuestion => 'Mark this lesson as watched?';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get marking => 'Marking…';

  @override
  String get marked => 'Lesson marked as watched';

  @override
  String get markFailed => 'Could not mark the lesson';

  @override
  String get onlyLesson => 'This action is available only on a video lesson';

  @override
  String get notificationSettings => 'Notification settings';

  @override
  String get reminders => 'Lesson reminders';

  @override
  String get remindersHelp =>
      'Checks for schedule changes in the background about every 5 minutes';

  @override
  String get threeHours => '3 hours before';

  @override
  String get oneHour => '1 hour before';

  @override
  String get fifteenMinutes => '15 minutes before';

  @override
  String get atStart => 'When it starts';

  @override
  String get customReminder => 'Custom time';

  @override
  String get minutes => 'Minutes';

  @override
  String get hours => 'Hours';

  @override
  String get add => 'Add';

  @override
  String get timezone => 'Time zone';

  @override
  String get searchTimezone => 'Search time zones';

  @override
  String get language => 'Language';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncing => 'Synchronizing…';

  @override
  String syncSuccess(int count) {
    return 'Synchronized $count lessons';
  }

  @override
  String get signInToSync => 'Sign in to synchronize';

  @override
  String get syncFailed => 'Could not synchronize the schedule';

  @override
  String lastSync(String value) {
    return 'Last sync: $value';
  }

  @override
  String get never => 'Never';

  @override
  String get exactTiming => 'Exact reminders';

  @override
  String get reducedPrecision =>
      'Exact-alarm access is off; reminders may be delayed';

  @override
  String get grantPermission => 'Grant access';

  @override
  String get pageError => 'Could not open the page';

  @override
  String get retry => 'Retry';

  @override
  String get unsupportedLink => 'This link was blocked for your safety';

  @override
  String get startsNow => 'Starts now';

  @override
  String startsIn(String offset) {
    return 'Starts in $offset';
  }

  @override
  String lessonAt(String date, String zone) {
    return '$date • $zone';
  }

  @override
  String get uzbekCyrillic => 'Ўзбекча (Кирилл)';

  @override
  String get uzbekLatin => 'O‘zbekcha (Lotin)';

  @override
  String get english => 'English';

  @override
  String get russian => 'Русский';

  @override
  String get close => 'Close';

  @override
  String get backgroundSync => 'Background synchronization';

  @override
  String get backgroundSyncHelp =>
      'Checks lessons every 5 minutes while KIU is closed';

  @override
  String get backgroundAccess => 'Background access';

  @override
  String get backgroundAccessHelp =>
      'Allow KIU in battery settings so Android can synchronize after the app is closed. Android may still delay work.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get remove => 'Remove';

  @override
  String get notificationSound => 'Notification sound';

  @override
  String get defaultSound => 'System default';

  @override
  String get soundSelected => 'Selected system sound';

  @override
  String get chooseSound => 'Choose sound';

  @override
  String get soundSettings => 'Sound settings';

  @override
  String get mainSound => 'Main sound';

  @override
  String get individualSounds => 'Reminder sounds';

  @override
  String get inheritsMainSound => 'Uses main sound';

  @override
  String get soundOverridesHelp =>
      'Each reminder uses Main sound until you customize it.';

  @override
  String get customSound => 'Custom sound';

  @override
  String get useMainSound => 'Use main';

  @override
  String get customizeSound => 'Customize';

  @override
  String get scheduledLessons => 'Scheduled lessons';

  @override
  String get noScheduledLessons => 'No scheduled lessons';

  @override
  String get lessonCalls => 'Lesson calls';

  @override
  String get lessonCallsHelp => 'Shows a full-screen call when a lesson starts';

  @override
  String get ringDuration => 'Ring duration';

  @override
  String ringDurationValue(int seconds) {
    return '$seconds s';
  }

  @override
  String get callRingtone => 'Call ringtone';

  @override
  String get fullScreenAccess => 'Full-screen access';

  @override
  String get fullScreenAccessHelp =>
      'Allow full-screen calls over the lock screen in system settings';

  @override
  String get overlayAccess => 'Display over other apps';

  @override
  String get overlayAccessHelp =>
      'Lets the call screen open while you are using the phone. Without it the call shows only as a notification banner.';

  @override
  String get callForThisLesson => 'Call for this lesson';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';
}
