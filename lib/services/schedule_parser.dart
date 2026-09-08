import 'package:html/parser.dart' as html_parser;

import '../core/constants.dart';
import '../domain/lesson.dart';

class ScheduleParseResult {
  const ScheduleParseResult({
    required this.hasScheduleContainer,
    required this.lessons,
  });

  final bool hasScheduleContainer;
  final List<Lesson> lessons;
}

class ScheduleParser {
  static final _datePattern = RegExp(r'\b(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\b');

  ScheduleParseResult parse(String source) {
    final document = html_parser.parse(source);
    final container = document.querySelector(
      '#enroll-courses, .enroll-courses',
    );
    if (container == null) {
      return const ScheduleParseResult(
        hasScheduleContainer: false,
        lessons: [],
      );
    }

    final lessons = <String, Lesson>{};
    for (final card in container.querySelectorAll('.course-box')) {
      final title = card
          .querySelector('h3.title.instructor-text a')
          ?.text
          .trim();
      final dateTexts = card
          .querySelectorAll('.course-view p')
          .map((element) => element.text.trim());
      final match = dateTexts
          .map(_datePattern.firstMatch)
          .whereType<RegExpMatch>()
          .firstOrNull;
      if (title == null || title.isEmpty || match == null) continue;
      final visit = card.querySelector('[data-visit-online-lesson][data-href]');
      final lessonId = _lessonId(visit?.attributes['data-visit-online-lesson']);
      final meetingUrl = _meetingUrl(visit?.attributes['data-href']);
      final lesson = Lesson(
        title: title,
        websiteStart: match.group(1)!,
        lessonId: lessonId,
        meetingUrl: meetingUrl,
      );
      lessons[lesson.key] = lesson;
    }
    return ScheduleParseResult(
      hasScheduleContainer: true,
      lessons: lessons.values.toList(growable: false),
    );
  }

  String? _lessonId(String? value) {
    final normalized = value?.trim();
    if (normalized == null ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  String? _meetingUrl(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final parsed = Uri.tryParse(normalized);
    if (parsed == null) return null;
    final uri = Uri.parse(homeUrl).resolveUri(parsed);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri.toString();
  }
}
