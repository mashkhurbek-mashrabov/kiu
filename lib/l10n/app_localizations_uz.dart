// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appTitle => 'KIU';

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
  String get notificationSettings => 'Eslatma sozlamalari';

  @override
  String get reminders => 'Dars eslatmalari';

  @override
  String get remindersHelp =>
      'Jadvalni fonda taxminan har 5 daqiqada tekshiradi';

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
  String syncSuccess(int count) {
    return '$count ta dars sinxronlandi';
  }

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
  String get reducedPrecision =>
      'Aniq vaqt ruxsati yo‘q; eslatma kechikishi mumkin';

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
  String get russian => 'Рсский';

  @override
  String get close => 'Yopish';

  @override
  String get backgroundSync => 'Fonda sinxronlash';

  @override
  String get backgroundSyncHelp =>
      'KIU yopiq bo‘lganda darslarni har 5 daqiqada tekshiradi';

  @override
  String get backgroundAccess => 'Fonda ishlash';

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
      'Boshqa ovoz tanlanmaguncha har bir eslatma asosiy ovozdan foydalanadi.';

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
  String get lessonCalls => 'Dars qo‘ng‘iroqlari';

  @override
  String get lessonCallsHelp =>
      'Dars boshlanganda to‘liq ekranli qo‘ng‘iroq ko‘rsatadi';

  @override
  String get ringDuration => 'Qo‘ng‘iroq davomiyligi';

  @override
  String ringDurationValue(int seconds) {
    return '$seconds soniya';
  }

  @override
  String get callRingtone => 'Qo‘ng‘iroq ohangi';

  @override
  String get fullScreenAccess => 'To‘liq ekran ruxsati';

  @override
  String get fullScreenAccessHelp =>
      'Qulflangan ekranda qo‘ng‘iroq ko‘rsatish uchun tizim sozlamalarida ruxsat bering';

  @override
  String get overlayAccess => 'Boshqa ilovalar ustida ko‘rsatish';

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
  String get apps => 'Ilovalar';
}

/// The translations for Uzbek, using the Cyrillic script (`uz_Cyrl`).
class AppLocalizationsUzCyrl extends AppLocalizationsUz {
  AppLocalizationsUzCyrl() : super('uz_Cyrl');

  @override
  String get appTitle => 'KIU';

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
  String get notificationSettings => 'Эслатма созламалари';

  @override
  String get reminders => 'Дарс эслатмалари';

  @override
  String get remindersHelp =>
      'Жадвални фонда тахминан ҳар 5 дақиқада текширади';

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
  String syncSuccess(int count) {
    return '$count та дарс синхронланди';
  }

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
  String get reducedPrecision =>
      'Аниқ вақт рухсати йўқ; эслатма кечикиши мумкин';

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
  String get close => 'Ёпиш';

  @override
  String get backgroundSync => 'Фонда синхронлаш';

  @override
  String get backgroundSyncHelp =>
      'KIU ёпиқ бўлганда дарсларни ҳар 5 дақиқада текширади';

  @override
  String get backgroundAccess => 'Фонда ишлаш';

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
      'Бошқа овоз танланмагунча ҳар бир эслатма асосий овоздан фойдаланади.';

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
  String get lessonCalls => 'Дарс қўнғироқлари';

  @override
  String get lessonCallsHelp =>
      'Дарс бошланганда тўлиқ экранли қўнғироқ кўрсатади';

  @override
  String get ringDuration => 'Қўнғироқ давомийлиги';

  @override
  String ringDurationValue(int seconds) {
    return '$seconds сония';
  }

  @override
  String get callRingtone => 'Қўнғироқ оҳанги';

  @override
  String get fullScreenAccess => 'Тўлиқ экран рухсати';

  @override
  String get fullScreenAccessHelp =>
      'Қулфланган экранда қўнғироқ кўрсатиш учун тизим созламаларида рухсат беринг';

  @override
  String get overlayAccess => 'Бошқа иловалар устида кўрсатиш';

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
  String get apps => 'Иловалар';
}
