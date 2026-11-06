import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../domain/video_download.dart';
import '../l10n/app_localizations.dart';
import '../services/video_download_service.dart';
import 'widgets/settings_widgets.dart';

/// Settings → Downloaded videos: every downloaded or downloading lesson video,
/// with watch, delete and delete-all.
class DownloadedVideosPage extends StatelessWidget {
  const DownloadedVideosPage({
    super.key,
    required this.service,
    this.beforePlay,
  });

  final VideoDownloadService service;

  /// Runs before a video opens, so the lesson playing behind this page can be
  /// paused instead of talking over it.
  final VoidCallback? beforePlay;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ValueListenableBuilder<List<VideoDownload>>(
      valueListenable: service.downloads,
      builder: (context, downloads, _) => Scaffold(
        key: const Key('downloaded-videos-page'),
        appBar: AppBar(
          title: Text(strings.downloadedVideos),
          actions: [
            if (downloads.isNotEmpty)
              IconButton(
                key: const Key('delete-all-videos'),
                tooltip: strings.deleteAll,
                icon: const Icon(Icons.delete_sweep_rounded),
                onPressed: () async {
                  if (await _confirm(
                    context,
                    strings.deleteAllVideosQuestion,
                  )) {
                    await service.deleteAll();
                  }
                },
              ),
          ],
        ),
        body: downloads.isEmpty
            ? Center(
                key: const Key('downloaded-videos-empty'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.download_for_offline_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 14),
                    Text(strings.noDownloadedVideos),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  SettingsSection(
                    title: strings.downloadedVideos,
                    icon: Icons.download_for_offline_rounded,
                    children: [
                      for (final download in downloads.reversed)
                        _row(context, strings, download),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations strings,
    VideoDownload download,
  ) {
    final fraction = download.fraction;
    return SettingsRow(
      key: Key('downloaded-video-${download.key}'),
      icon: download.done
          ? Icons.play_circle_rounded
          : Icons.downloading_rounded,
      title: download.title,
      value: download.done
          ? formatBytes(download.bytes)
          : fraction == null
          ? strings.downloadingVideo
          : '${strings.downloadingVideo} ${(fraction * 100).round()}%',
      onTap: download.done ? () => _play(context, download) : null,
      trailing: IconButton(
        key: Key('delete-video-${download.key}'),
        tooltip: strings.remove,
        icon: const Icon(Icons.delete_outline_rounded, size: 20),
        onPressed: () async {
          if (await _confirm(
            context,
            download.done
                ? strings.deleteVideoQuestion
                : strings.cancelDownloadQuestion,
          )) {
            await service.delete(download.key);
          }
        },
      ),
    );
  }

  Future<void> _play(BuildContext context, VideoDownload download) async {
    final url = await service.localUrl(download.key);
    if (url == null || !context.mounted) return;
    beforePlay?.call();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfflineVideoPage(title: download.title, url: url),
      ),
    );
  }
}

/// Asks [question] with Cancel / Confirm; true only on Confirm.
Future<bool> _confirm(BuildContext context, String question) async {
  final strings = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.delete_outline_rounded),
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const Key('confirm-delete'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.confirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Confirms cancelling a running download from the lesson page's button.
Future<bool> confirmCancelDownload(BuildContext context) =>
    _confirm(context, AppLocalizations.of(context).cancelDownloadQuestion);

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).round()} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// Plays a downloaded video with no internet: a plain HTML5 `<video>` in its
/// own WebView, fed by the loopback server. The LMS page cannot be used here
/// because it needs the network to load at all.
class OfflineVideoPage extends StatefulWidget {
  const OfflineVideoPage({super.key, required this.title, required this.url});

  final String title;
  final Uri url;

  @override
  State<OfflineVideoPage> createState() => _OfflineVideoPageState();
}

class _OfflineVideoPageState extends State<OfflineVideoPage> {
  final WebViewController _webView = WebViewController();

  @override
  void initState() {
    super.initState();
    final platform = _webView.platform;
    // `autoplay` is ignored until this is off; the tap that opened the page
    // was the user's gesture.
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    final src = const HtmlEscape().convert('${widget.url}');
    _webView
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.black)
      ..loadHtmlString(
        '<!doctype html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#000}'
        'video{width:100%;height:100%;object-fit:contain}</style>'
        '</head><body>'
        '<video controls autoplay playsinline src="$src"></video>'
        '</body></html>',
      );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      // Explicit: the app bar theme's title style carries its own color,
      // which foregroundColor does not override.
      title: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white),
      ),
    ),
    body: SafeArea(child: WebViewWidget(controller: _webView)),
  );
}
