import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';

void main() {
  const lesson = 'https://uz.do-kazankiu.ru/uz/profile/my-online-lessons';

  test('Android hands over a trusted HTTPS page directly', () {
    expect(widgetLaunchTarget(Uri.parse(lesson)), Uri.parse(lesson));
  });

  test('iOS carries the page in the kiu:// target parameter', () {
    final uri = Uri(
      scheme: 'kiu',
      host: 'open',
      queryParameters: {'homeWidget': '1', 'target': lesson},
    );
    expect(widgetLaunchTarget(uri), Uri.parse(lesson));
  });

  test('a plain reopen or sync link navigates nowhere', () {
    expect(
      widgetLaunchTarget(Uri.parse('kiu://widget-sync?homeWidget=1')),
      isNull,
    );
    expect(widgetLaunchTarget(null), isNull);
  });

  test('a target off the trusted host is refused', () {
    for (final target in [
      'https://evil.example/uz/profile',
      'http://uz.do-kazankiu.ru/uz/profile',
      'https://uz.do-kazankiu.ru.evil.example/',
    ]) {
      final uri = Uri(
        scheme: 'kiu',
        host: 'open',
        queryParameters: {'target': target},
      );
      expect(widgetLaunchTarget(uri), isNull, reason: target);
    }
    expect(widgetLaunchTarget(Uri.parse('https://evil.example/')), isNull);
  });
}
