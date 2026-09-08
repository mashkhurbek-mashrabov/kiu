import 'dart:convert';
import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

import '../core/constants.dart';
import '../domain/lesson.dart';
import 'schedule_parser.dart';

abstract interface class CookieProvider {
  Future<Map<String, String>> cookiesFor(Uri uri);
}

class AndroidCookieProvider implements CookieProvider {
  AndroidCookieProvider({WebViewCookieManager? manager})
    : _manager = manager ?? WebViewCookieManager();

  final WebViewCookieManager _manager;

  @override
  Future<Map<String, String>> cookiesFor(Uri uri) async {
    if (!isTrustedHttps(uri)) return const {};
    final values = await _manager.getCookies(domain: uri);
    return {for (final cookie in values) cookie.name: cookie.value};
  }
}

class ScheduleFetchException implements Exception {
  const ScheduleFetchException(this.code);
  final String code;
}

class ScheduleFetcher {
  ScheduleFetcher({
    required CookieProvider cookieProvider,
    ScheduleParser? parser,
    HttpClient? client,
  }) : _cookieProvider = cookieProvider,
       _parser = parser ?? ScheduleParser(),
       _client = client ?? HttpClient();

  final CookieProvider _cookieProvider;
  final ScheduleParser _parser;
  final HttpClient _client;

  Future<List<Lesson>> fetch({String? userAgent}) async {
    final uri = Uri.parse(homeUrl);
    final cookies = await _cookieProvider.cookiesFor(uri);
    if (cookies.isEmpty) throw const ScheduleFetchException('auth');

    final request = await _client.getUrl(uri);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.cookieHeader,
      cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '),
    );
    if (userAgent != null && userAgent.isNotEmpty) {
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      final target = location == null ? null : uri.resolve(location);
      if (target == null || !isTrustedHttps(target)) {
        throw const ScheduleFetchException('redirect');
      }
      throw const ScheduleFetchException('auth');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw ScheduleFetchException('http_${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    final parsed = _parser.parse(body);
    if (!parsed.hasScheduleContainer) {
      throw const ScheduleFetchException('auth');
    }
    return parsed.lessons;
  }

  void close() => _client.close(force: true);
}
