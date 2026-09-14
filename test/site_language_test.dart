import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';

void main() {
  group('siteLanguageFor', () {
    test('maps every non-Russian app locale to Uzbek', () {
      for (final localeTag in const ['uz_Cyrl', 'uz', 'en']) {
        expect(siteLanguageFor(localeTag), 'uz', reason: localeTag);
      }
    });

    test('maps Russian to Russian', () {
      expect(siteLanguageFor('ru'), 'ru');
    });
  });

  group('homeUrlFor', () {
    test('builds the lessons URL in the matching language', () {
      expect(
        homeUrlFor('ru'),
        'https://uz.do-kazankiu.ru/ru/profile/my-online-lessons',
      );
      expect(
        homeUrlFor('uz_Cyrl'),
        'https://uz.do-kazankiu.ru/uz/profile/my-online-lessons',
      );
    });

    test('never emits an English prefix the servers would accept blindly', () {
      expect(homeUrlFor('en'), isNot(contains('/en/')));
    });
  });

  group('isSiteHttps', () {
    test('accepts both of our hosts over HTTPS', () {
      expect(
        isSiteHttps(Uri.parse('https://uz.do-kazankiu.ru/uz/profile')),
        isTrue,
      );
      expect(
        isSiteHttps(Uri.parse('https://test.do-kazankiu.ru/uz/tests')),
        isTrue,
      );
    });

    test('rejects plaintext and look-alike hosts', () {
      for (final url in const [
        'http://test.do-kazankiu.ru/uz/tests',
        'https://test.do-kazankiu.ru.attacker.com/uz/tests',
        'https://eviltest.do-kazankiu.ru/uz/tests',
        'https://attacker.com/uz/tests',
      ]) {
        expect(isSiteHttps(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });

  group('trust split', () {
    test('the exam host is a site but never a privileged trusted host', () {
      final exam = Uri.parse('https://test.do-kazankiu.ru/uz/tests');
      expect(isSiteHttps(exam), isTrue);
      // Guards cookies, injected scripts and the KiuBridge channel: widening
      // this to the exam host would leak the LMS session there.
      expect(isTrustedHttps(exam), isFalse);
      expect(isHomeUri(exam), isFalse);
      expect(
        isLessonUri(Uri.parse('https://test.do-kazankiu.ru/uz/lesson/1')),
        isFalse,
      );
    });
  });

  group('withSiteLanguage', () {
    test('swaps the prefix on an LMS page, keeping the rest of the path', () {
      expect(
        withSiteLanguage(
          Uri.parse('https://uz.do-kazankiu.ru/uz/profile/lesson/42'),
          'ru',
        ).toString(),
        'https://uz.do-kazankiu.ru/ru/profile/lesson/42',
      );
    });

    test('swaps the prefix on the exam platform', () {
      expect(
        withSiteLanguage(
          Uri.parse('https://test.do-kazankiu.ru/uz/tests'),
          'ru',
        ).toString(),
        'https://test.do-kazankiu.ru/ru/tests',
      );
    });

    test('preserves query strings and fragments', () {
      expect(
        withSiteLanguage(
          Uri.parse('https://test.do-kazankiu.ru/ru/tests?page=2#top'),
          'uz',
        ).toString(),
        'https://test.do-kazankiu.ru/uz/tests?page=2#top',
      );
    });

    test('clamps English back to Uzbek rather than inventing /en/', () {
      expect(
        withSiteLanguage(
          Uri.parse('https://uz.do-kazankiu.ru/ru/profile/lesson/42'),
          'en',
        ).toString(),
        'https://uz.do-kazankiu.ru/uz/profile/lesson/42',
      );
    });

    test('leaves prefix-less and unknown-prefix paths untouched', () {
      for (final url in const [
        'https://test.do-kazankiu.ru/tests',
        'https://uz.do-kazankiu.ru/',
        'https://uz.do-kazankiu.ru/profile/my-online-lessons',
        'https://uz.do-kazankiu.ru/en/profile/my-online-lessons',
      ]) {
        expect(
          withSiteLanguage(Uri.parse(url), 'ru').toString(),
          url,
          reason: url,
        );
      }
    });

    test('leaves untrusted hosts untouched', () {
      const url = 'https://attacker.com/uz/tests';
      expect(withSiteLanguage(Uri.parse(url), 'ru').toString(), url);
    });
  });

  group('isHomeUri', () {
    test('matches the lessons page in either language', () {
      for (final url in const [
        'https://uz.do-kazankiu.ru/uz/profile/my-online-lessons',
        'https://uz.do-kazankiu.ru/ru/profile/my-online-lessons',
        'https://uz.do-kazankiu.ru/ru/profile/my-online-lessons/',
      ]) {
        expect(isHomeUri(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('does not match another page', () {
      expect(
        isHomeUri(Uri.parse('https://uz.do-kazankiu.ru/uz/profile/lesson/42')),
        isFalse,
      );
    });
  });

  group('courseUrlFor', () {
    test('uses the site language for the app locale', () {
      expect(
        courseUrlFor('ru', 2),
        'https://uz.do-kazankiu.ru/ru/profile/my-courses/2',
      );
      expect(
        courseUrlFor('uz_Cyrl', 13),
        'https://uz.do-kazankiu.ru/uz/profile/my-courses/13',
      );
      // English is not served, so it falls back to Uzbek like homeUrlFor.
      expect(courseUrlFor('en', 1), isNot(contains('/en/')));
    });
  });

  group('isCourseUri', () {
    test('matches a course page in either language', () {
      for (final url in const [
        'https://uz.do-kazankiu.ru/uz/profile/my-courses/2',
        'https://uz.do-kazankiu.ru/ru/profile/my-courses/13',
        'https://uz.do-kazankiu.ru/uz/profile/my-courses/2/',
      ]) {
        expect(isCourseUri(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('rejects a missing or non-positive level', () {
      for (final url in const [
        'https://uz.do-kazankiu.ru/uz/profile/my-courses',
        'https://uz.do-kazankiu.ru/uz/profile/my-courses/0',
        'https://uz.do-kazankiu.ru/uz/profile/my-courses/x',
        'https://uz.do-kazankiu.ru/uz/profile/my-courses/2/lesson',
      ]) {
        expect(isCourseUri(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('rejects another host, the exam site, and plain http', () {
      for (final url in const [
        'https://attacker.com/uz/profile/my-courses/2',
        'https://test.do-kazankiu.ru/uz/profile/my-courses/2',
        'http://uz.do-kazankiu.ru/uz/profile/my-courses/2',
        'https://uz.do-kazankiu.ru/en/profile/my-courses/2',
      ]) {
        expect(isCourseUri(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });
}
