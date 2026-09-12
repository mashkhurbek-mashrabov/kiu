class Lesson {
  const Lesson({
    required this.title,
    required this.websiteStart,
    this.lessonId,
    this.meetingUrl,
  });

  final String title;
  final String websiteStart;
  final String? lessonId;
  final String? meetingUrl;

  String get key => lessonId ?? '$title|$websiteStart';

  /// Occurrence-unique key: [key] alone may repeat across occurrences of a
  /// recurring course, but a call alert must target one specific occurrence.
  String get callKey => '$key@$websiteStart';

  Map<String, Object> toJson() {
    final json = <String, Object>{'title': title, 'websiteStart': websiteStart};
    if (lessonId != null) json['lessonId'] = lessonId!;
    if (meetingUrl != null) json['meetingUrl'] = meetingUrl!;
    return json;
  }

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
    title: json['title'] as String,
    websiteStart: json['websiteStart'] as String,
    lessonId: json['lessonId'] as String?,
    meetingUrl: json['meetingUrl'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Lesson &&
      title == other.title &&
      websiteStart == other.websiteStart &&
      lessonId == other.lessonId &&
      meetingUrl == other.meetingUrl;

  @override
  int get hashCode => Object.hash(title, websiteStart, lessonId, meetingUrl);
}

enum ScheduleSyncStatus { idle, syncing, success, signInRequired, failed }

class ScheduleSnapshot {
  const ScheduleSnapshot({required this.lessons, required this.syncedAt});

  final List<Lesson> lessons;
  final DateTime syncedAt;
}
