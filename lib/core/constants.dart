const String homeUrl = 'https://uz.do-kazankiu.ru/uz/profile/my-online-lessons';
const String trustedHost = 'uz.do-kazankiu.ru';
const String websiteTimeZone = 'Asia/Tashkent';
const String backgroundTaskName = 'kiuScheduleSync';
const String backgroundTaskUniqueName = 'kiu.periodicScheduleSync';

bool isTrustedHttps(Uri uri) =>
    uri.scheme == 'https' && uri.host.toLowerCase() == trustedHost;

bool isHomeUri(Uri uri) =>
    isTrustedHttps(uri) &&
    uri.path.replaceAll(RegExp(r'/+$'), '') == '/uz/profile/my-online-lessons';

bool isLessonUri(Uri uri) {
  if (!isTrustedHttps(uri)) return false;
  final path = uri.path.toLowerCase();
  return path.contains('lesson') || path.contains('video');
}
