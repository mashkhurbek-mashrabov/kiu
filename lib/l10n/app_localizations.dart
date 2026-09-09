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

  /// No description provided for @appTitle.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'KIU'**
  String get appTitle;

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
  /// **'Эслатма созламалари'**
  String get notificationSettings;

  /// No description provided for @reminders.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Дарс эслатмалари'**
  String get reminders;

  /// No description provided for @remindersHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Жадвални фонда тахминан ҳар 5 дақиқада текширади'**
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

  /// No description provided for @syncSuccess.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'{count} та дарс синхронланди'**
  String syncSuccess(int count);

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
  /// **'Аниқ вақт рухсати йўқ; эслатма кечикиши мумкин'**
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

  /// No description provided for @lessonAt.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'{date} • {zone}'**
  String lessonAt(String date, String zone);

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

  /// No description provided for @close.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Ёпиш'**
  String get close;

  /// No description provided for @backgroundSync.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Фонда синхронлаш'**
  String get backgroundSync;

  /// No description provided for @backgroundSyncHelp.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'KIU ёпиқ бўлганда дарсларни ҳар 5 дақиқада текширади'**
  String get backgroundSyncHelp;

  /// No description provided for @backgroundAccess.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Фонда ишлаш'**
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
  /// **'Бошқа овоз танланмагунча ҳар бир эслатма асосий овоздан фойдаланади.'**
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

  /// No description provided for @scheduledLessons.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Режалаштирилган дарслар'**
  String get scheduledLessons;

  /// No description provided for @noScheduledLessons.
  ///
  /// In uz_Cyrl, this message translates to:
  /// **'Режалаштирилган дарслар йўқ'**
  String get noScheduledLessons;
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
