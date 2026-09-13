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

  /// Tolerant counterpart to [Lesson.fromJson], for reading back a cached
  /// snapshot that may predate a schema change or have been truncated: returns
  /// null instead of throwing on anything unusable. Cached lessons are read
  /// during cold start, where a throw is an unrecoverable launch crash.
  static Lesson? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final title = json['title'];
    final websiteStart = json['websiteStart'];
    if (title is! String || title.isEmpty) return null;
    if (websiteStart is! String || websiteStart.isEmpty) return null;
    final lessonId = json['lessonId'];
    final meetingUrl = json['meetingUrl'];
    return Lesson(
      title: title,
      websiteStart: websiteStart,
      lessonId: lessonId is String ? lessonId : null,
      meetingUrl: meetingUrl is String ? meetingUrl : null,
    );
  }

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
