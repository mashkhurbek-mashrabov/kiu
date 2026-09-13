// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get back => 'Orqaga';

  @override
  String get forward => 'Oldinga';

  @override
  String get home => 'Bosh sahifa';

  @override
  String get refresh => 'Yangilash';

  @override
  String get actions => 'Amallar';

  @override
  String get version => 'Versiya';

  @override
  String get videoSpeed => 'Video tezligi';

  @override
  String get customSpeed => 'Maxsus tezlik';

  @override
  String get markWatched => 'Ko‘rilgan deb belgilash';

  @override
  String get markWatchedQuestion => 'Bu darsni ko‘rilgan deb belgilaymizmi?';

  @override
  String get cancel => 'Bekor qilish';

  @override
  String get confirm => 'Tasdiqlash';

  @override
  String get marking => 'Belgilanmoqda…';

  @override
  String get marked => 'Dars ko‘rilgan deb belgilandi';

  @override
  String get markFailed => 'Darsni belgilab bo‘lmadi';

  @override
  String get onlyLesson => 'Bu amal faqat video darsida ishlaydi';

  @override
  String get notificationSettings => 'Bildirishnoma va qo‘ng‘iroqlar';

  @override
  String get reminders => 'Dars eslatmalari';

  @override
  String get remindersHelp => 'Har bir dars boshlanishidan oldin xabar beradi.';

  @override
  String get threeHours => '3 soat oldin';

  @override
  String get oneHour => '1 soat oldin';

  @override
  String get fifteenMinutes => '15 daqiqa oldin';

  @override
  String get atStart => 'Boshlanganda';

  @override
  String get customReminder => 'Maxsus vaqt';

  @override
  String get minutes => 'Daqiqa';

  @override
  String get hours => 'Soat';

  @override
  String get add => 'Qo‘shish';

  @override
  String get timezone => 'Vaqt mintaqasi';

  @override
  String get searchTimezone => 'Vaqt mintaqasini qidirish';

  @override
  String get language => 'Til';

  @override
  String get syncNow => 'Hozir sinxronlash';

  @override
  String get syncing => 'Sinxronlanmoqda…';

  @override
  String get signInToSync => 'Sinxronlash uchun tizimga kiring';

  @override
  String get syncFailed => 'Jadvalni sinxronlab bo‘lmadi';

  @override
  String lastSync(String value) {
    return 'Oxirgi sinxronlash: $value';
  }

  @override
  String get never => 'Hali yo‘q';

  @override
  String get exactTiming => 'Aniq eslatmalar';

  @override
  String get reducedPrecision => 'Eslatmalar kechikishi mumkin';

  @override
  String get grantPermission => 'Ruxsat berish';

  @override
  String get pageError => 'Sahifani ochib bo‘lmadi';

  @override
  String get retry => 'Qayta urinish';

  @override
  String get unsupportedLink => 'Bu havola xavfsizlik sababli ochilmadi';

  @override
  String get startsNow => 'Hozir boshlanadi';

  @override
  String startsIn(String offset) {
    return '${offset}dan keyin boshlanadi';
  }

  @override
  String get uzbekCyrillic => 'Ўзбекча (Кирилл)';

  @override
  String get uzbekLatin => 'O‘zbekcha (Lotin)';

  @override
  String get english => 'English';

  @override
  String get russian => 'Рсский';

  @override
  String get backgroundSync => 'Fonda sinxronlash';

  @override
  String get backgroundSyncHelp =>
      'KIU yopiq bo‘lganda jadvalni har 5 daqiqada tekshiradi.';

  @override
  String get backgroundAccess => 'Batareya ruxsati';

  @override
  String get backgroundAccessHelp =>
      'Ilova yopilganda sinxronlash uchun batareya sozlamalarida KIUga ruxsat bering. Android baribir vazifani kechiktirishi mumkin.';

  @override
  String get openSettings => 'Sozlamalarni ochish';

  @override
  String get remove => 'Olib tashlash';

  @override
  String get notificationSound => 'Bildirishnoma ovozi';

  @override
  String get defaultSound => 'Tizim standart ovozi';

  @override
  String get soundSelected => 'Tizim ovozi tanlangan';

  @override
  String get chooseSound => 'Ovozni tanlash';

  @override
  String get soundSettings => 'Ovoz sozlamalari';

  @override
  String get mainSound => 'Asosiy ovoz';

  @override
  String get individualSounds => 'Eslatma ovozlari';

  @override
  String get inheritsMainSound => 'Asosiy ovoz ishlatiladi';

  @override
  String get soundOverridesHelp =>
      'Alohida ovoz tanlanmaguncha har bir eslatma asosiy ovozdan foydalanadi.';

  @override
  String get customSound => 'Maxsus ovoz';

  @override
  String get useMainSound => 'Asosiy ovoz';

  @override
  String get customizeSound => 'Moslash';

  @override
  String get scheduledLessons => 'Rejalashtirilgan darslar';

  @override
  String get noScheduledLessons => 'Rejalashtirilgan darslar yo‘q';

  @override
  String get lessonCalls => 'Qo‘ng‘iroqlar';

  @override
  String get lessonCallsHelp =>
      'Dars boshlanganda to‘liq ekranli qo‘ng‘iroq qiladi.';

  @override
  String get ringDuration => 'Qo‘ng‘iroq davomiyligi';

  @override
  String ringDurationValue(int seconds) {
    return '$seconds soniya';
  }

  @override
  String get callRingtone => 'Qo‘ng‘iroq ohangi';

  @override
  String get fullScreenAccess => 'To‘liq ekranli qo‘ng‘iroq';

  @override
  String get fullScreenAccessHelp =>
      'Qulflangan ekranda qo‘ng‘iroq ko‘rsatish uchun tizim sozlamalarida ruxsat bering';

  @override
  String get overlayAccess => 'Ilovalar ustida ko‘rsatish';

  @override
  String get overlayAccessHelp =>
      'Telefondan foydalanayotganingizda qo‘ng‘iroq ekrani ochilishiga imkon beradi. Bo‘lmasa, qo‘ng‘iroq faqat bildirishnoma sifatida ko‘rinadi.';

  @override
  String get callForThisLesson => 'Ushbu dars uchun qo‘ng‘iroq';

  @override
  String get appearance => 'Ko‘rinish';

  @override
  String get themeSystem => 'Tizim bo‘yicha';

  @override
  String get themeLight => 'Yorug‘';

  @override
  String get themeDark => 'Tungi';

  @override
  String get usefulLinks => 'Foydali havolalar';

  @override
  String get testPlatforms => 'Test platformalari';

  @override
  String get pdfBooks => 'PDF kitoblar';

  @override
  String get bookRussianDictionary => 'Rus tili lug‘ati';

  @override
  String get bookRussianLessons => 'Rus tili darslari';

  @override
  String get apps => 'Ilovalar';

  @override
  String get feedback => 'Fikr va savollar';

  @override
  String offsetHours(int count) {
    return '$count soat';
  }

  @override
  String offsetMinutes(int count) {
    return '$count daqiqa';
  }

  @override
  String get settings => 'Sozlamalar';

  @override
  String get sectionPlayback => 'Ijro';

  @override
  String get sectionLessons => 'Darslar';

  @override
  String get sectionNotifications => 'Bildirishnomalar';

  @override
  String get sectionCalls => 'Dars qo‘ng‘iroqlari';

  @override
  String get sectionAppearance => 'Ko‘rinish';

  @override
  String get sectionResources => 'Manbalar';

  @override
  String get sectionPermissions => 'Ruxsatlar';

  @override
  String get sectionReminderTimes => 'Eslatish vaqti';

  @override
  String get sectionSync => 'Sinxronlash';

  @override
  String get speed => 'Tezlik';

  @override
  String get reminderTimes => 'Eslatma vaqtlari';

  @override
  String get sound => 'Ovoz';

  @override
  String get sounds => 'Ovozlar';

  @override
  String get addTime => 'Vaqt qo‘shish';

  @override
  String get amount => 'Miqdor';

  @override
  String get exactTimingHelp =>
      'Android eslatmalarni aniq daqiqada faqat shu ruxsat bilan yetkazadi. Bo‘lmasa, ular kechikishi mumkin.';

  @override
  String get remindersTooltip =>
      'Har bir dars boshlanishidan oldin bildirishnoma yuboradi.';

  @override
  String get themeSystemHelp =>
      'Android’dagi yorug‘ yoki tungi sozlamaga ergashadi.';

  @override
  String get close => 'Yopish';

  @override
  String get on => 'Yoniq';

  @override
  String get off => 'O‘chiq';

  @override
  String get granted => 'Berilgan';

  @override
  String get notGranted => 'Berilmagan';

  @override
  String get about => 'Ilova haqida';

  @override
  String get markWatchedShort => 'Ko‘rilgan';

  @override
  String get openLink => 'Ochish';

  @override
  String get searchHint => 'Qidirish';

  @override
  String get reset => 'Tiklash';

  @override
  String get custom => 'Maxsus';

  @override
  String get preset => 'Tayyor';

  @override
  String get noResults => 'Hech narsa topilmadi';

  @override
  String get reminderTimesHelp =>
      'Dars boshlanishidan qancha vaqt oldin xabar berishni tanlang. Yoqilgan har bir vaqt alohida bildirishnoma yuboradi, shuning uchun bitta darsga bir nechtasi kelishi mumkin.';

  @override
  String get ringDurationHelp =>
      'Qo‘ng‘iroq ekrani o‘zi to‘xtagunga qadar qancha vaqt jiringlashi.';
}

