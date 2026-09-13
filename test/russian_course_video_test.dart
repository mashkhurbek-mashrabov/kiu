import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';

void main() {
  group('isRussianCourseVideoUri', () {
    test('matches the course 8 video pages under either language', () {
      for (final url in const [
        'https://uz.do-kazankiu.ru/uz/my-course/8/33/video-iframe',
        'https://uz.do-kazankiu.ru/uz/my-course/8/17/video-iframe',
        'https://uz.do-kazankiu.ru/ru/my-course/8/17/video-iframe',
      ]) {
        expect(isRussianCourseVideoUri(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('leaves the course 8 non-video pages alone', () {
      for (final url in const [
        'https://uz.do-kazankiu.ru/uz/my-course/8/17/test',
        'https://uz.do-kazankiu.ru/uz/my-course/8/17',
        'https://uz.do-kazankiu.ru/uz/my-course/8',
      ]) {
        expect(isRussianCourseVideoUri(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('leaves every other course alone', () {
      for (final url in const [
        'https://uz.do-kazankiu.ru/uz/my-course/9/33/video-iframe',
        'https://uz.do-kazankiu.ru/uz/my-course/18/33/video-iframe',
        'https://uz.do-kazankiu.ru/uz/my-course/80/33/video-iframe',
      ]) {
        expect(isRussianCourseVideoUri(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('rejects untrusted hosts and plain http', () {
      for (final url in const [
        'https://evil.example/uz/my-course/8/33/video-iframe',
        'https://test.do-kazankiu.ru/uz/my-course/8/33/video-iframe',
        'http://uz.do-kazankiu.ru/uz/my-course/8/33/video-iframe',
      ]) {
        expect(isRussianCourseVideoUri(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });
}
