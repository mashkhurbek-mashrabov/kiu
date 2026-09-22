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

/// The https destination an `intent://` URL is really asking for.
///
/// Google Meet — and every other Firebase Dynamic Link — hands a lesson link
/// off to its app by redirecting the WebView to `intent://...#Intent;...;end`.
/// That has no https scheme, so the shell used to block it and show "link
/// blocked", which is the one thing tapping a lesson is for.
///
/// Two candidates are read, in this order:
///
///  * `link=`, the wrapped destination — for Meet this is the meeting itself
///    (`https://meet.google.com/<code>`). Android hands that to the Meet app
///    when it is installed and to the browser when it is not, so it works in
///    both cases and joins the lesson directly.
///  * `S.browser_fallback_url`, the intent's own declared web fallback, used
///    only when there is no `link=`. For Meet this is the Play Store listing,
///    which installs the app but does not join anything — hence second.
///
/// Both are read off the raw string rather than through [Uri.queryParameters]:
/// the fallback sits percent-encoded inside the `#Intent;...;end` fragment,
/// which is not a query, so the query parsers never see it. Whichever matches
/// is re-checked rather than trusted — this is page content, and a
/// `javascript:`, `file:` or `user:pass@` target must never reach another app.
Uri? intentFallbackUrl(Uri uri) {
  if (uri.scheme.toLowerCase() != 'intent') return null;
  final raw = uri.toString();
  for (final pattern in [
    RegExp(r'[?&]link=([^&;#]+)'),
    RegExp(r'S\.browser_fallback_url=([^;]+)'),
  ]) {
    final match = pattern.firstMatch(raw);
    if (match == null) continue;
    final decoded = Uri.tryParse(Uri.decodeComponent(match.group(1)!));
    if (decoded == null || decoded.scheme != 'https') continue;
    if (decoded.host.isEmpty || decoded.userInfo.isNotEmpty) continue;
    return decoded;
  }
  return null;
}

/// Path prefixes the sites accept as a language. Both servers happily set a
/// `lang` cookie for *any* two-letter prefix (`/en/` included) without
/// validating it, so the app clamps to this set rather than trusting them.
const Set<String> supportedSiteLanguages = {'uz', 'ru'};

const String _homePath = 'profile/my-online-lessons';

/// The user's own course page, which is where the site actually lands them.
/// The trailing segment is a course level that differs per user, so unlike
/// [_homePath] this path is never complete on its own — see [courseUrlFor].
const String _coursePath = 'profile/my-courses';

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

/// The course page for [level] in the app's language. The level is read out of
/// the site's own nav (`courseLevelScript`) rather than assumed: it is per-user,
/// and the server does not redirect a level-less `/profile/my-courses`.
String courseUrlFor(String localeTag, int level) =>
    'https://$trustedHost/${siteLanguageFor(localeTag)}/$_coursePath/$level';

/// Whether [uri] is a course page — `<lang>/profile/my-courses/<level>`.
///
/// Deliberately strict, like [isRussianCourseVideoUri]: this drives the Home
/// highlight, and a loose match would light it up on unrelated course routes.
bool isCourseUri(Uri uri) {
  if (!isTrustedHttps(uri)) return false;
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  // <lang>/profile/my-courses/<level>
  if (segments.length != 4) return false;
  return supportedSiteLanguages.contains(segments[0]) &&
      '${segments[1]}/${segments[2]}' == _coursePath &&
      RegExp(r'^[1-9]\d*$').hasMatch(segments[3]);
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
