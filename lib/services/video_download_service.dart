import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../data/settings_repository.dart';
import '../domain/video_download.dart';
import 'app_version_service.dart';

typedef NativeDownloadStatus = ({
  int id,
  String status,
  int downloaded,
  int total,
  String? path,
});

/// The system download manager. A fake replaces it in tests.
abstract interface class VideoDownloadGateway {
  Future<int> enqueue({
    required Uri url,
    required String fileName,
    required String title,
  });
  Future<List<NativeDownloadStatus>> query(List<int> ids);
  Future<void> remove(List<int> ids);
}

class AndroidVideoDownloadGateway implements VideoDownloadGateway {
  @override
  Future<int> enqueue({
    required Uri url,
    required String fileName,
    required String title,
  }) async => (await platformChannel.invokeMethod<int>('enqueueVideoDownload', {
    'url': url.toString(),
    'fileName': fileName,
    'title': title,
  }))!;

  @override
  Future<List<NativeDownloadStatus>> query(List<int> ids) async {
    final rows =
        await platformChannel.invokeListMethod<Map<Object?, Object?>>(
          'queryVideoDownloads',
          {'ids': ids},
        ) ??
        const [];
    return [
      for (final row in rows)
        (
          id: row['id'] as int,
          status: row['status'] as String,
          downloaded: row['downloaded'] as int,
          total: row['total'] as int,
          path: row['path'] as String?,
        ),
    ];
  }

  @override
  Future<void> remove(List<int> ids) =>
      platformChannel.invokeMethod<void>('removeVideoDownloads', {'ids': ids});
}

/// Downloads lesson videos for offline viewing and serves the finished files
/// to the WebView over loopback, so the LMS's own player plays them.
///
/// State lives in [downloads], a [ValueNotifier]: `notifyListeners()` on the
/// controller would rebuild the WebView mid-lesson.
class VideoDownloadService {
  VideoDownloadService({
    required SettingsRepository repository,
    VideoDownloadGateway? gateway,
  }) : _repository = repository,
       _gateway = gateway ?? AndroidVideoDownloadGateway(),
       downloads = ValueNotifier(repository.loadVideoDownloads());

  final SettingsRepository _repository;
  final VideoDownloadGateway _gateway;
  final ValueNotifier<List<VideoDownload>> downloads;
  Timer? _poll;
  LocalVideoServer? _server;