/// The translations for Uzbek, using the Cyrillic script (`uz_Cyrl`).
class AppLocalizationsUzCyrl extends AppLocalizationsUz {
  AppLocalizationsUzCyrl() : super('uz_Cyrl');

  @override
  String get back => 'Орқага';

  @override
  String get forward => 'Олдинга';

  @override
  String get home => 'Бош саҳифа';

  @override
  String get refresh => 'Янгилаш';

  @override
  String get actions => 'Амаллар';

  @override
  String get version => 'Версия';

  @override
  String get videoSpeed => 'Видео тезлиги';

  @override
  String get customSpeed => 'Махсус тезлик';

  @override
  String get markWatched => 'Кўрилган деб белгилаш';

  @override
  String get markWatchedQuestion => 'Бу дарсни кўрилган деб белгилаймизми?';

  @override
  String get cancel => 'Бекор қилиш';

  @override
  String get confirm => 'Тасдиқлаш';

  @override
  String get marking => 'Белгиланмоқда…';

  @override
  String get marked => 'Дарс кўрилган деб белгиланди';

  @override
  String get markFailed => 'Дарсни белгилаб бўлмади';

  @override
  String get onlyLesson => 'Бу амал фақат видео дарсида ишлайди';

  @override
  String get notificationSettings => 'Билдиришнома ва қўнғироқлар';

