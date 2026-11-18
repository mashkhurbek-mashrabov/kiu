import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// One downloaded (or downloading) lesson video.
///
/// [path] is set once the system download finishes; until then the entry is
/// in progress and [received] / [total] carry the live byte counts, which are
/// never persisted.
@immutable
class VideoDownload {
  const VideoDownload({
    required this.key,
    required this.title,
    required this.lessonUrl,
    required this.downloadId,
    required this.savedAt,
    this.path,
    this.bytes = 0,
    this.received = 0,
    this.total = 0,
  });

  /// `"<course>/<lesson>"`, from [videoDownloadKey].
  final String key;
  final String title;
  final Uri lessonUrl;
  final int downloadId;
  final DateTime savedAt;
  final String? path;
  final int bytes;
  final int received;
  final int total;

  bool get done => path != null;

  /// 0..1, or null while the size is still unknown.
  double? get fraction => total > 0 ? (received / total).clamp(0, 1) : null;

  VideoDownload copyWith({
    String? path,
    int? bytes,
    int? received,
    int? total,
  }) => VideoDownload(
    key: key,
    title: title,
    lessonUrl: lessonUrl,
    downloadId: downloadId,
    savedAt: savedAt,
    path: path ?? this.path,
    bytes: bytes ?? this.bytes,
    received: received ?? this.received,
    total: total ?? this.total,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'lessonUrl': lessonUrl.toString(),
    'downloadId': downloadId,
    'savedAt': savedAt.millisecondsSinceEpoch,
    'path': path,
    'bytes': bytes,
  };

  /// Null for anything unusable, so one bad entry never breaks the list.
  static VideoDownload? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final title = json['title'];
    final lessonUrl = json['lessonUrl'];
    final downloadId = json['downloadId'];
    final savedAt = json['savedAt'];
    final path = json['path'];
    final bytes = json['bytes'];
    if (key is! String ||
        title is! String ||
        lessonUrl is! String ||
        downloadId is! int ||
        savedAt is! int ||
        (path != null && path is! String) ||
        bytes is! int) {
      return null;
    }
    final uri = Uri.tryParse(lessonUrl);
    if (uri == null || videoDownloadKey(uri) != key) return null;
    return VideoDownload(
      key: key,
      title: title,
      lessonUrl: uri,
      downloadId: downloadId,
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
      path: path as String?,
      bytes: bytes,
    );
  }
}

/// The downloads of one course, for the grouped Downloaded videos list.
typedef CourseDownloads = ({
  String courseId,
  String? courseName,
  List<VideoDownload> videos,
});

/// Groups [downloads] by course and sorts courses and lessons by name.
///
/// [courseNames] maps a course id to the name the "my courses" page shows; a
/// course missing from it keeps a null name and sorts after the named ones,
/// by id. Names compare with [compareNatural], so "10. …" follows "9. …".
List<CourseDownloads> groupDownloadsByCourse(
  List<VideoDownload> downloads,
  Map<String, String> courseNames,
) {
  final byCourse = <String, List<VideoDownload>>{};
  for (final download in downloads) {
    final courseId = download.key.split('/').first;
    (byCourse[courseId] ??= []).add(download);
  }
  final groups = [
    for (final entry in byCourse.entries)
      (
        courseId: entry.key,
        courseName: courseNames[entry.key],
        videos: entry.value..sort((a, b) => compareNatural(a.title, b.title)),
      ),
  ];
  groups.sort((a, b) {
    final aName = a.courseName;
    final bName = b.courseName;
    if (aName != null && bName != null) return compareNatural(aName, bName);
    if (aName != null) return -1;
    if (bName != null) return 1;
    return compareNatural(a.courseId, b.courseId);
  });
  return groups;
}

final RegExp _naturalChunk = RegExp(r'\d+|\D+');

/// Case-insensitive comparison that orders digit runs by value, so lesson
/// titles numbered "2." and "10." sort as a person would read them.
int compareNatural(String a, String b) {
  final aChunks = _naturalChunk.allMatches(a.toLowerCase()).toList();
  final bChunks = _naturalChunk.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < aChunks.length && i < bChunks.length; i++) {
    final x = aChunks[i][0]!;
    final y = bChunks[i][0]!;
    final xNumber = int.tryParse(x);
    final yNumber = int.tryParse(y);
    final order = xNumber != null && yNumber != null
        ? xNumber.compareTo(yNumber)
        : x.compareTo(y);
    if (order != 0) return order;
  }
  return aChunks.length.compareTo(bChunks.length);
}
