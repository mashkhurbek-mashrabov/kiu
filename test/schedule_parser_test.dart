import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/services/schedule_parser.dart';

void main() {
  const fixture = '''
  <div class="enroll-courses">
    <div class="course-box">
      <h3 class="title instructor-text"><a>Imtihon - Tahfiz</a></h3>
      <div class="course-view d-flex align-items-center"><p>2026-09-09 19:00</p></div>
    </div>
    <div class="course-box">
      <h3 class="title instructor-text"><a>Imtihon - Tahfiz</a></h3>
      <div class="course-view"><p>2026-09-09 19:00</p></div>
    </div>
    <div class="course-box"><h3 class="title instructor-text"><a>Incomplete</a></h3></div>
  </div>
  ''';

  test('parses and deduplicates LMS lesson cards', () {
    final result = ScheduleParser().parse(fixture);
    expect(result.hasScheduleContainer, isTrue);
    expect(result.lessons, hasLength(1));
    expect(result.lessons.single.title, 'Imtihon - Tahfiz');
    expect(result.lessons.single.websiteStart, '2026-09-09 19:00');
  });

  test('distinguishes login page from an empty authenticated schedule', () {
    expect(
      ScheduleParser().parse('<form id="login"></form>').hasScheduleContainer,
      isFalse,
    );
    final empty = ScheduleParser().parse('<div class="enroll-courses"></div>');
    expect(empty.hasScheduleContainer, isTrue);
    expect(empty.lessons, isEmpty);
  });

  test('accepts live id container and extracts validated visit data', () {
    const source = '''
      <div id="enroll-courses"><div class="course-box">
        <h3 class="title instructor-text"><a>Tafsir</a></h3>
        <div class="course-view"><p>2026-09-10 08:30</p></div>
        <button data-visit-online-lesson="lesson_42"
          data-href="/uz/profile/online-lesson/42">Join</button>
      </div></div>
    ''';
    final lesson = ScheduleParser().parse(source).lessons.single;
    expect(lesson.lessonId, 'lesson_42');
    expect(
      lesson.meetingUrl,
      'https://uz.do-kazankiu.ru/uz/profile/online-lesson/42',
    );
  });

  test('drops malformed lesson ids and unsafe meeting links', () {
    const source = '''
      <div id="enroll-courses"><div class="course-box">
        <h3 class="title instructor-text"><a>Tafsir</a></h3>
        <div class="course-view"><p>2026-09-10 08:30</p></div>
        <button data-visit-online-lesson="bad id"
          data-href="javascript:alert(1)">Join</button>
      </div></div>
    ''';
    final lesson = ScheduleParser().parse(source).lessons.single;
    expect(lesson.lessonId, isNull);
    expect(lesson.meetingUrl, isNull);
  });
}
