// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'KIU';

  @override
  String get back => 'Назад';

  @override
  String get forward => 'Вперёд';

  @override
  String get home => 'Главная';

  @override
  String get refresh => 'Обновить';

  @override
  String get actions => 'Действия';

  @override
  String get version => 'Версия';

  @override
  String get videoSpeed => 'Скорость видео';

  @override
  String get customSpeed => 'Своя скорость';

  @override
  String get markWatched => 'Отметить просмотренным';

  @override
  String get markWatchedQuestion => 'Отметить урок как просмотренный?';

  @override
  String get cancel => 'Отмена';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get marking => 'Отмечаем…';

  @override
  String get marked => 'Урок отмечен просмотренным';

  @override
  String get markFailed => 'Не удалось отметить урок';

  @override
  String get onlyLesson => 'Действие доступно только на видеоуроке';

  @override
  String get notificationSettings => 'Настройки уведомлений';

  @override
  String get reminders => 'Напоминания об уроках';

  @override
  String get remindersHelp =>
      'Проверяет изменения расписания в фоне примерно каждые 5 минут';

  @override
  String get threeHours => 'За 3 часа';

  @override
  String get oneHour => 'За 1 час';

  @override
  String get fifteenMinutes => 'За 15 минут';

  @override
  String get atStart => 'При начале';

  @override
  String get customReminder => 'Своё время';

  @override
  String get minutes => 'Минуты';

  @override
  String get hours => 'Часы';

  @override
  String get add => 'Добавить';

  @override
  String get timezone => 'Часовой пояс';

  @override
  String get searchTimezone => 'Поиск часового пояса';

  @override
  String get language => 'Язык';

  @override
  String get syncNow => 'Синхронизировать';

  @override
  String get syncing => 'Синхронизация…';

  @override
  String syncSuccess(int count) {
    return 'Синхронизировано уроков: $count';
  }

  @override
  String get signInToSync => 'Войдите для синхронизации';

  @override
  String get syncFailed => 'Не удалось синхронизировать расписание';

  @override
  String lastSync(String value) {
    return 'Последняя синхронизация: $value';
  }

  @override
  String get never => 'Никогда';

  @override
  String get exactTiming => 'Точные напоминания';

  @override
  String get reducedPrecision =>
      'Нет доступа к точным будильникам; напоминания могут задерживаться';

  @override
  String get grantPermission => 'Разрешить';

  @override
  String get pageError => 'Не удалось открыть страницу';

  @override
  String get retry => 'Повторить';

  @override
  String get unsupportedLink => 'Ссылка заблокирована для вашей безопасности';

  @override
  String get startsNow => 'Начинается сейчас';

  @override
  String startsIn(String offset) {
    return 'Начинается через $offset';
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
  String get close => 'Закрыть';

  @override
  String get backgroundSync => 'Фоновая синхронизация';

  @override
  String get backgroundSyncHelp =>
      'Проверяет уроки каждые 5 минут при закрытом KIU';

  @override
  String get backgroundAccess => 'Работа в фоне';

  @override
  String get backgroundAccessHelp =>
      'Разрешите KIU фоновую работу в настройках батареи. Android всё ещё может отложить задачу.';

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get remove => 'Удалить';
}