  @override
  String get reminders => 'Дарс эслатмалари';

  @override
  String get remindersHelp => 'Ҳар бир дарс бошланишидан олдин хабар беради.';

  @override
  String get threeHours => '3 соат олдин';

  @override
  String get oneHour => '1 соат олдин';

  @override
  String get fifteenMinutes => '15 дақиқа олдин';

  @override
  String get atStart => 'Бошланганда';

  @override
  String get customReminder => 'Махсус вақт';

  @override
  String get minutes => 'Дақиқа';

  @override
  String get hours => 'Соат';

  @override
  String get add => 'Қўшиш';

  @override
  String get timezone => 'Вақт минтақаси';

  @override
  String get searchTimezone => 'Вақт минтақасини қидириш';

  @override
  String get language => 'Тил';

  @override
  String get syncNow => 'Ҳозир синхронлаш';

  @override
  String get syncing => 'Синхронланмоқда…';

  @override
  String get signInToSync => 'Синхронлаш учун тизимга киринг';

  @override
  String get syncFailed => 'Жадвални синхронлаб бўлмади';

  @override
  String lastSync(String value) {
    return 'Охирги синхронлаш: $value';
  }

  @override
  String get never => 'Ҳали йўқ';

  @override
  String get exactTiming => 'Аниқ эслатмалар';

  @override
  String get reducedPrecision => 'Эслатмалар кечикиши мумкин';

  @override
  String get grantPermission => 'Рухсат бериш';

  @override
  String get pageError => 'Саҳифани очиб бўлмади';

  @override
  String get retry => 'Қайта уриниш';

  @override
  String get unsupportedLink => 'Бу ҳавола хавфсизлик сабабли очилмади';

  @override
  String get startsNow => 'Ҳозир бошланади';