  VideoDownload? entryFor(String key) {
    for (final entry in downloads.value) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  /// Starts a download, or does nothing if [key] already has one.
  ///
  /// Throws [ArgumentError] for a URL that is not a lesson MP4 on the LMS host.
  /// No cookies are sent: the files are static and public, so nothing of the
  /// session ever reaches the download manager.
  Future<void> start({
    required String key,
    required String title,
    required Uri lessonUrl,
    required Uri videoUrl,
  }) async {
    if (!isLessonVideoFile(videoUrl)) {
      throw ArgumentError.value(videoUrl, 'videoUrl', 'not a lesson video');
    }
    if (entryFor(key) != null) return;
    final id = await _gateway.enqueue(
      url: videoUrl,
      fileName: '${key.replaceAll('/', '-')}.mp4',
      title: title,
    );
    await _save([
      ...downloads.value,
      VideoDownload(
        key: key,
        title: title,
        lessonUrl: lessonUrl,
        downloadId: id,
        savedAt: DateTime.now(),
      ),
    ]);
    _ensurePolling();
  }

  /// Syncs [downloads] with the download manager: progress for running ones,
  /// the file for finished ones; failed ones and ones whose file is gone are
  /// dropped. Polls every second while anything is still running.
  Future<void> refresh() async {
    final current = downloads.value;
    if (current.isEmpty) return;
    final List<NativeDownloadStatus> rows;
    try {
      rows = await _gateway.query([for (final e in current) e.downloadId]);
    } on Exception {
      return;
    }
    final byId = {for (final row in rows) row.id: row};
    final queried = {for (final e in current) e.downloadId};
    final next = <VideoDownload>[];
    final dropped = <int>[];
    // Re-read after the await: a delete or a new download may have landed
    // meanwhile, and the snapshot must not undo it.
    for (final entry in downloads.value) {
      final row = byId[entry.downloadId];
      if (entry.done) {
        // The system list may forget a finished download; the file is what
        // matters.
        if (File(entry.path!).existsSync()) {
          next.add(entry);
        } else {
          dropped.add(entry.downloadId);
        }
      } else if (!queried.contains(entry.downloadId)) {
        next.add(entry);
      } else if (row == null || row.status == 'failed') {
        dropped.add(entry.downloadId);
      } else if (row.status == 'done' && row.path != null) {
        next.add(entry.copyWith(path: row.path, bytes: row.total));
      } else {
        next.add(entry.copyWith(received: row.downloaded, total: row.total));
      }
    }
    if (dropped.isNotEmpty) unawaited(_gateway.remove(dropped));
    await _save(next);
    if (next.any((entry) => !entry.done)) {
      _ensurePolling();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Cancels a running download or deletes a finished one's file.
  Future<void> delete(String key) async {
    final entry = entryFor(key);
    if (entry == null) return;
    await _gateway.remove([entry.downloadId]);
    await _save([
      for (final e in downloads.value)
        if (e.key != key) e,
    ]);
  }

  Future<void> deleteAll() async {
    final ids = [for (final e in downloads.value) e.downloadId];
    if (ids.isNotEmpty) await _gateway.remove(ids);
    await _save(const []);
  }

  /// The loopback URL the WebView can play [key]'s file from, or null when
  /// it is not downloaded yet.
  Future<Uri?> localUrl(String key) async {
    final entry = entryFor(key);
    if (entry == null || !entry.done) return null;
    final server = _server ??= LocalVideoServer(pathFor: _pathFor);
    return server.urlFor(key);
  }

  String? _pathFor(String key) => entryFor(key)?.path;

  void dispose() {
    _poll?.cancel();
    _poll = null;
    unawaited(_server?.close());
  }

  void _ensurePolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  Future<void> _save(List<VideoDownload> next) async {
    downloads.value = List.unmodifiable(next);
    await _repository.saveVideoDownloads(next);
  }
}

/// Serves downloaded files to the WebView at
/// `http://127.0.0.1:<port>/<token>/<course>/<lesson>`.
///
/// Bound to loopback only, and every path starts with a random 128-bit token,
/// so another app on the device cannot enumerate or read the files. Supports
/// `Range`, which the player needs to seek. Cleartext to 127.0.0.1 is allowed
/// by `network_security_config.xml`; every other host stays HTTPS-only.
class LocalVideoServer {
  LocalVideoServer({required String? Function(String key) pathFor})
    : _pathFor = pathFor;

  final String? Function(String key) _pathFor;
  final String _token = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<HttpServer>? _server;

  Future<Uri> urlFor(String key) async {
    final server = await (_server ??= _bind());
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/$_token/$key',
    );
  }

  Future<void> close() async => (await _server)?.close(force: true);

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_handle(request)));
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final path = segments.length == 3 && segments[0] == _token
          ? _pathFor('${segments[1]}/${segments[2]}')
          : null;
      final file = path == null ? null : File(path);
      if (file == null ||
          !file.existsSync() ||
          !const {'GET', 'HEAD'}.contains(request.method)) {
        response.statusCode = HttpStatus.notFound;
        return await response.close();
      }
      final length = await file.length();
      final range = parseByteRange(
        request.headers.value(HttpHeaders.rangeHeader),
        length,
      );
      response.headers
        ..contentType = ContentType('video', 'mp4')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (range == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        return await response.close();
      }
      final (start, end) = range;
      if (request.headers.value(HttpHeaders.rangeHeader) != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$length',
        );
      }
      response.contentLength = end - start + 1;
      if (request.method == 'HEAD') return await response.close();
      await response.addStream(file.openRead(start, end + 1));
      await response.close();
    } on Object {
      // The player aborts requests all the time while seeking; a closed
      // socket is not an error worth surfacing.
      try {
        await response.close();
      } on Object {
        // Already closed.
      }
    }
  }
}

/// The inclusive byte range a `Range` header asks for, the whole file when
/// [header] is null, or null when the range cannot be satisfied.
@visibleForTesting
(int, int)? parseByteRange(String? header, int length) {
  if (header == null) return length == 0 ? null : (0, length - 1);
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (match == null) return null;
  final from = int.tryParse(match[1]!);
  final to = int.tryParse(match[2]!);
  if (from == null) {
    // Suffix range: the last `to` bytes.
    if (to == null || to == 0) return null;
    return (max(0, length - to), length - 1);
  }
  if (from >= length) return null;
  final end = to == null ? length - 1 : min(to, length - 1);
  if (end < from) return null;
  return (from, end);
}
