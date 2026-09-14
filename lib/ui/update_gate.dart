import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_downloader.dart';
import '../services/update_service.dart';
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
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.update.notes,
                          style: theme.textTheme.bodySmall,
                        ),
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
