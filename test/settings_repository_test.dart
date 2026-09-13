import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/domain/lesson.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Corrupt or outdated stored state must degrade to a default, never throw:
/// `loadSettings` runs in `AppController`'s initializer list and in the
/// WorkManager background isolate, where a throw is an unrecoverable launch
/// crash with no way for the user to clear the bad value.
Future<SettingsRepository> repositoryWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsRepository(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadLessons survives a corrupt snapshot', () {
    test('object stored where a list is expected', () async {
      final repository = await repositoryWith({
        'kiu.lessonSnapshot': '{"not":"a list"}',
      });
      expect(repository.loadLessons(), isEmpty);
    });

    test('unparsable JSON', () async {
      final repository = await repositoryWith({
        'kiu.lessonSnapshot': 'not json at all',
      });
      expect(repository.loadLessons(), isEmpty);
    });

    test(
      'drops entries missing required fields, keeps the good ones',
      () async {
        final repository = await repositoryWith({
          'kiu.lessonSnapshot':
              '[{"websiteStart":"2026-09-09 19:00"},'
              '{"title":"Tafsir","websiteStart":"2026-09-10 08:30"},'
              '{"title":"","websiteStart":"2026-09-11 08:30"},'
              '"a bare string"]',
        });
        final lessons = repository.loadLessons();
        expect(lessons, hasLength(1));
        expect(lessons.single.title, 'Tafsir');
      },
    );

    test(
      'ignores wrongly typed optional fields rather than throwing',
      () async {
        final repository = await repositoryWith({
          'kiu.lessonSnapshot':
              '[{"title":"Tafsir","websiteStart":"2026-09-10 08:30",'
              '"lessonId":42,"meetingUrl":null}]',
        });
        final lesson = repository.loadLessons().single;
        expect(lesson.lessonId, isNull);
        expect(lesson.meetingUrl, isNull);
      },
    );
  });

  group('loadSettings survives corrupt reminder offsets', () {
    test('non-numeric entry is dropped, valid ones survive', () async {
      final repository = await repositoryWith({
        'kiu.reminderOffsets': <String>['60', 'garbage', '15'],
      });
      expect(repository.loadSettings().reminderOffsetsMinutes, [60, 15]);
    });

    test('falls back to defaults when nothing is stored', () async {
      final repository = await repositoryWith({});
      expect(repository.loadSettings().reminderOffsetsMinutes, [60, 0]);
    });
  });

  test('round-trips a saved snapshot unchanged', () async {
    final repository = await repositoryWith({});
    const lessons = [
      Lesson(
        title: 'Tafsir',
        websiteStart: '2026-09-10 08:30',
        lessonId: 'lesson_42',
        meetingUrl: 'https://uz.do-kazankiu.ru/uz/profile/online-lesson/42',
      ),
    ];
    await repository.saveLessons(lessons);
    expect(repository.loadLessons(), lessons);
  });
}
