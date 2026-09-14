// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get notificationSettings => 'Notifications & calls';

  @override
  String get reminders => 'Lesson reminders';

  @override
  String get remindersHelp => 'Notifies you before each lesson starts.';

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
  String get reducedPrecision => 'Reminders may be delayed';

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
  String get uzbekCyrillic => 'Ўзбекча (Кирилл)';

  @override
  String get uzbekLatin => 'O‘zbekcha (Lotin)';

  @override
  String get english => 'English';

  @override
  String get russian => 'Русский';

  @override
  String get backgroundSync => 'Background synchronization';

  @override
  String get backgroundSyncHelp =>
      'Checks for schedule changes every 5 minutes while KIU is closed.';

  @override
  String get backgroundAccess => 'Battery access';

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
      'Each reminder uses the main sound until you give it its own.';

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
  String get lessonCalls => 'Calls';

  @override
  String get lessonCallsHelp =>
      'Rings a full-screen call when a lesson starts.';

  @override
  String get ringDuration => 'Ring duration';

  @override
  String ringDurationValue(int seconds) {
    return '$seconds s';
  }

  @override
  String get callRingtone => 'Call ringtone';

  @override
  String get fullScreenAccess => 'Full-screen calls';

  @override
  String get fullScreenAccessHelp =>
      'Allow full-screen calls over the lock screen in system settings';

  @override
  String get overlayAccess => 'Display over apps';

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

  @override
  String get usefulLinks => 'Useful links';

  @override
  String get testPlatforms => 'Test platforms';

  @override
  String get pdfBooks => 'PDF books';

  @override
  String get bookRussianDictionary => 'Russian dictionary';

  @override
  String get bookRussianLessons => 'Russian lessons';

  @override
  String get apps => 'Apps';

  @override
  String get feedback => 'Feedback and questions';

  @override
  String offsetHours(int count) {
    return '$count h';
  }

  @override
  String offsetMinutes(int count) {
    return '$count min';
  }

  @override
  String get settings => 'Settings';

  @override
  String get sectionPlayback => 'Playback';

  @override
  String get sectionLessons => 'Lessons';

  @override
  String get sectionNotifications => 'Notifications';

  @override
  String get sectionCalls => 'Lesson calls';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get sectionResources => 'Resources';

  @override
  String get sectionPermissions => 'Permissions';

  @override
  String get sectionReminderTimes => 'Remind me';

  @override
  String get sectionSync => 'Synchronization';

  @override
  String get speed => 'Speed';

  @override
  String get reminderTimes => 'Reminder times';

  @override
  String get sound => 'Sound';

  @override
  String get sounds => 'Sounds';

  @override
  String get addTime => 'Add time';

  @override
  String get amount => 'Amount';

  @override
  String get exactTimingHelp =>
      'Android delivers reminders at the exact minute only with this access. Without it they may arrive late.';

  @override
  String get remindersTooltip =>
      'Sends a notification before each lesson starts.';

  @override
  String get themeSystemHelp => 'Follows your Android light or dark setting.';

  @override
  String get close => 'Close';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get granted => 'Granted';

  @override
  String get notGranted => 'Not granted';

  @override
  String get about => 'About';

  @override
  String get markWatchedShort => 'Mark watched';

  @override
  String get openLink => 'Open';

  @override
  String get searchHint => 'Search';

  @override
  String get reset => 'Reset';

  @override
  String get custom => 'Custom';

  @override
  String get preset => 'Preset';

  @override
  String get noResults => 'Nothing found';

  @override
  String get reminderTimesHelp =>
      'Pick how long before a lesson you want to be notified. Each time you turn on sends its own notification, so several can fire for one lesson.';

  @override
  String get ringDurationHelp =>
      'How long the call screen keeps ringing before it gives up and stops on its own.';

  @override
  String get sectionAbout => 'About';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checking => 'Checking…';

  @override
  String lastChecked(String value) {
    return 'Last checked: $value';
  }

  @override
  String get upToDate => 'You are on the latest version';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get updateRequired => 'Update required';

  @override
  String updateVersion(String value) {
    return 'Version $value';
  }

  @override
  String get updateNow => 'Update';

  @override
  String get whatsNew => 'What\'s new';

  @override
  String get updateLater => 'Later';

  @override
  String get downloadingUpdate => 'Downloading…';

  @override
  String get installingUpdate => 'Installing…';

  @override
  String get updateFailed => 'Could not download the update';

  @override
  String get updateRequiredHelp =>
      'This version is out of date and cannot keep running. Install the update to continue.';

  @override
  String get installPermissionNeeded => 'Install permission needed';

  @override
  String get installPermissionHelp =>
      'Android asks for the “Install unknown apps” permission before an app can update itself. The system settings will open.';

  @override
  String get callsDisabledMissingPermission =>
      'Lesson calls stayed off — a required permission was not granted. Turn them on in Settings → Permissions.';

  @override
  String get callsEnabledAfterOnboarding => 'Lesson calls are on.';

  @override
  String get notNow => 'Not now';

  @override
  String get permissionAllow => 'Allow';

  @override
  String get permissionWhyBattery =>
      'So your schedule keeps updating after you close KIU.';

  @override
  String get permissionWhyExactTiming =>
      'So reminders arrive at the exact minute, not minutes late.';

  @override
  String get permissionWhyOverlay =>
      'So a lesson call can open while you are using your phone.';

  @override
  String get permissionWhyFullScreen =>
      'So a lesson call can appear over the lock screen.';

  @override
  String get permissionWhyNotifications =>
      'So KIU can tell you before a lesson starts.';

  @override
  String get permissionNotificationsHelp =>
      'Every reminder and lesson call arrives as a notification. Without this permission KIU cannot alert you about anything, even while the app is open.';
}
