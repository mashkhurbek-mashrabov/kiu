const String homeUrl = 'https://uz.do-kazankiu.ru/uz/profile/my-online-lessons';
const String trustedHost = 'uz.do-kazankiu.ru';
const String examHost = 'test.do-kazankiu.ru';
const String websiteTimeZone = 'Asia/Tashkent';
const String backgroundTaskName = 'kiuScheduleSync';
const String backgroundTaskUniqueName = 'kiu.periodicScheduleSync';

/// The repository releases are published to. Read unauthenticated — no token
/// ships in the APK — which caps us at 60 requests/hour per IP, far above what
/// the 6-hour check throttle uses.
const String latestReleaseApiUrl =
    'https://api.github.com/repos/mashkhurbek-mashrabov/kiu/releases/latest';

/// Where users reach the developer with feedback or a problem. Shown once, in
/// the main settings sheet — kept here so the handle and the URL cannot drift
/// apart from each other.
const String contactHandle = '@developer_aka';
const String contactUrl = 'https://t.me/developer_aka';

/// Hosts allowed to serve an update APK.
///
/// The download ends up installed as code, so the URL is allowlisted rather
/// than trusted because it arrived in the release payload. `github.com` issues
/// the asset URL and redirects to `objects.githubusercontent.com`, which is
/// where the bytes actually come from.
bool isGitHubReleaseAsset(Uri uri) =>
    uri.scheme == 'https' &&
    const {
      'github.com',
      'objects.githubusercontent.com',
      'release-assets.githubusercontent.com',
    }.contains(uri.host.toLowerCase());

/// Path prefixes the sites accept as a language. Both servers happily set a
/// `lang` cookie for *any* two-letter prefix (`/en/` included) without
/// validating it, so the app clamps to this set rather than trusting them.
const Set<String> supportedSiteLanguages = {'uz', 'ru'};

const String _homePath = 'profile/my-online-lessons';

/// The LMS host, which is allowed to receive session cookies and to run the
/// scripts and bridge calls the shell injects. Deliberately narrower than
/// [isSiteHttps] — do not widen it to bring in another host.
bool isTrustedHttps(Uri uri) =>
    uri.scheme == 'https' && uri.host.toLowerCase() == trustedHost;

/// Either of our sites: the LMS or the exam platform. Only broad enough to
/// rewrite a language prefix; it grants none of the privileges gated by
/// [isTrustedHttps].
bool isSiteHttps(Uri uri) =>
    uri.scheme == 'https' &&
    {trustedHost, examHost}.contains(uri.host.toLowerCase());

/// Maps an app locale onto one of the two languages the sites serve. The app
/// offers Latin and Cyrillic Uzbek plus English; only Russian differs.
String siteLanguageFor(String localeTag) => localeTag == 'ru' ? 'ru' : 'uz';

String homeUrlFor(String localeTag) =>
    'https://$trustedHost/${siteLanguageFor(localeTag)}/$_homePath';

/// Rewrites the language prefix of one of our URLs, which is all it takes to
/// switch the site over: visiting a prefixed URL makes the server persist the
/// choice in a long-lived `lang` cookie. Leaves prefix-less paths alone — the
/// server redirects those onto a prefixed URL from that cookie anyway.
Uri withSiteLanguage(Uri uri, String localeTag) {
  if (!isSiteHttps(uri) || uri.pathSegments.isEmpty) return uri;
  if (!supportedSiteLanguages.contains(uri.pathSegments.first)) return uri;
  return uri.replace(
    pathSegments: [siteLanguageFor(localeTag), ...uri.pathSegments.skip(1)],
  );
}

bool isHomeUri(Uri uri) {
  if (!isTrustedHttps(uri)) return false;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return supportedSiteLanguages.any((lang) => path == '/$lang/$_homePath');
}

bool isLessonUri(Uri uri) {
  if (!isTrustedHttps(uri)) return false;
  final path = uri.path.toLowerCase();
  return path.contains('lesson') || path.contains('video');
}

/// The Russian course, whose lesson pages ship the video in an unsized iframe
/// that collapses to a sliver; [videoIframeFixScript] gives it back a 16:9 box.
/// Every other course renders the same player correctly, so this is deliberately
/// narrow: course id 8 and only its `video-iframe` pages, not its tests.
const String _russianCourseId = '8';

bool isRussianCourseVideoUri(Uri uri) {
  if (!isTrustedHttps(uri)) return false;
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  // <lang>/my-course/<course>/<lesson>/video-iframe
  if (segments.length != 5) return false;
  return supportedSiteLanguages.contains(segments[0]) &&
      segments[1] == 'my-course' &&
      segments[2] == _russianCourseId &&
      segments[4].toLowerCase() == 'video-iframe';
}
