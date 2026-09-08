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
}
