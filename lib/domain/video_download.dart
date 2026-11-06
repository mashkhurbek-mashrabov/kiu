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
