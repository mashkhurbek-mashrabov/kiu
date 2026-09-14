import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('uz'),
    Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl'),
  ];

  /// No description provided for @back.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Орқага'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Олдинга'**
  String get forward;

  /// No description provided for @home.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Бош саҳифа'**
  String get home;

  /// No description provided for @scheduledLessons.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Режалаштирилган дарслар'**
  String get scheduledLessons;

  /// No description provided for @refresh.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Янгилаш'**
  String get refresh;

  /// No description provided for @actions.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Амаллар'**
  String get actions;

  /// No description provided for @version.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Версия'**
  String get version;

  /// No description provided for @videoSpeed.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Видео тезлиги'**
  String get videoSpeed;

  /// No description provided for @customSpeed.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Махсус тезлик'**
  String get customSpeed;

  /// No description provided for @markWatched.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Кўрилган деб белгилаш'**
  String get markWatched;

  /// No description provided for @markWatchedQuestion.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Бу дарсни кўрилган деб белгилаймизми?'**
  String get markWatchedQuestion;

  /// No description provided for @cancel.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Бекор қилиш'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тасдиқлаш'**
  String get confirm;

  /// No description provided for @marking.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Белгиланмоқда…'**
  String get marking;

  /// No description provided for @marked.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс кўрилган деб белгиланди'**
  String get marked;

  /// No description provided for @markFailed.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарсни белгилаб бўлмади'**
  String get markFailed;

  /// No description provided for @onlyLesson.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Бу амал фақат видео дарсида ишлайди'**
  String get onlyLesson;

  /// No description provided for @notificationSettings.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Билдиришнома ва қўнғироқлар'**
  String get notificationSettings;

  /// No description provided for @reminders.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс эслатмалари'**
  String get reminders;

  /// No description provided for @remindersHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ҳар бир дарс бошланишидан олдин хабар беради.'**
  String get remindersHelp;

  /// No description provided for @threeHours.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'3 соат олдин'**
  String get threeHours;

  /// No description provided for @oneHour.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'1 соат олдин'**
  String get oneHour;

  /// No description provided for @fifteenMinutes.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'15 дақиқа олдин'**
  String get fifteenMinutes;

  /// No description provided for @atStart.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Бошланганда'**
  String get atStart;

  /// No description provided for @customReminder.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Махсус вақт'**
  String get customReminder;

  /// No description provided for @minutes.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дақиқа'**
  String get minutes;

  /// No description provided for @hours.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Соат'**
  String get hours;

  /// No description provided for @add.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қўшиш'**
  String get add;

  /// No description provided for @timezone.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Вақт минтақаси'**
  String get timezone;

  /// No description provided for @searchTimezone.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Вақт минтақасини қидириш'**
  String get searchTimezone;

  /// No description provided for @language.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тил'**
  String get language;

  /// No description provided for @syncNow.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ҳозир синхронлаш'**
  String get syncNow;

  /// No description provided for @syncing.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Синхронланмоқда…'**
  String get syncing;

  /// No description provided for @signInToSync.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Синхронлаш учун тизимга киринг'**
  String get signInToSync;

  /// No description provided for @syncFailed.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Жадвални синхронлаб бўлмади'**
  String get syncFailed;

  /// No description provided for @lastSync.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Охирги синхронлаш: {value}'**
  String lastSync(String value);

  /// No description provided for @never.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ҳали йўқ'**
  String get never;

  /// No description provided for @exactTiming.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Аниқ эслатмалар'**
  String get exactTiming;

  /// No description provided for @reducedPrecision.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Эслатмалар кечикиши мумкин'**
  String get reducedPrecision;

  /// No description provided for @grantPermission.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Рухсат бериш'**
  String get grantPermission;

  /// No description provided for @pageError.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Саҳифани очиб бўлмади'**
  String get pageError;

  /// No description provided for @retry.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қайта уриниш'**
  String get retry;

  /// No description provided for @unsupportedLink.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Бу ҳавола хавфсизлик сабабли очилмади'**
  String get unsupportedLink;

  /// No description provided for @startsNow.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ҳозир бошланади'**
  String get startsNow;

  /// No description provided for @startsIn.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'{offset}дан кейин бошланади'**
  String startsIn(String offset);

  /// No description provided for @uzbekCyrillic.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ўзбекча (Кирилл)'**
  String get uzbekCyrillic;

  /// No description provided for @uzbekLatin.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'O‘zbekcha (Lotin)'**
  String get uzbekLatin;

  /// No description provided for @english.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @russian.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Русский'**
  String get russian;

  /// No description provided for @backgroundSync.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Фонда синхронлаш'**
  String get backgroundSync;

  /// No description provided for @backgroundSyncHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'KIU ёпиқ бўлганда жадвални ҳар 5 дақиқада текширади.'**
  String get backgroundSyncHelp;

  /// No description provided for @backgroundAccess.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Батарея рухсати'**
  String get backgroundAccess;

  /// No description provided for @backgroundAccessHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Илова ёпилганда синхронлаш учун батарея созламаларида KIUга рухсат беринг. Android барибир вазифани кечиктириши мумкин.'**
  String get backgroundAccessHelp;

  /// No description provided for @openSettings.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Созламаларни очиш'**
  String get openSettings;

  /// No description provided for @remove.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ўчириш'**
  String get remove;

  /// No description provided for @notificationSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Билдиришнома овози'**
  String get notificationSound;

  /// No description provided for @defaultSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тизим стандарт овози'**
  String get defaultSound;

  /// No description provided for @soundSelected.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тизим овози танланган'**
  String get soundSelected;

  /// No description provided for @chooseSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Овозни танлаш'**
  String get chooseSound;

  /// No description provided for @soundSettings.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Овоз созламалари'**
  String get soundSettings;

  /// No description provided for @mainSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Асосий овоз'**
  String get mainSound;

  /// No description provided for @individualSounds.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Эслатма овозлари'**
  String get individualSounds;

  /// No description provided for @inheritsMainSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Асосий овоз ишлатилади'**
  String get inheritsMainSound;

  /// No description provided for @soundOverridesHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Алоҳида овоз танланмагунча ҳар бир эслатма асосий овоздан фойдаланади.'**
  String get soundOverridesHelp;

  /// No description provided for @customSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Махсус овоз'**
  String get customSound;

  /// No description provided for @useMainSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Асосий овоз'**
  String get useMainSound;

  /// No description provided for @customizeSound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Мослаш'**
  String get customizeSound;

  /// No description provided for @noScheduledLessons.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Режалаштирилган дарслар йўқ'**
  String get noScheduledLessons;

  /// No description provided for @lessonCalls.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қўнғироқлар'**
  String get lessonCalls;

  /// No description provided for @lessonCallsHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс бошланганда тўлиқ экранли қўнғироқ қилади.'**
  String get lessonCallsHelp;

  /// No description provided for @ringDuration.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қўнғироқ давомийлиги'**
  String get ringDuration;

  /// No description provided for @ringDurationValue.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'{seconds} сония'**
  String ringDurationValue(int seconds);

  /// No description provided for @callRingtone.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қўнғироқ оҳанги'**
  String get callRingtone;

  /// No description provided for @fullScreenAccess.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тўлиқ экранли қўнғироқ'**
  String get fullScreenAccess;

  /// No description provided for @fullScreenAccessHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қулфланган экранда қўнғироқ кўрсатиш учун тизим созламаларида рухсат беринг'**
  String get fullScreenAccessHelp;

  /// No description provided for @overlayAccess.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Иловалар устида кўрсатиш'**
  String get overlayAccess;

  /// No description provided for @overlayAccessHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Телефондан фойдаланаётганингизда қўнғироқ экрани очилишига имкон беради. Бўлмаса, қўнғироқ фақат билдиришнома сифатида кўринади.'**
  String get overlayAccessHelp;

  /// No description provided for @callForThisLesson.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ушбу дарс учун қўнғироқ'**
  String get callForThisLesson;

  /// No description provided for @appearance.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Кўриниш'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тизим бўйича'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ёруғ'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тунги'**
  String get themeDark;

  /// No description provided for @usefulLinks.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Фойдали ҳаволалар'**
  String get usefulLinks;

  /// No description provided for @testPlatforms.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тест платформалари'**
  String get testPlatforms;

  /// No description provided for @pdfBooks.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'PDF китоблар'**
  String get pdfBooks;

  /// No description provided for @bookRussianDictionary.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Рус тили луғати'**
  String get bookRussianDictionary;

  /// No description provided for @bookRussianLessons.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Рус тили дарслари'**
  String get bookRussianLessons;

  /// No description provided for @apps.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Иловалар'**
  String get apps;

  /// No description provided for @feedback.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Фикр ва саволлар'**
  String get feedback;

  /// No description provided for @offsetHours.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'{count} соат'**
  String offsetHours(int count);

  /// No description provided for @offsetMinutes.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'{count} дақиқа'**
  String offsetMinutes(int count);

  /// No description provided for @settings.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Созламалар'**
  String get settings;

  /// No description provided for @sectionPlayback.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ижро'**
  String get sectionPlayback;

  /// No description provided for @sectionLessons.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарслар'**
  String get sectionLessons;

  /// No description provided for @sectionNotifications.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Билдиришномалар'**
  String get sectionNotifications;

  /// No description provided for @sectionCalls.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс қўнғироқлари'**
  String get sectionCalls;

  /// No description provided for @sectionAppearance.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Кўриниш'**
  String get sectionAppearance;

  /// No description provided for @sectionResources.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Манбалар'**
  String get sectionResources;

  /// No description provided for @sectionPermissions.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Рухсатлар'**
  String get sectionPermissions;

  /// No description provided for @sectionReminderTimes.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Эслатиш вақти'**
  String get sectionReminderTimes;

  /// No description provided for @sectionSync.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Синхронлаш'**
  String get sectionSync;

  /// No description provided for @speed.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тезлик'**
  String get speed;

  /// No description provided for @reminderTimes.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Эслатма вақтлари'**
  String get reminderTimes;

  /// No description provided for @sound.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Овоз'**
  String get sound;

  /// No description provided for @sounds.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Овозлар'**
  String get sounds;

  /// No description provided for @addTime.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Вақт қўшиш'**
  String get addTime;

  /// No description provided for @amount.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Миқдор'**
  String get amount;

  /// No description provided for @exactTimingHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Android эслатмаларни аниқ дақиқада фақат шу рухсат билан етказади. Бўлмаса, улар кечикиши мумкин.'**
  String get exactTimingHelp;

  /// No description provided for @remindersTooltip.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ҳар бир дарс бошланишидан олдин билдиришнома юборади.'**
  String get remindersTooltip;

  /// No description provided for @themeSystemHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Android’даги ёруғ ёки тунги созламага эргашади.'**
  String get themeSystemHelp;

  /// No description provided for @close.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ёпиш'**
  String get close;

  /// No description provided for @on.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ёниқ'**
  String get on;

  /// No description provided for @off.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ўчиқ'**
  String get off;

  /// No description provided for @granted.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Берилган'**
  String get granted;

  /// No description provided for @notGranted.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Берилмаган'**
  String get notGranted;

  /// No description provided for @about.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Илова ҳақида'**
  String get about;

  /// No description provided for @markWatchedShort.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Кўрилган'**
  String get markWatchedShort;

  /// No description provided for @openLink.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Очиш'**
  String get openLink;

  /// No description provided for @searchHint.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қидириш'**
  String get searchHint;

  /// No description provided for @reset.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тиклаш'**
  String get reset;

  /// No description provided for @custom.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Махсус'**
  String get custom;

  /// No description provided for @preset.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Тайёр'**
  String get preset;

  /// No description provided for @noResults.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ҳеч нарса топилмади'**
  String get noResults;

  /// No description provided for @reminderTimesHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс бошланишидан қанча вақт олдин хабар беришни танланг. Ёқилган ҳар бир вақт алоҳида билдиришнома юборади, шунинг учун битта дарсга бир нечтаси келиши мумкин.'**
  String get reminderTimesHelp;

  /// No description provided for @ringDurationHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Қўнғироқ экрани ўзи тўхтагунга қадар қанча вақт жиринглаши.'**
  String get ringDurationHelp;

  /// No description provided for @sectionAbout.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Илова ҳақида'**
  String get sectionAbout;

  /// No description provided for @checkForUpdates.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Янгиланишни текшириш'**
  String get checkForUpdates;

  /// No description provided for @checking.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Текширилмоқда…'**
  String get checking;

  /// No description provided for @lastChecked.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Охирги текширув: {value}'**
  String lastChecked(String value);

  /// No description provided for @upToDate.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Сизда энг сўнгги версия'**
  String get upToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Янгиланиш мавжуд'**
  String get updateAvailable;

  /// No description provided for @updateRequired.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Янгиланиш талаб қилинади'**
  String get updateRequired;

  /// No description provided for @updateVersion.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Версия {value}'**
  String updateVersion(String value);

  /// No description provided for @updateNow.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Янгилаш'**
  String get updateNow;

  /// No description provided for @whatsNew.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Нима янгиланди'**
  String get whatsNew;

  /// No description provided for @updateLater.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Кейинроқ'**
  String get updateLater;

  /// No description provided for @downloadingUpdate.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Юклаб олинмоқда…'**
  String get downloadingUpdate;

  /// No description provided for @installingUpdate.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ўрнатилмоқда…'**
  String get installingUpdate;

  /// No description provided for @updateFailed.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Янгиланишни юклаб бўлмади'**
  String get updateFailed;

  /// No description provided for @updateRequiredHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Бу версия эскирган ва ишлашда давом этолмайди. Давом этиш учун янгиланишни ўрнатинг.'**
  String get updateRequiredHelp;

  /// No description provided for @installPermissionNeeded.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ўрнатишга рухсат керак'**
  String get installPermissionNeeded;

  /// No description provided for @installPermissionHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Android илова ўзини янгилаши учун «Номаълум иловаларни ўрнатиш» рухсатини сўрайди. Тизим созламалари очилади.'**
  String get installPermissionHelp;

  /// No description provided for @callsDisabledMissingPermission.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс қўнғироқлари ёқилмади — керакли рухсат берилмади. Созламалар → Рухсатлар бўлимидан ёқинг.'**
  String get callsDisabledMissingPermission;

  /// No description provided for @callsEnabledAfterOnboarding.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс қўнғироқлари ёқилди.'**
  String get callsEnabledAfterOnboarding;

  /// No description provided for @notNow.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ҳозир эмас'**
  String get notNow;

  /// No description provided for @permissionAllow.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Рухсат бериш'**
  String get permissionAllow;

  /// No description provided for @permissionWhyBattery.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'KIU ёпилгандан кейин ҳам дарс жадвали янгиланиб туриши учун.'**
  String get permissionWhyBattery;

  /// No description provided for @permissionWhyExactTiming.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Эслатмалар кечикмасдан, аниқ вақтида келиши учун.'**
  String get permissionWhyExactTiming;

  /// No description provided for @permissionWhyOverlay.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Телефондан фойдаланаётганингизда дарс қўнғироғи очилиши учун.'**
  String get permissionWhyOverlay;

  /// No description provided for @permissionWhyFullScreen.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс қўнғироғи қулфланган экранда кўриниши учун.'**
  String get permissionWhyFullScreen;

  /// No description provided for @permissionWhyNotifications.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'KIU дарс бошланишидан олдин хабар бериши учун.'**
  String get permissionWhyNotifications;

  /// No description provided for @permissionNotificationsHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Барча эслатмалар ва дарс қўнғироқлари билдиришнома сифатида келади. Бу рухсатсиз KIU сизга ҳеч қандай хабар юбора олмайди.'**
  String get permissionNotificationsHelp;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'uz':
      {
        switch (locale.scriptCode) {
          case 'Cyrl':
            return AppLocalizationsUzCyrl();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
