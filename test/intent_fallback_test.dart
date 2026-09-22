import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';

void main() {
  group('intentFallbackUrl', () {
    test('recovers the Meet link a dynamic-link handoff wraps', () {
      // The exact URL the LMS join button reaches after Meet redirects twice.
      final uri = Uri.parse(
        'intent://meet.app.goo.gl/?link=https://meet.google.com/abc-defg-hij'
        '&apn=com.google.android.apps.tachyon&isi=1096918571'
        '&ibi=com.google.Tachyon#Intent;package=com.google.android.gms;'
        'action=com.google.firebase.dynamiclinks.VIEW_DYNAMIC_LINK;'
        'scheme=https;S.browser_fallback_url=https://play.google.com/store/'
        'apps/details%3Fid%3Dcom.google.android.apps.tachyon;end;',
      );
      // The meeting itself, not the Play Store listing: Android routes this to
      // the Meet app when installed and to the browser when it is not.
      expect(
        intentFallbackUrl(uri).toString(),
        'https://meet.google.com/abc-defg-hij',
      );
    });

    test('falls back to the declared web URL when there is no link=', () {
      final uri = Uri.parse(
        'intent://example.com/#Intent;package=com.example;'
        'S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fweb;end;',
      );
      expect(intentFallbackUrl(uri).toString(), 'https://example.com/web');
    });

    test('skips a non-https link= and still takes a usable fallback', () {
      final uri = Uri.parse(
        'intent://x/?link=market%3A%2F%2Fdetails%3Fid%3Dx#Intent;'
        'S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fweb;end;',
      );
      expect(intentFallbackUrl(uri).toString(), 'https://example.com/web');
    });

    test('ignores anything that is not an intent URL', () {
      for (final url in const [
        'https://meet.google.com/abc-defg-hij',
        'meet://call',
        'javascript:alert(1)',
      ]) {
        expect(intentFallbackUrl(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('returns null for an intent URL carrying no fallback', () {
      final uri = Uri.parse(
        'intent://scan/#Intent;package=com.zxing;scheme=zxing;end;',
      );
      expect(intentFallbackUrl(uri), isNull);
    });

    test('refuses a fallback that is not plain https', () {
      // The fragment is page content, so a hostile site controls this value.
      for (final fallback in const [
        'javascript:alert(1)',
        'file:///sdcard/Download/evil.apk',
        'http://example.com',
        'https://user:pass@example.com',
        'https:///nohost',
      ]) {
        final encoded = Uri.encodeComponent(fallback);
        expect(
          intentFallbackUrl(
            Uri.parse(
              'intent://x/#Intent;S.browser_fallback_url=$encoded;end;',
            ),
          ),
          isNull,
          reason: 'fallback $fallback',
        );
        // Same rule for the wrapped destination, which is read first.
        expect(
          intentFallbackUrl(Uri.parse('intent://x/?link=$encoded#Intent;end;')),
          isNull,
          reason: 'link $fallback',
        );
      }
    });
  });
}