  @override
  String startsIn(String offset) {
    return '$offsetдан кейин бошланади';
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
  String get backgroundSync => 'Фонда синхронлаш';

  @override
  String get backgroundSyncHelp =>
      'KIU ёпиқ бўлганда жадвални ҳар 5 дақиқада текширади.';

  @override
  String get backgroundAccess => 'Батарея рухсати';

  @override
  String get backgroundAccessHelp =>
      'Илова ёпилганда синхронлаш учун батарея созламаларида KIUга рухсат беринг. Android барибир вазифани кечиктириши мумкин.';

  @override
  String get openSettings => 'Созламаларни очиш';

  @override
  String get remove => 'Ўчириш';

  @override
  String get notificationSound => 'Билдиришнома овози';

  @override
  String get defaultSound => 'Тизим стандарт овози';

  @override
  String get soundSelected => 'Тизим овози танланган';

  @override
  String get chooseSound => 'Овозни танлаш';

  @override
  String get soundSettings => 'Овоз созламалари';

  @override
  String get mainSound => 'Асосий овоз';

  @override
  String get individualSounds => 'Эслатма овозлари';

  @override
  String get inheritsMainSound => 'Асосий овоз ишлатилади';

  @override
  String get soundOverridesHelp =>
      'Алоҳида овоз танланмагунча ҳар бир эслатма асосий овоздан фойдаланади.';

  @override
  String get customSound => 'Махсус овоз';

  @override
  String get useMainSound => 'Асосий овоз';

  @override
  String get customizeSound => 'Мослаш';

  @override
  String get scheduledLessons => 'Режалаштирилган дарслар';

  @override
  String get noScheduledLessons => 'Режалаштирилган дарслар йўқ';

  @override
  String get lessonCalls => 'Қўнғироқлар';

  @override
  String get lessonCallsHelp =>
      'Дарс бошланганда тўлиқ экранли қўнғироқ қилади.';

  @override
  String get ringDuration => 'Қўнғироқ давомийлиги';

  @override
  String ringDurationValue(int seconds) {
    return '$seconds сония';
  }

  @override
  String get callRingtone => 'Қўнғироқ оҳанги';

  @override
  String get fullScreenAccess => 'Тўлиқ экранли қўнғироқ';

  @override
  String get fullScreenAccessHelp =>
      'Қулфланган экранда қўнғироқ кўрсатиш учун тизим созламаларида рухсат беринг';

  @override
  String get overlayAccess => 'Иловалар устида кўрсатиш';

  @override
  String get overlayAccessHelp =>
      'Телефондан фойдаланаётганингизда қўнғироқ экрани очилишига имкон беради. Бўлмаса, қўнғироқ фақат билдиришнома сифатида кўринади.';

  @override
  String get callForThisLesson => 'Ушбу дарс учун қўнғироқ';

  @override
  String get appearance => 'Кўриниш';

  @override
  String get themeSystem => 'Тизим бўйича';

  @override
  String get themeLight => 'Ёруғ';

  @override
  String get themeDark => 'Тунги';

  @override
  String get usefulLinks => 'Фойдали ҳаволалар';

  @override
  String get testPlatforms => 'Тест платформалари';

  @override
  String get pdfBooks => 'PDF китоблар';

  @override
  String get bookRussianDictionary => 'Рус тили луғати';

  @override
  String get bookRussianLessons => 'Рус тили дарслари';

  @override
  String get apps => 'Иловалар';

  @override
  String get feedback => 'Фикр ва саволлар';

  @override
  String offsetHours(int count) {
    return '$count соат';
  }

  @override
  String offsetMinutes(int count) {
    return '$count дақиқа';
  }

  @override
  String get settings => 'Созламалар';

  @override
  String get sectionPlayback => 'Ижро';

  @override
  String get sectionLessons => 'Дарслар';

  @override
  String get sectionNotifications => 'Билдиришномалар';

  @override
  String get sectionCalls => 'Дарс қўнғироқлари';

  @override
  String get sectionAppearance => 'Кўриниш';

  @override
  String get sectionResources => 'Манбалар';

  @override
  String get sectionPermissions => 'Рухсатлар';

  @override
  String get sectionReminderTimes => 'Эслатиш вақти';

  @override
  String get sectionSync => 'Синхронлаш';

  @override
  String get speed => 'Тезлик';

  @override
  String get reminderTimes => 'Эслатма вақтлари';

  @override
  String get sound => 'Овоз';

  @override
  String get sounds => 'Овозлар';

  @override
  String get addTime => 'Вақт қўшиш';

  @override
  String get amount => 'Миқдор';

  @override
  String get exactTimingHelp =>
      'Android эслатмаларни аниқ дақиқада фақат шу рухсат билан етказади. Бўлмаса, улар кечикиши мумкин.';

  @override
  String get remindersTooltip =>
      'Ҳар бир дарс бошланишидан олдин билдиришнома юборади.';

  @override
  String get themeSystemHelp =>
      'Android’даги ёруғ ёки тунги созламага эргашади.';

  @override
  String get close => 'Ёпиш';

  @override
  String get on => 'Ёниқ';

  @override
  String get off => 'Ўчиқ';

  @override
  String get granted => 'Берилган';

  @override
  String get notGranted => 'Берилмаган';

  @override
  String get about => 'Илова ҳақида';

  @override
  String get markWatchedShort => 'Кўрилган';

  @override
  String get openLink => 'Очиш';

  @override
  String get searchHint => 'Қидириш';

  @override
  String get reset => 'Тиклаш';

  @override
  String get custom => 'Махсус';

  @override
  String get preset => 'Тайёр';

  @override
  String get noResults => 'Ҳеч нарса топилмади';

  @override
  String get reminderTimesHelp =>
      'Дарс бошланишидан қанча вақт олдин хабар беришни танланг. Ёқилган ҳар бир вақт алоҳида билдиришнома юборади, шунинг учун битта дарсга бир нечтаси келиши мумкин.';

  @override
  String get ringDurationHelp =>
      'Қўнғироқ экрани ўзи тўхтагунга қадар қанча вақт жиринглаши.';
}
