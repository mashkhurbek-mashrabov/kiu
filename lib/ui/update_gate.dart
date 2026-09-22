import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_downloader.dart';
import '../services/update_service.dart';
import 'widgets/release_notes.dart';
import 'widgets/settings_widgets.dart';

/// Full-screen block shown while a mandatory update is pending.
///
/// A screen rather than a dialog on purpose: a dialog sits over a live
/// `BrowserPage`, which keeps loading the LMS behind the barrier and can be
/// dismissed by a system back gesture. Replacing `home:` is the only way the
/// block is actually a block.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.update, required this.downloader});

  final AppUpdate update;
  final UpdateDownloader downloader;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      // The whole point of the gate: a back gesture must not reach the app.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    size: 56,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          strings.updateRequired,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Long prose lives behind the hint, never as wrapped
                      // body text under the title.
                      InfoHint(message: strings.updateRequiredHelp),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.updateVersion(widget.update.versionName),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (widget.update.notes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    // Collapsed by default: the gate's job is to get the user
                    // updated, and a wall of notes pushes the button down and
                    // buries the one action that matters. Anyone who wants the
                    // detail can open it.
                    Material(
                      color: colors.surfaceContainerLow,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: ExpansionTile(
                        key: const Key('update-notes'),
                        title: Text(
                          strings.whatsNew,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        shape: const RoundedRectangleBorder(),
                        collapsedShape: const RoundedRectangleBorder(),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          14,
                        ),
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ReleaseNotes(widget.update.notes),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  UpdateActionButton(
                    update: widget.update,
                    downloader: widget.downloader,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Download button that turns into a progress bar, and back into a retry on
/// failure. Shared by the mandatory gate and the optional-update sheet so both
/// behave identically once the download starts.
class UpdateActionButton extends StatelessWidget {
  const UpdateActionButton({
    super.key,
    required this.update,
    required this.downloader,
  });

  final AppUpdate update;
  final UpdateDownloader downloader;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // ValueListenableBuilder, not setState on an ancestor: rebuilding above
    // this point would take the WebView down with it.
    return ValueListenableBuilder<UpdateDownloadProgress>(
      valueListenable: downloader.progress,
      builder: (context, progress, _) {
        switch (progress.stage) {
          case UpdateDownloadStage.downloading:
            final fraction = progress.total > 0
                ? progress.received / progress.total
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: fraction, minHeight: 8),
                ),
                const SizedBox(height: 10),
                Text(
                  '${strings.downloadingUpdate}  ${_megabytes(progress.received)} / ${_megabytes(progress.total)} MB',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            );
          case UpdateDownloadStage.installing:
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  child: LinearProgressIndicator(minHeight: 8),
                ),
                const SizedBox(height: 10),
                Text(
                  strings.installingUpdate,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            );
          case UpdateDownloadStage.failed:
            // A mandatory gate with no way back would be a bricked app, so a
            // failed download always offers another attempt.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.updateFailed,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('update-retry'),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(strings.retry),
                  onPressed: () => downloader.download(update),
                ),
              ],
            );
          case UpdateDownloadStage.idle:
            return FilledButton.icon(
              key: const Key('update-now'),
              icon: const Icon(Icons.download_rounded),
              label: Text(strings.updateNow),
              onPressed: () => downloader.download(update),
            );
        }
      },
    );
  }

  String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}

/// The compact form of [UpdateActionButton], sized to sit in a settings row's
/// trailing slot.
///
/// The gate can afford a full-width button and a progress bar; a row cannot.
/// Here the button collapses to an icon once a download starts, and the bar
/// moves to the row's subtitle — see [updateRowStatus].
class UpdateRowButton extends StatelessWidget {
  const UpdateRowButton({
    super.key,
    required this.update,
    required this.downloader,
  });

  final AppUpdate update;
  final UpdateDownloader downloader;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ValueListenableBuilder<UpdateDownloadProgress>(
      valueListenable: downloader.progress,
      builder: (context, progress, _) => switch (progress.stage) {
        // Nothing to press while bytes are moving: the subtitle is already
        // reporting, and a live button invites a second download.
        UpdateDownloadStage.downloading ||
        UpdateDownloadStage.installing => const SizedBox.shrink(),
        UpdateDownloadStage.failed => IconButton(
          key: const Key('update-row-retry'),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: strings.retry,
          onPressed: () => downloader.download(update),
        ),
        UpdateDownloadStage.idle => FilledButton(
          key: const Key('update-row-now'),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () => downloader.download(update),
          child: Text(strings.updateNow),
        ),
      },
    );
  }
}

/// The row subtitle while an update is pending: the version, then the progress
/// bar once a download starts.
Widget updateRowStatus(
  AppUpdate update,
  UpdateDownloader downloader,
  AppLocalizations strings,
) {
  return ValueListenableBuilder<UpdateDownloadProgress>(
    valueListenable: downloader.progress,
    builder: (context, progress, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final caption = theme.textTheme.bodySmall;
      switch (progress.stage) {
        case UpdateDownloadStage.downloading:
        case UpdateDownloadStage.installing:
          final downloading = progress.stage == UpdateDownloadStage.downloading;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: downloading && progress.total > 0
                      ? progress.received / progress.total
                      : null,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                downloading
                    ? strings.downloadingUpdate
                    : strings.installingUpdate,
                style: caption?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          );
        case UpdateDownloadStage.failed:
          return Text(
            strings.updateFailed,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: caption?.copyWith(color: colors.error),
          );
        case UpdateDownloadStage.idle:
          return Text(
            strings.updateVersion(update.versionName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: caption?.copyWith(color: colors.onSurfaceVariant),
          );
      }
    },
  );
}
