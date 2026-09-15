// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get back => 'Назад';

  @override
  String get forward => 'Вперёд';

  @override
  String get home => 'Главная';

  @override
  String get scheduledLessons => 'Запланированные занятия';

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
  String get notificationSettings => 'Уведомления и звонки';

  @override
  String get reminders => 'Напоминания об уроках';

  @override
  String get remindersHelp => 'Уведомляет перед началом каждого урока.';

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
  String get reducedPrecision => 'Напоминания могут опаздывать';

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
  String get uzbekCyrillic => 'Ўзбекча (Кирилл)';

  @override
  String get uzbekLatin => 'O‘zbekcha (Lotin)';

  @override
  String get english => 'English';

  @override
  String get russian => 'Русский';

  @override
  String get backgroundSync => 'Фоновая синхронизация';

  @override
  String get backgroundSyncHelp =>
      'Проверяет расписание каждые 5 минут, пока KIU закрыт.';

  @override
  String get backgroundAccess => 'Доступ к батарее';

  @override
  String get backgroundAccessHelp =>
      'Разрешите KIU фоновую работу в настройках батареи. Android всё ещё может отложить задачу.';

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get remove => 'Удалить';

  @override
  String get notificationSound => 'Звук уведомления';

  @override
  String get defaultSound => 'Системный по умолчанию';

  @override
  String get soundSelected => 'Выбран системный звук';

  @override
  String get chooseSound => 'Выбрать звук';

  @override
  String get soundSettings => 'Настройки звука';

  @override
  String get mainSound => 'Основной звук';

  @override
  String get individualSounds => 'Звуки напоминаний';

  @override
  String get inheritsMainSound => 'Использует основной звук';

  @override
  String get soundOverridesHelp =>
      'Каждое напоминание использует основной звук, пока вы не зададите свой.';

  @override
  String get customSound => 'Свой звук';

  @override
  String get useMainSound => 'Основной';

  @override
  String get customizeSound => 'Изменить';

  @override
  String get noScheduledLessons => 'Нет запланированных уроков';

  @override
  String get lessonCalls => 'Звонки';

  @override
  String get lessonCallsHelp =>
      'Показывает полноэкранный звонок в начале урока.';

  @override
  String get ringDuration => 'Длительность звонка';

  @override
  String ringDurationValue(int seconds) {
    return '$seconds с';
  }

  @override
  String get callRingtone => 'Мелодия звонка';

  @override
  String get fullScreenAccess => 'Полноэкранные звонки';

  @override
  String get fullScreenAccessHelp =>
      'Разрешите полноэкранные звонки поверх блокировки экрана в настройках системы';

  @override
  String get overlayAccess => 'Поверх других приложений';

  @override
  String get overlayAccessHelp =>
      'Позволяет экрану звонка открываться, даже когда вы используете телефон. Без этого звонок показывается только как уведомление.';

  @override
  String get callForThisLesson => 'Звонок для этого урока';

  @override
  String get joinLesson => 'Присоединиться к уроку';

  @override
  String get lessonStarted => 'Начался';

  @override
  String get appearance => 'Оформление';

  @override
  String get themeSystem => 'Как в системе';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get usefulLinks => 'Полезные ссылки';

  @override
  String get testPlatforms => 'Платформы тестирования';

  @override
  String get pdfBooks => 'Книги в PDF';

  @override
  String get bookRussianDictionary => 'Словарь русского языка';

  @override
  String get bookRussianLessons => 'Уроки русского языка';

  @override
  String get apps => 'Приложения';

  @override
  String get feedback => 'Отзывы и вопросы';

  @override
  String offsetHours(int count) {
    return '$count ч';
  }

  @override
  String offsetMinutes(int count) {
    return '$count мин';
  }

  @override
  String get settings => 'Настройки';

  @override
  String get sectionPlayback => 'Воспроизведение';

  @override
  String get sectionLessons => 'Уроки';

  @override
  String get sectionNotifications => 'Уведомления';

  @override
  String get sectionCalls => 'Звонки об уроках';

  @override
  String get sectionAppearance => 'Оформление';

  @override
  String get sectionResources => 'Ресурсы';

  @override
  String get sectionPermissions => 'Разрешения';

  @override
  String get sectionReminderTimes => 'Напоминать';

  @override
  String get sectionSync => 'Синхронизация';

  @override
  String get speed => 'Скорость';

  @override
  String get reminderTimes => 'Время напоминаний';

  @override
  String get sound => 'Звук';

  @override
  String get sounds => 'Звуки';

  @override
  String get addTime => 'Добавить время';

  @override
  String get amount => 'Значение';

  @override
  String get exactTimingHelp =>
      'Android доставляет напоминания минута в минуту только с этим доступом. Без него они могут опаздывать.';

  @override
  String get remindersTooltip =>
      'Отправляет уведомление перед началом каждого урока.';

  @override
  String get themeSystemHelp => 'Следует светлой или тёмной теме Android.';

  @override
  String get close => 'Закрыть';

  @override
  String get on => 'Вкл.';

  @override
  String get off => 'Выкл.';

  @override
  String get granted => 'Предоставлено';

  @override
  String get notGranted => 'Не предоставлено';

  @override
  String get allPermissionsGranted => 'Все предоставлены';

  @override
  String permissionsMissing(int count) {
    return 'Не предоставлено: $count';
  }

  @override
  String get about => 'О приложении';

  @override
  String get markWatchedHint =>
      'Помечает видео как просмотренное на платформе.';

  @override
  String get openLink => 'Открыть';

  @override
  String get searchHint => 'Поиск';

  @override
  String get reset => 'Сбросить';

  @override
  String get custom => 'Своё';

  @override
  String get preset => 'Готовое';

  @override
  String get noResults => 'Ничего не найдено';

  @override
  String get reminderTimesHelp =>
      'Выберите, за сколько до начала урока вас уведомить. Каждое включённое время отправляет своё уведомление, поэтому для одного урока их может прийти несколько.';

  @override
  String get ringDurationHelp =>
      'Сколько времени экран звонка звонит, прежде чем остановиться сам.';

  @override
  String get sectionAbout => 'О приложении';

  @override
  String get checkForUpdates => 'Проверить обновления';

  @override
  String get checking => 'Проверка…';

  @override
  String lastChecked(String value) {
    return 'Последняя проверка: $value';
  }

  @override
  String get upToDate => 'У вас последняя версия';

  @override
  String get updateAvailable => 'Доступно обновление';

  @override
  String get updateRequired => 'Требуется обновление';

  @override
  String updateVersion(String value) {
    return 'Версия $value';
  }

  @override
  String get updateNow => 'Обновить';

  @override
  String get whatsNew => 'Что нового';

  @override
  String get updateLater => 'Позже';

  @override
  String get downloadingUpdate => 'Загрузка…';

  @override
  String get installingUpdate => 'Установка…';

  @override
  String get updateFailed => 'Не удалось загрузить обновление';

  @override
  String get updateRequiredHelp =>
      'Эта версия устарела и не может продолжить работу. Установите обновление, чтобы продолжить.';

  @override
  String get installPermissionNeeded => 'Нужно разрешение на установку';

  @override
  String get installPermissionHelp =>
      'Android запрашивает разрешение «Установка неизвестных приложений», чтобы приложение могло обновить себя. Откроются системные настройки.';

  @override
  String get callsDisabledMissingPermission =>
      'Звонки на занятия не включены — нужное разрешение не выдано. Включите их в «Настройки → Разрешения».';

  @override
  String get callsEnabledAfterOnboarding => 'Звонки на занятия включены.';

  @override
  String get notNow => 'Не сейчас';

  @override
  String get permissionAllow => 'Разрешить';

  @override
  String get permissionWhyBattery =>
      'Чтобы расписание обновлялось даже после закрытия KIU.';

  @override
  String get permissionWhyExactTiming =>
      'Чтобы напоминания приходили точно в срок, а не с опозданием.';

  @override
  String get permissionWhyOverlay =>
      'Чтобы звонок на занятие открывался, пока вы пользуетесь телефоном.';

  @override
  String get permissionWhyFullScreen =>
      'Чтобы звонок на занятие появлялся на заблокированном экране.';

  @override
  String get permissionWhyNotifications =>
      'Чтобы KIU предупреждал вас до начала занятия.';

  @override
  String get permissionNotificationsHelp =>
      'Все напоминания и звонки на занятия приходят как уведомления. Без этого разрешения KIU не сможет сообщить вам ни о чём.';

  @override
  String get additionalFunctions => 'Дополнительные функции';

  @override
  String get additionalFunctionsHint =>
      'Эти функции открываются только по ключу активации. Скопируйте ID ниже и отправьте его разработчику — он создаст ключ для этого ID. Ключ работает только на этом устройстве.';

  @override
  String get yourUserId => 'Ваш ID';

  @override
  String get userIdCopied => 'ID скопирован';

  @override
  String get activationKey => 'Ключ активации';

  @override
  String get activationKeyHint => 'Например: KIU-XXXX-XXXX';

  @override
  String get activate => 'Активировать';

  @override
  String get activated => 'Активировано';

  @override
  String get activationFailed => 'Неверный ключ';

  @override
  String get activationSuccess => 'Дополнительные функции открыты';

  @override
  String get contactForKey => 'Написать за ключом';
}
