import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app/app_controller.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../domain/app_settings.dart';
import '../domain/lesson.dart';
import '../l10n/app_localizations.dart';
import '../services/lesson_widget_service.dart';
import '../services/time_zone_service.dart';
import '../web/js_scripts.dart';
import 'widgets/settings_widgets.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.controller,
    required this.homeRequests,
    this.navigationRequests,
  });

  final AppController controller;
  final ValueNotifier<int> homeRequests;
  final ValueNotifier<Uri?>? navigationRequests;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  late final WebViewController _webView;
  Timer? _foregroundTimer;
  late Uri _currentUri;
  int _progress = 0;
  bool _canBack = false;
  bool _canForward = false;
  bool _pageFailed = false;
  bool _marking = false;
  bool _fullscreenOpen = false;
  bool _backgroundPromptOpen = false;
  bool _checking = false;

  /// Outcome of the last manual update check, shown in the row itself. Cleared
  /// when the sheet reopens so a stale answer never reads as a fresh one.
  String? _checkResult;
  double _pullDistance = 0;
  Timer? _pullWatchdog;
  Completer<Map<String, dynamic>>? _markCompleter;
  String? _markRequestId;

  AppLocalizations get strings => AppLocalizations.of(context);

  String get _homeUrl => homeUrlFor(widget.controller.settings.localeTag);

  Brightness get _brightness =>
      resolveDark(widget.controller.settings.themeMode)
      ? Brightness.dark
      : Brightness.light;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.homeRequests.addListener(_goHome);
    widget.navigationRequests?.addListener(_goToRequestedPage);
    final requestedUri = widget.navigationRequests?.value;
    final initialUri = requestedUri != null && isTrustedHttps(requestedUri)
        ? requestedUri
        : Uri.parse(_homeUrl);
    _currentUri = initialUri;
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(surfaceFor(_brightness))
      ..addJavaScriptChannel(
        'KiuBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigation,
          onPageStarted: _pageStarted,
          onPageFinished: _pageFinished,
          onProgress: (value) =>
              mounted ? setState(() => _progress = value) : null,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _pageFailed = true);
            }
          },
          onUrlChange: (change) {
            final uri = Uri.tryParse(change.url ?? '');
            if (uri != null && mounted) setState(() => _currentUri = uri);
          },
        ),
      )
      ..loadRequest(initialUri);
    _configureAndroidVideo();
    _startForegroundSync();
  }

  void _configureAndroidVideo() {
    final platform = _webView.platform;
    if (platform is! AndroidWebViewController) return;
    platform.setMediaPlaybackRequiresUserGesture(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: (video, onHide) {
          if (!mounted || _fullscreenOpen) return;
          _fullscreenOpen = true;
          Navigator.of(context)
              .push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => ColoredBox(color: Colors.black, child: video),
                ),
              )
              .whenComplete(() {
                _fullscreenOpen = false;
                onHide();
              });
        },
        onHideCustomWidget: () {
          if (_fullscreenOpen && mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      );
    });
  }

  void _startForegroundSync() {
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _synchronize(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startForegroundSync();
      _synchronize();
      // The user may have just granted a permission in Android settings.
      unawaited(widget.controller.refreshBackgroundAccess());
      // Throttled to 6h inside the controller, so resuming repeatedly costs
      // nothing. Catches an update published while the app sat backgrounded.
      unawaited(widget.controller.checkForUpdate());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foregroundTimer?.cancel();
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.controller.settings.themeMode != ThemeMode.system) return;
    if (mounted) setState(() {});
    unawaited(_applySiteTheme());
    unawaited(widget.controller.refreshWidget());
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri != null && uri.scheme == 'https') {
      return NavigationDecision.navigate;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.unsupportedLink)));
      }
    });
    return NavigationDecision.prevent;
  }

  void _pageStarted(String url) {
    final uri = Uri.tryParse(url);
    _pullWatchdog?.cancel();
    setState(() {
      if (uri != null) _currentUri = uri;
      _pageFailed = false;
      _progress = 0;
      _pullDistance = 0;
    });
  }

  Future<void> _pageFinished(String url) async {
    final uri = Uri.tryParse(url);
    _canBack = await _webView.canGoBack();
    _canForward = await _webView.canGoForward();
    if (uri != null && isTrustedHttps(uri)) {
      await _applyPlaybackRate();
      await _applySiteTheme();
      await _webView.runJavaScript(
        pullToRefreshScript(thresholdPx: _pullThreshold.round()),
      );
      if (isRussianCourseVideoUri(uri)) {
        await _webView.runJavaScript(videoIframeFixScript());
      }
      if (isHomeUri(uri)) {
        unawaited(_synchronize());
        unawaited(_maybeExplainBackgroundAccess());
      }
    }
    if (mounted) {
      setState(() {
        if (uri != null) _currentUri = uri;
        _progress = 100;
      });
    }
  }

  Future<void> _applyPlaybackRate() async {
    if (!isTrustedHttps(_currentUri)) return;
    await _webView.runJavaScript(
      playbackRateScript(widget.controller.settings.playbackRate),
    );
  }

  /// Mirrors the app theme onto the LMS page: recolors the WebView so page
  /// transitions do not flash the opposite theme, then nudges the site's own
  /// dark-mode toggle when it disagrees with the app.
  Future<void> _applySiteTheme() async {
    final brightness = _brightness;
    await _webView.setBackgroundColor(surfaceFor(brightness));
    if (!isTrustedHttps(_currentUri)) return;
    await _webView.runJavaScript(
      siteThemeScript(brightness == Brightness.dark),
    );
  }

  Future<void> _setPlaybackRate(double rate) async {
    await widget.controller.setPlaybackRate(rate);
    await _applyPlaybackRate();
    if (mounted) setState(() {});
  }

  /// Switches the site over to the app's language by reloading the current
  /// page with its language prefix swapped, which also makes the server
  /// persist the choice for later navigation. Unlike the theme and playback
  /// scripts this runs on the exam platform too, so both sites follow the
  /// language; it injects nothing and only ever rewrites one of our own URLs.
  Future<void> _applySiteLanguage() async {
    final target = withSiteLanguage(
      _currentUri,
      widget.controller.settings.localeTag,
    );
    if (target == _currentUri) return;
    await _webView.loadRequest(target);
  }

  Future<void> _goHome() => _webView.loadRequest(Uri.parse(_homeUrl));

  Future<void> _goToRequestedPage() async {
    final uri = widget.navigationRequests?.value;
    if (uri != null && isTrustedHttps(uri)) await _webView.loadRequest(uri);
  }

  Future<void> _synchronize() async {
    String? userAgent;
    try {
      userAgent = await _webView.getUserAgent();
    } on PlatformException {
      userAgent = null;
    }
    await widget.controller.synchronize(userAgent: userAgent);
  }

  Future<void> _maybeExplainBackgroundAccess() async {
    if (_backgroundPromptOpen ||
        !widget.controller.shouldShowBackgroundExplainer ||
        !mounted) {
      return;
    }
    _backgroundPromptOpen = true;
    await widget.controller.markBackgroundExplainerShown();
    if (!mounted) return;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.battery_saver_rounded),
        title: Text(strings.backgroundAccess),
        content: Text(strings.backgroundAccessHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(strings.openSettings),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await widget.controller.openBatteryOptimizationSettings();
    }
    _backgroundPromptOpen = false;
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    if (!isTrustedHttps(_currentUri)) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type'] == 'pullRefresh') {
        _handlePullRefresh(decoded);
        return;
      }
      if (decoded['type'] != 'markWatchedResult' ||
          decoded['requestId'] != _markRequestId ||
          decoded['ok'] is! bool ||
          decoded['code'] is! String) {
        return;
      }
      if (!(_markCompleter?.isCompleted ?? true)) {
        _markCompleter!.complete(decoded);
      }
    } on FormatException {
      return;
    }
  }

  /// Distance past which a release reloads. Also the point the indicator
  /// stops following the finger, so "it stopped moving" reads as "let go now".
  static const double _pullThreshold = 90;

  /// Renders the pull reported by [pullToRefreshScript] and reloads on a
  /// release past the threshold. The page only ever reports the gesture; the
  /// reload decision stays here.
  void _handlePullRefresh(Map<String, dynamic> message) {
    if (!mounted) return;
    final phase = message['phase'];
    final distance = message['distance'];
    if (phase == 'move' && distance is num) {
      _armPullWatchdog();
      setState(() => _pullDistance = distance.toDouble());
      return;
    }
    _pullWatchdog?.cancel();
    final release = phase == 'end' && _pullDistance >= _pullThreshold;
    setState(() => _pullDistance = 0);
    if (release) unawaited(_webView.reload());
  }

  /// Clears the indicator when a pull stops reporting without ever ending.
  ///
  /// The page cannot always deliver a final `touchend`: lifting the finger
  /// outside the WebView, or the system claiming the gesture mid-drag, ends
  /// the touch stream silently. Without this the spinner sits on screen until
  /// the next navigation. Re-armed on every `move`, so it only fires once the
  /// drag has genuinely stopped feeding us.
  void _armPullWatchdog() {
    _pullWatchdog?.cancel();
    _pullWatchdog = Timer(const Duration(milliseconds: 600), () {
      if (mounted && _pullDistance > 0) setState(() => _pullDistance = 0);
    });
  }

  Future<void> _markWatched() async {
    if (_marking || !isLessonUri(_currentUri)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.onlyLesson)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.task_alt_rounded),
        title: Text(strings.markWatched),
        content: Text(strings.markWatchedQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _marking = true);
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    _markRequestId = requestId;
    _markCompleter = Completer<Map<String, dynamic>>();
    try {
      await _webView.runJavaScript(markWatchedScript(requestId));
      final result = await _markCompleter!.future.timeout(
        const Duration(seconds: 25),
      );
      if (!mounted) return;
      if (result['ok'] == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.marked)));
        await _webView.reload();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.markFailed}: ${result['code']}')),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.markFailed)));
      }
    } finally {
      _markCompleter = null;
      _markRequestId = null;
      if (mounted) setState(() => _marking = false);
    }
  }

  /// Main settings sheet.
  ///
  /// Grouped into sections rather than one flat list: playback sits at the top
  /// because it is the only control used mid-lesson, and everything a user
  /// touches once during setup sinks below it.
  Future<void> _openActions() async {
    var selected = widget.controller.settings.playbackRate;
    // A result from a previous visit would otherwise read as the answer to a
    // check the user has not run yet.
    _checkResult = null;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final settings = widget.controller.settings;
          // Read before SafeArea consumes it, so the scroll view can still pad
          // for the system bar; inside, viewPadding is already zero.
          final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      strings.settings,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      // Sections carry no bottom padding of their own, so the
                      // last row would end flush with the scroll extent and be
                      // clipped by the sheet's rounded edge -- on a short
                      // screen it could not be tapped at all. The system-bar
                      // inset is added on top because SafeArea sizes the sheet
                      // without padding this scroll view.
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 36 + bottomInset),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _playbackSection(selected, (rate) {
                            selected = rate;
                            setSheetState(() {});
                          }),
                          SettingsSection(
                            title: strings.sectionLessons,
                            icon: Icons.school_rounded,
                            children: [
                              SettingsRow(
                                key: const Key('mark-watched-menu'),
                                icon: Icons.task_alt_rounded,
                                title: _marking
                                    ? strings.marking
                                    : strings.markWatchedShort,
                                enabled: !_marking,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _markWatched();
                                },
                              ),
                              SettingsRow(
                                key: const Key('scheduled-lessons-menu'),
                                icon: Icons.calendar_month_rounded,
                                title: strings.scheduledLessons,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openScheduledLessons();
                                },
                              ),
                              SettingsRow(
                                key: const Key('notification-settings-menu'),
                                icon: Icons.notifications_active_rounded,
                                title: strings.notificationSettings,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openNotificationSettings();
                                },
                              ),
                            ],
                          ),
                          SettingsSection(
                            title: strings.sectionAppearance,
                            icon: Icons.palette_rounded,
                            children: [
                              _themeModeRow(setSheetState),
                              SettingsRow(
                                key: const Key('language-menu'),
                                icon: Icons.translate_rounded,
                                title: strings.language,
                                value: _languageLabel(settings.localeTag),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _selectLanguage();
                                },
                              ),
                              SettingsRow(
                                key: const Key('timezone-menu'),
                                icon: Icons.public_rounded,
                                title: strings.timezone,
                                value: settings.timeZoneId,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _selectTimeZone();
                                },
                              ),
                            ],
                          ),
                          SettingsSection(
                            title: strings.sectionResources,
                            icon: Icons.auto_stories_rounded,
                            children: [
                              SettingsRow(
                                key: const Key('useful-links-menu'),
                                icon: Icons.bookmarks_rounded,
                                title: strings.usefulLinks,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openUsefulLinks();
                                },
                              ),
                              // Also listed inside Useful links, but questions
                              // and problem reports are common enough to earn
                              // a row in the main sheet rather than two taps.
                              SettingsRow(
                                key: const Key('contact-developer'),
                                icon: Icons.telegram_rounded,
                                title: strings.feedback,
                                value: contactHandle,
                                trailing: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 20,
                                ),
                                onTap: () => _launchExternal(contactUrl),
                              ),
                            ],
                          ),
                          _aboutSection(setSheetState),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Playback speed. Presets as chips plus a fine slider, kept at the top of
  /// the sheet because it is the one control reached while a lesson plays.
  Widget _playbackSection(double selected, ValueChanged<double> onSelected) {
    final theme = Theme.of(context);
    return SettingsSection(
      title: strings.sectionPlayback,
      icon: Icons.play_circle_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SettingsLeading(Icons.speed_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.videoSpeed,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // Live read-out, so the slider needs no separate value label.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${selected.toStringAsFixed(2)}×',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <double>[1, 1.5, 1.7, 2, 2.5]
                    .map(
                      (rate) => ChoiceChip(
                        label: Text(
                          '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}×',
                        ),
                        selected: (selected - rate).abs() < 0.01,
                        onSelected: (_) async {
                          onSelected(rate);
                          await _setPlaybackRate(rate);
                        },
                      ),
                    )
                    .toList(),
              ),
              Slider(
                value: selected.clamp(0.5, 4.0).toDouble(),
                min: 0.5,
                max: 4,
                divisions: 70,
                label: '${selected.toStringAsFixed(2)}×',
                onChanged: onSelected,
                onChangeEnd: _setPlaybackRate,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Theme as three icon segments rather than a dialog: the choice is small,
  /// mutually exclusive and reads faster as sun/moon/auto than as words.
  ///
  /// Label above, segments below. Side by side the three segments claim their
  /// natural width first and leave the label so little room that a word like
  /// "Кўриниш" wraps to one character per line.
  Widget _themeModeRow(StateSetter setSheetState) {
    final mode = widget.controller.settings.themeMode;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        key: const Key('theme-mode-menu'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SettingsLeading(Icons.brightness_6_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.appearance,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Current mode in words: the icons alone do not say which of
              // the three is active for someone who does not know them.
              Text(
                _themeModeLabel(mode),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              InfoHint(message: strings.themeSystemHelp),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              // Icons only: three translated labels do not fit across the
              // sheet width, and the active mode is already named in the row
              // above. Tooltips carry the name for anyone unsure of an icon.
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.brightness_auto_rounded, size: 20),
                tooltip: strings.themeSystem,
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_rounded, size: 20),
                tooltip: strings.themeLight,
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_rounded, size: 20),
                tooltip: strings.themeDark,
              ),
            ],
            selected: {mode},
            onSelectionChanged: (values) async {
              await widget.controller.setThemeMode(values.first);
              await _applySiteTheme();
              setSheetState(() {});
            },
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => strings.themeSystem,
    ThemeMode.light => strings.themeLight,
    ThemeMode.dark => strings.themeDark,
  };

  Future<void> _openScheduledLessons() async {
    final returnToActions = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final settings = widget.controller.settings;
          final colors = Theme.of(context).colorScheme;
          // Re-read inside the builder so "Sync now" can refresh the list in
          // place rather than showing the snapshot the sheet opened with.
          final scheduledLessons = widget.controller.scheduledLessons;
          final lessons = buildLessonWidgetPayload(
            scheduledLessons,
            settings,
            TimeZoneService(),
          );
          final lessonsByKey = {
            for (final lesson in scheduledLessons) lesson.callKey: lesson,
          };
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: strings.scheduledLessons,
                    backTooltip: strings.back,
                    backKey: const Key('scheduled-lessons-back'),
                  ),
                  _lessonsSyncBar(setSheetState),
                  Expanded(
                    child: lessons.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_busy_rounded,
                                  size: 44,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  strings.noScheduledLessons,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            key: const Key('scheduled-lessons-list'),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: lessons.length,
                            itemBuilder: (context, index) {
                              final lesson = lessons[index];
                              final startsGroup =
                                  index == 0 ||
                                  lesson['group'] !=
                                      lessons[index - 1]['group'];
                              final lessonEntity = lessonsByKey[lesson['key']];
                              final callOn =
                                  lessonEntity != null &&
                                  settings.callEnabledFor(lessonEntity);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (startsGroup)
                                    _lessonGroupHeader(
                                      lesson['group']! as String,
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Card(
                                      child: ListTile(
                                        key: Key('scheduled-lesson-$index'),
                                        contentPadding:
                                            const EdgeInsets.fromLTRB(
                                              12,
                                              6,
                                              6,
                                              6,
                                            ),
                                        // A call that is armed gets a filled
                                        // accent so the list scans for "which
                                        // lessons will ring" at a glance.
                                        leading: SettingsLeading(
                                          Icons.play_lesson_rounded,
                                          color: callOn
                                              ? colors.primary
                                              : colors.onSurfaceVariant,
                                          active: callOn,
                                        ),
                                        title: Text(
                                          lesson['title']! as String,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          lesson['displayStart']! as String,
                                        ),
                                        // Phone icon rather than a switch, matching
                                        // the home-screen widget's per-row toggle.
                                        trailing: lessonEntity == null
                                            ? null
                                            : _LessonCallToggle(
                                                key: Key(
                                                  'scheduled-lesson-call-$index',
                                                ),
                                                enabled: callOn,
                                                tooltip:
                                                    strings.callForThisLesson,
                                                onPressed: () async {
                                                  await widget.controller
                                                      .setLessonCallEnabled(
                                                        lessonEntity,
                                                        !callOn,
                                                      );
                                                  setSheetState(() {});
                                                },
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (returnToActions == true && mounted) _openActions();
  }

  /// Last-sync line plus a manual trigger, above the lesson list.
  ///
  /// Listens to the sync notifier directly rather than going through
  /// `notifyListeners()`, which would rebuild the whole app including the
  /// WebView. Rebuilding the sheet on completion refreshes the list itself,
  /// since the payload is read inside the sheet's builder.
  Widget _lessonsSyncBar(StateSetter setSheetState) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ValueListenableBuilder<
      ({ScheduleSyncStatus status, DateTime? lastSuccessfulSync})
    >(
      valueListenable: widget.controller.syncState,
      builder: (context, syncState, _) {
        final syncing = syncState.status == ScheduleSyncStatus.syncing;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(
            color: colors.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: InkWell(
              key: const Key('scheduled-lessons-sync'),
              onTap: syncing
                  ? null
                  : () async {
                      await _synchronize();
                      if (mounted) setSheetState(() {});
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _syncStatusText(
                          syncState.status,
                          syncState.lastSuccessfulSync,
                          timeOnly: true,
                        ),
                        // Two lines: the timestamp is the point of this row,
                        // and "Last sync: <date>" does not fit on one line
                        // beside the button in any of the four languages.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Icon-only trigger: the label doubled the row's width and
                    // squeezed the timestamp it sits next to into an ellipsis.
                    if (syncing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    else
                      Tooltip(
                        message: strings.syncNow,
                        child: Icon(
                          Icons.sync_rounded,
                          size: 20,
                          color: colors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Day separator in the lesson list. Label plus a rule, mirroring the
  /// home-screen widget's group header so both lists read the same way.
  Widget _lessonGroupHeader(String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    final customController = TextEditingController();
    var customUnitHours = false;
    var backgroundAccessRefreshStarted = false;
    final returnToMainSettings = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (!backgroundAccessRefreshStarted) {
            backgroundAccessRefreshStarted = true;
            // Fire-and-forget: the sheet must render immediately rather
            // than block on a platform channel round trip, so the
            // permission tiles appear a frame later once this resolves.
            widget.controller.refreshBackgroundAccess().then((_) {
              if (mounted) setSheetState(() {});
            });
          }
          final settings = widget.controller.settings;
          final offsets = settings.reminderOffsetsMinutes.toSet();
          Future<void> toggleOffset(int value, bool enabled) async {
            enabled ? offsets.add(value) : offsets.remove(value);
            await widget.controller.setReminderOffsets(offsets.toList());
            setSheetState(() {});
          }

          final customOffsets =
              offsets
                  .where((value) => !{180, 60, 15, 0}.contains(value))
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: strings.notificationSettings,
                    backTooltip: strings.back,
                    backKey: const Key('notification-settings-back'),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SettingsSection(
                            title: strings.sectionNotifications,
                            icon: Icons.notifications_rounded,
                            children: [
                              SettingsSwitchRow(
                                icon: Icons.notifications_active_rounded,
                                title: strings.reminders,
                                hint: strings.remindersHelp,
                                value: settings.remindersEnabled,
                                onChanged: (value) async {
                                  await widget.controller.setRemindersEnabled(
                                    value,
                                  );
                                  setSheetState(() {});
                                },
                              ),
                              SettingsRow(
                                key: const Key('notification-sound-settings'),
                                icon: Icons.music_note_rounded,
                                title: strings.sound,
                                value: settings.reminderSoundUri == null
                                    ? strings.defaultSound
                                    : settings.reminderSoundName ??
                                          strings.soundSelected,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                // Close this sheet first: the sound page
                                // reopens it on the way back, and leaving it
                                // mounted would stack a second copy.
                                onTap: () {
                                  Navigator.pop(context);
                                  _openSoundSettings();
                                },
                              ),
                            ],
                          ),
                          _reminderTimesSection(
                            settings: settings,
                            offsets: offsets,
                            customOffsets: customOffsets,
                            toggleOffset: toggleOffset,
                            customController: customController,
                            customUnitHours: customUnitHours,
                            onUnitChanged: (value) =>
                                setSheetState(() => customUnitHours = value),
                            setSheetState: setSheetState,
                          ),
                          _callsSection(settings, setSheetState),
                          _permissionsSection(settings, setSheetState),
                          _syncSection(settings, setSheetState),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    customController.dispose();
    if (returnToMainSettings == true && mounted) {
      await _openActions();
    }
  }

  /// Reminder offsets.
  ///
  /// Explicit toggle rows rather than chips: a chip's selected state is a
  /// subtle fill change that reads as styling, not as on/off, so there was no
  /// way to tell at a glance which reminders would actually fire. Each row now
  /// carries a check/circle icon, a bold label when active, and the section
  /// caption states how many are on.
  Widget _reminderTimesSection({
    required AppSettings settings,
    required Set<int> offsets,
    required List<int> customOffsets,
    required Future<void> Function(int, bool) toggleOffset,
    required TextEditingController customController,
    required bool customUnitHours,
    required ValueChanged<bool> onUnitChanged,
    required StateSetter setSheetState,
  }) {
    final enabled = settings.remindersEnabled;
    final theme = Theme.of(context);
    return SettingsSection(
      title: strings.sectionReminderTimes,
      icon: Icons.alarm_rounded,
      hint: strings.reminderTimesHelp,
      // No count: each row already shows its own switch, so a tally beside the
      // caption just repeats what is directly below it. The disabled marker
      // stays — that state is not visible from the rows alone.
      trailing: enabled
          ? null
          : Text(
              strings.off.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
      children: [
        for (final option in <(int, String)>[
          (180, strings.threeHours),
          (60, strings.oneHour),
          (15, strings.fifteenMinutes),
          (0, strings.atStart),
        ])
          _reminderOffsetRow(
            key: Key('reminder-offset-${option.$1}'),
            label: option.$2,
            on: offsets.contains(option.$1),
            enabled: enabled,
            onTap: () => toggleOffset(option.$1, !offsets.contains(option.$1)),
          ),
        // Custom offsets are the same row, plus a delete: they are removable
        // where the presets are only switchable.
        for (final value in customOffsets)
          _reminderOffsetRow(
            key: Key('reminder-custom-$value'),
            label: _reminderOffsetLabel(value),
            on: true,
            enabled: enabled,
            onTap: () => toggleOffset(value, false),
            onDelete: () => toggleOffset(value, false),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Unit picker on its own line: "Minutes"/"Hours" translate to
              // much wider words (Дақиқа, Минуты), which overflowed the row
              // when it also held the field and the add button.
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            strings.minutes,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                            strings.hours,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      selected: {customUnitHours},
                      onSelectionChanged: enabled
                          ? (values) => onUnitChanged(values.first)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: customController,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: strings.customReminder,
                        hintText: '1–168',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('reminder-add'),
                    tooltip: strings.add,
                    onPressed: enabled
                        ? () async {
                            final amount = int.tryParse(customController.text);
                            if (amount == null || amount < 1) return;
                            final minutes = customUnitHours
                                ? amount * 60
                                : amount;
                            if (minutes > 10080) return;
                            offsets.add(minutes);
                            await widget.controller.setReminderOffsets(
                              offsets.toList(),
                            );
                            customController.clear();
                            setSheetState(() {});
                          }
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              if (!enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    strings.remindersTooltip,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One reminder offset: on/off state plus, for custom offsets, a delete.
  Widget _reminderOffsetRow({
    required Key key,
    required String label,
    required bool on,
    required bool enabled,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = on && enabled;
    return ListTile(
      key: key,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minVerticalPadding: 10,
      shape: const RoundedRectangleBorder(),
      leading: SettingsLeading(
        active ? Icons.notifications_active_rounded : Icons.circle_outlined,
        active: active,
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          // Weight carries the state as well as color, so it survives a
          // grayscale screenshot and low-vision use.
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: enabled
              ? (active ? colors.onSurface : colors.onSurfaceVariant)
              : colors.onSurface.withValues(alpha: 0.38),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDelete != null)
            IconButton(
              tooltip: strings.remove,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: enabled ? onDelete : null,
            ),
          Switch(value: active, onChanged: enabled ? (_) => onTap() : null),
        ],
      ),
    );
  }

  /// Lesson calls: the master switch plus the two knobs it gates.
  Widget _callsSection(AppSettings settings, StateSetter setSheetState) {
    final on = settings.callsEnabled;
    return SettingsSection(
      title: strings.sectionCalls,
      icon: Icons.phone_in_talk_rounded,
      children: [
        SettingsSwitchRow(
          key: const Key('lesson-calls-switch'),
          icon: Icons.ring_volume_rounded,
          title: strings.lessonCalls,
          hint: strings.lessonCallsHelp,
          value: on,
          onChanged: (value) async {
            await widget.controller.setCallsEnabled(value);
            setSheetState(() {});
          },
        ),
        SettingsRow(
          key: const Key('call-ring-duration'),
          icon: Icons.timer_rounded,
          title: strings.ringDuration,
          hint: strings.ringDurationHelp,
          value: strings.ringDurationValue(settings.callRingSeconds),
          enabled: on,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            await _openCallRingDurationDialog(settings);
            setSheetState(() {});
          },
        ),
        SettingsRow(
          key: const Key('call-ringtone'),
          icon: Icons.music_note_rounded,
          title: strings.callRingtone,
          value: settings.callRingtoneName ?? strings.defaultSound,
          enabled: on,
          trailing: on && settings.callRingtoneUri != null
              ? IconButton(
                  key: const Key('call-ringtone-reset'),
                  tooltip: strings.defaultSound,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  onPressed: () async {
                    await widget.controller.clearCallRingtone();
                    setSheetState(() {});
                  },
                )
              : const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            await widget.controller.selectCallRingtone();
            setSheetState(() {});
          },
        ),
      ],
    );
  }

  /// Android permissions. Grouped together because they share one shape — the
  /// app cannot grant them, it can only deep-link to the system screen.
  ///
  /// Every row is listed whether or not it is granted, each with a
  /// granted/not-granted badge. Hiding the granted ones (as this used to do
  /// for full-screen access) left no way to confirm a permission was actually
  /// in place, so a working setup looked identical to a missing row.
  Widget _permissionsSection(AppSettings settings, StateSetter setSheetState) {
    final controller = widget.controller;
    return SettingsSection(
      title: strings.sectionPermissions,
      icon: Icons.shield_rounded,
      children: [
        _permissionRow(
          key: const Key('battery-access'),
          icon: Icons.battery_saver_rounded,
          title: strings.backgroundAccess,
          hint: strings.backgroundAccessHelp,
          granted: controller.batteryOptimizationDisabled,
          onTap: () async {
            await controller.openBatteryOptimizationSettings();
            setSheetState(() {});
          },
        ),
        _permissionRow(
          key: const Key('exact-timing'),
          icon: Icons.alarm_on_rounded,
          title: strings.exactTiming,
          hint: strings.exactTimingHelp,
          granted: controller.exactTiming,
          onTap: () async {
            await controller.requestExactTiming();
            setSheetState(() {});
          },
        ),
        if (settings.callsEnabled) ...[
          _permissionRow(
            key: const Key('full-screen-access'),
            icon: Icons.fullscreen_rounded,
            title: strings.fullScreenAccess,
            hint: strings.fullScreenAccessHelp,
            granted: controller.canUseFullScreenIntent,
            onTap: () async {
              await controller.openFullScreenIntentSettings();
              setSheetState(() {});
            },
          ),
          // Android grants this one only from its own settings screen, so
          // tapping deep-links there rather than toggling anything locally.
          _permissionRow(
            key: const Key('overlay-access-tile'),
            icon: Icons.picture_in_picture_alt_rounded,
            title: strings.overlayAccess,
            hint: strings.overlayAccessHelp,
            granted: controller.canDrawOverlays,
            onTap: () async {
              await controller.openOverlaySettings();
              setSheetState(() {});
            },
          ),
        ],
      ],
    );
  }

  /// One permission row: status badge plus a link out to the system screen
  /// that owns the setting.
  Widget _permissionRow({
    required Key key,
    required IconData icon,
    required String title,
    required String hint,
    required bool granted,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SettingsRow(
      key: key,
      icon: icon,
      title: title,
      hint: hint,
      // A missing permission is the row worth noticing, so only that state
      // takes the warning tint.
      iconColor: granted ? colors.primary : colors.error,
      // The badge is the row's status, so it sits under the title rather than
      // beside it: as a trailing widget it squeezed long permission names into
      // a dozen wrapped lines.
      valueWidget: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: PermissionBadge(
            granted: granted,
            grantedLabel: strings.granted,
            deniedLabel: strings.notGranted,
          ),
        ),
      ),
      trailing: Icon(
        Icons.open_in_new_rounded,
        size: 18,
        color: colors.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }

  /// Background sync plus the manual trigger and its status.
  Widget _syncSection(AppSettings settings, StateSetter setSheetState) =>
      SettingsSection(
        title: strings.sectionSync,
        icon: Icons.sync_rounded,
        children: [
          SettingsSwitchRow(
            key: const Key('background-sync-switch'),
            icon: Icons.cloud_sync_rounded,
            title: strings.backgroundSync,
            hint: strings.backgroundSyncHelp,
            value: settings.backgroundSyncEnabled,
            onChanged: (value) async {
              await widget.controller.setBackgroundSyncEnabled(value);
              setSheetState(() {});
            },
          ),
          // Listens to the sync notifier directly: this row is the only thing
          // sync progress renders, so a background sync repaints it alone
          // instead of the whole app.
          ValueListenableBuilder<
            ({ScheduleSyncStatus status, DateTime? lastSuccessfulSync})
          >(
            valueListenable: widget.controller.syncState,
            builder: (context, syncState, _) => SettingsRow(
              key: const Key('sync-now'),
              icon: Icons.sync_rounded,
              title: strings.syncNow,
              value: _syncStatusText(
                syncState.status,
                syncState.lastSuccessfulSync,
              ),
              trailing: syncState.status == ScheduleSyncStatus.syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.refresh_rounded),
              onTap: _synchronize,
            ),
          ),
        ],
      );

  /// Version plus the manual update check.
  ///
  /// The version used to be a bare centered `Text` under the last section;
  /// promoting it to a real section gives the update check somewhere to live
  /// that matches every other row in the sheet.
  Widget _aboutSection(StateSetter setSheetState) {
    final version = widget.controller.appVersion;
    return SettingsSection(
      title: strings.sectionAbout,
      icon: Icons.info_rounded,
      children: [
        if (version != null)
          SettingsRow(
            key: const Key('app-version'),
            icon: Icons.badge_rounded,
            title: strings.version,
            value: '${version.name} (${version.code})',
          ),
        // Listens to the check notifier for the same reason the sync row does:
        // a check firing on resume repaints this row alone.
        ValueListenableBuilder<DateTime?>(
          valueListenable: widget.controller.updateCheckState,
          builder: (context, lastChecked, _) => SettingsRow(
            key: const Key('check-updates'),
            icon: Icons.system_update_rounded,
            title: strings.checkForUpdates,
            value: switch ((_checking, _checkResult)) {
              (true, _) => strings.checking,
              (_, final result?) => result,
              _ => strings.lastChecked(
                lastChecked == null
                    ? strings.never
                    : DateFormat('dd.MM.yyyy HH:mm').format(lastChecked),
              ),
            },
            trailing: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded),
            onTap: _checking ? null : () => _checkForUpdates(setSheetState),
          ),
        ),
      ],
    );
  }

  Future<void> _checkForUpdates(StateSetter setSheetState) async {
    setSheetState(() => _checking = true);
    await widget.controller.checkForUpdate(force: true);
    if (!mounted) return;
    final update = widget.controller.availableUpdate.value;
    setSheetState(() {
      _checking = false;
      // Shown in the row rather than as a snack bar. The sheet is 88% of the
      // screen and a snack bar renders at the very bottom, so on a short
      // device it came up *behind* the sheet and the user saw nothing until
      // they backed out -- by which point it no longer explained itself.
      _checkResult = update == null
          ? strings.upToDate
          : strings.updateAvailable;
    });
  }

  /// Sync status line.
  ///
  /// With [timeOnly] the date is dropped for a sync that happened today —
  /// the lessons sheet is a glance-and-go surface where "14:32" is the whole
  /// answer. An older sync keeps its date, otherwise yesterday's stale sync
  /// would read as if it had just run.
  String _syncStatusText(
    ScheduleSyncStatus status,
    DateTime? lastSync, {
    bool timeOnly = false,
  }) {
    if (status == ScheduleSyncStatus.syncing) return strings.syncing;
    if (status == ScheduleSyncStatus.signInRequired) {
      return strings.signInToSync;
    }
    if (status == ScheduleSyncStatus.failed) return strings.syncFailed;
    if (lastSync == null) return strings.lastSync(strings.never);
    final now = DateTime.now();
    final isToday =
        lastSync.year == now.year &&
        lastSync.month == now.month &&
        lastSync.day == now.day;
    final pattern = timeOnly && isToday ? 'HH:mm' : 'yyyy-MM-dd HH:mm';
    return strings.lastSync(DateFormat(pattern).format(lastSync));
  }

  String _reminderOffsetLabel(int minutes) {
    if (minutes < 60) return '$minutes ${strings.minutes}';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0
        ? '$hours ${strings.hours}'
        : '$hours ${strings.hours} $remainder ${strings.minutes}';
  }

  Future<void> _openCallRingDurationDialog(AppSettings settings) async {
    final customController = TextEditingController();
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.timer_rounded),
        title: Text(strings.ringDuration),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <int>[15, 30, 60, 120]
                  .map(
                    (seconds) => ChoiceChip(
                      label: Text(strings.ringDurationValue(seconds)),
                      selected: settings.callRingSeconds == seconds,
                      onSelected: (_) => Navigator.pop(context, seconds),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: strings.custom,
                      hintText: '10–300',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: strings.add,
                  onPressed: () {
                    final amount = int.tryParse(customController.text);
                    if (amount == null) return;
                    Navigator.pop(context, amount);
                  },
                  icon: const Icon(Icons.check_rounded),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
        ],
      ),
    );
    customController.dispose();
    if (selected != null) {
      await widget.controller.setCallRingSeconds(selected);
    }
  }

  /// Opens the sound page, then returns to the notification sheet it was
  /// reached from — same reasoning as [_openUsefulLinks].
  Future<void> _openSoundSettings() async {
    await _pushSoundSettings();
    if (mounted) await _openNotificationSettings();
  }

  Future<void> _pushSoundSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => StatefulBuilder(
        builder: (context, setPageState) {
          final settings = widget.controller.settings;
          final offsets = settings.reminderOffsetsMinutes.toSet().toList()
            ..sort((a, b) => b.compareTo(a));
          return Scaffold(
            appBar: AppBar(title: Text(strings.soundSettings)),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                SettingsSection(
                  title: strings.mainSound,
                  icon: Icons.volume_up_rounded,
                  children: [
                    SettingsRow(
                      key: const Key('main-notification-sound'),
                      icon: Icons.library_music_rounded,
                      title: strings.mainSound,
                      value: settings.reminderSoundUri == null
                          ? strings.defaultSound
                          : settings.reminderSoundName ?? strings.soundSelected,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Only offered once a custom sound is set; with none
                          // there is nothing to reset back to.
                          if (settings.reminderSoundUri != null)
                            IconButton(
                              key: const Key('main-notification-sound-reset'),
                              tooltip: strings.defaultSound,
                              icon: const Icon(
                                Icons.settings_backup_restore_rounded,
                              ),
                              onPressed: () async {
                                await widget.controller.clearReminderSound();
                                setPageState(() {});
                              },
                            ),
                          TextButton(
                            onPressed: () async {
                              await widget.controller.selectMainReminderSound();
                              setPageState(() {});
                            },
                            child: Text(strings.chooseSound),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SettingsSection(
                  title: strings.individualSounds,
                  icon: Icons.queue_music_rounded,
                  hint: strings.soundOverridesHelp,
                  children: [
                    for (final offset in offsets)
                      _reminderSoundOverrideTile(
                        offset,
                        settings,
                        () => setPageState(() {}),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  /// Opens Useful links, then returns to the main settings sheet.
  ///
  /// The sheet is already dismissed by the time this page is pushed, so
  /// popping it would otherwise drop the user straight onto the WebView —
  /// looking like Back had closed settings entirely.
  Future<void> _openUsefulLinks() async {
    await _pushUsefulLinks();
    if (mounted) await _openActions();
  }

  Future<void> _pushUsefulLinks() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(strings.usefulLinks)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            SettingsSection(
              title: strings.pdfBooks,
              icon: Icons.menu_book_rounded,
              children: [
                // Not const: the last two titles are descriptive rather than
                // proper nouns, so they come from the localizations.
                for (final link in [
                  (
                    'E\'tiqod durdonalari',
                    'https://uz.do-kazankiu.ru/files/upload/books/2024-10-19-17-14-55_51415d09fa306b663e1d1f9ba25f8bf6.pdf',
                  ),
                  (
                    'Nurul Izoh',
                    'https://uz.do-kazankiu.ru/files/upload/books/2026-09-03-13-50-07_dcf4732467d276aa.pdf',
                  ),
                  (
                    'Mabdaul qiroat 1',
                    'https://arabic.uz/kitoblar/mabdaul-qiroat-1.pdf',
                  ),
                  (
                    'Mabdaul qiroat 2',
                    'https://arabic.uz/kitoblar/mabdaul-qiroat-2.pdf',
                  ),
                  (
                    'Mabdaul qiroat 3',
                    'https://arabic.uz/kitoblar/mabdaul-qiroat-3.pdf',
                  ),
                  (
                    'Mabdaun nahv',
                    'https://arabic.uz/kitoblar/mabdaun-nahv-tugrilangan-va-tuldirilgan.pdf',
                  ),
                  (
                    strings.bookRussianDictionary,
                    'https://drive.google.com/file/d/1U6uYlS2ae3QHUYBtW7DXOi4MLjCFjr1M/view',
                  ),
                  (
                    strings.bookRussianLessons,
                    'https://drive.google.com/file/d/1lKshAbXGkmOPuojCpaVz_z5XlAoZTKNw/view?usp=sharing',
                  ),
                ])
                  SettingsRow(
                    icon: Icons.picture_as_pdf_rounded,
                    title: link.$1,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openPdfViewer(link.$1, link.$2),
                  ),
              ],
            ),
            SettingsSection(
              title: strings.testPlatforms,
              icon: Icons.quiz_rounded,
              children: [
                for (final link in const [
                  ('ibodati-islomiya.com', 'https://ibodati-islomiya.com'),
                  ('nurul-izoh.com', 'https://nurul-izoh.com'),
                  ('etiqod-durdonalari.xyz', 'https://etiqod-durdonalari.xyz'),
                  (
                    'mukammal-sarf-darsligi',
                    'https://mukammal-sarf-darsligi-app.netlify.app',
                  ),
                  (
                    'ar-rahiq-al-maxtum',
                    'https://ar-rahiq-al-maxtum.netlify.app',
                  ),
                ])
                  SettingsRow(
                    icon: Icons.language_rounded,
                    title: link.$1,
                    // Leaves the app: the arrow marks it as an external hop
                    // rather than another in-app page.
                    trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                    onTap: () => _launchExternal(link.$2),
                  ),
              ],
            ),
            SettingsSection(
              title: strings.apps,
              icon: Icons.apps_rounded,
              children: [
                for (final link in const [
                  (
                    'Riyozus solihiyn',
                    'https://play.google.com/store/apps/details?id=uz.hilolnashr.riyozus_solihiyn',
                  ),
                  (
                    'Odoblar xazinasi',
                    'https://play.google.com/store/apps/details?id=uz.hilol.odoblar',
                  ),
                  (
                    'Arabcha-O‘zbekcha lug‘at',
                    'https://play.google.com/store/apps/details?id=uz.hilal.javohir',
                  ),
                ])
                  SettingsRow(
                    icon: Icons.shop_rounded,
                    title: link.$1,
                    trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                    onTap: () => _launchExternal(link.$2),
                  ),
              ],
            ),
            SettingsSection(
              title: strings.feedback,
              icon: Icons.chat_bubble_outline_rounded,
              children: [
                SettingsRow(
                  icon: Icons.telegram_rounded,
                  title: contactHandle,
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => _launchExternal(contactUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _launchExternal(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// Maps a `drive.google.com/file/d/<id>/...` share link to its read-only
  /// `/preview` embed, or returns null for anything else.
  ///
  /// Matches on the parsed host so a lookalike path on another domain cannot
  /// pose as Drive, and drops the trailing segment rather than trusting it.
  static String? _drivePreviewUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri?.host != 'drive.google.com') return null;
    final segments = uri!.pathSegments;
    if (segments.length < 3 || segments[0] != 'file' || segments[1] != 'd') {
      return null;
    }
    final id = segments[2];
    return id.isEmpty ? null : 'https://drive.google.com/file/d/$id/preview';
  }

  /// Opens [pdfUrl] in a throwaway WebView using Google's public docs
  /// viewer. Uses its own [WebViewController] — no cookies or trusted-host
  /// gating needed for a public PDF rendered by Google.
  ///
  /// A Drive share link is not a direct file URL, so the docs viewer would
  /// render the sharing page instead of the PDF. Drive serves those from its
  /// own `/preview` endpoint, which embeds as-is and is read-only.
  Future<void> _openPdfViewer(
    String title,
    String pdfUrl,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) {
        final viewerUrl =
            _drivePreviewUrl(pdfUrl) ??
            'https://docs.google.com/viewer?url=${Uri.encodeComponent(pdfUrl)}&embedded=true';
        var loading = true;
        void Function()? onPageFinished;
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(surfaceFor(_brightness))
          ..setNavigationDelegate(
            NavigationDelegate(onPageFinished: (_) => onPageFinished?.call()),
          )
          ..loadRequest(Uri.parse(viewerUrl));
        return StatefulBuilder(
          builder: (context, setPageState) {
            onPageFinished = () => setPageState(() => loading = false);
            return Scaffold(
              appBar: AppBar(title: Text(title)),
              body: Stack(
                children: [
                  WebViewWidget(controller: controller),
                  if (loading)
                    const Center(
                      key: Key('pdf-loading'),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            );
          },
        );
      },
    ),
  );

  Widget _reminderSoundOverrideTile(
    int offsetMinutes,
    AppSettings settings,
    VoidCallback refresh,
  ) {
    final hasOverride = settings.reminderSoundOverrides.containsKey(
      offsetMinutes,
    );
    return SettingsRow(
      key: Key('notification-sound-$offsetMinutes'),
      icon: hasOverride ? Icons.music_note_rounded : Icons.music_note_outlined,
      // A row with its own sound reads as active; an inheriting one stays
      // muted so the exceptions stand out in the list.
      iconColor: hasOverride
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      title: _reminderOffsetLabel(offsetMinutes),
      value: hasOverride
          ? settings.reminderSoundOverrideNames[offsetMinutes] ??
                strings.customSound
          : strings.inheritsMainSound,
      trailing: hasOverride
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('notification-sound-inherit-$offsetMinutes'),
                  tooltip: strings.useMainSound,
                  onPressed: () async {
                    await widget.controller.clearReminderSoundOverride(
                      offsetMinutes,
                    );
                    refresh();
                  },
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                ),
                IconButton(
                  key: Key('notification-sound-edit-$offsetMinutes'),
                  tooltip: strings.chooseSound,
                  onPressed: () async {
                    await widget.controller.selectReminderSoundOverride(
                      offsetMinutes,
                    );
                    refresh();
                  },
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            )
          : TextButton(
              key: Key('notification-sound-customize-$offsetMinutes'),
              onPressed: () async {
                await widget.controller.selectReminderSoundOverride(
                  offsetMinutes,
                );
                refresh();
              },
              child: Text(strings.customizeSound),
            ),
    );
  }

  Future<void> _selectTimeZone() async {
    final timeZoneService = TimeZoneService();
    final zones = timeZoneService.availableZoneIds;
    final offsetLabels = {
      for (final zone in zones) zone: timeZoneService.offsetLabel(zone),
    };
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final needle = query.toLowerCase();
          final filtered = zones
              .where(
                (zone) =>
                    zone.toLowerCase().contains(needle) ||
                    offsetLabels[zone]!.toLowerCase().contains(needle),
              )
              .take(100)
              .toList();
          return AlertDialog(
            title: Text(strings.timezone),
            icon: const Icon(Icons.public_rounded),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            content: SizedBox(
              width: double.maxFinite,
              height: 430,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: strings.searchTimezone,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              strings.noResults,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          )
                        : RadioGroup<String>(
                            groupValue: widget.controller.settings.timeZoneId,
                            onChanged: (value) => Navigator.pop(context, value),
                            child: ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final zone = filtered[index];
                                return RadioListTile<String>(
                                  value: zone,
                                  dense: true,
                                  title: Text(zone),
                                  subtitle: Text(offsetLabels[zone]!),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected != null) {
      await widget.controller.setTimeZone(selected);
    }
  }

  String _languageLabel(String tag) => switch (tag) {
    'uz_Cyrl' => strings.uzbekCyrillic,
    'uz' => strings.uzbekLatin,
    'ru' => strings.russian,
    _ => strings.english,
  };

  Future<void> _selectLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => RadioGroup<String>(
        groupValue: widget.controller.settings.localeTag,
        onChanged: (value) => Navigator.pop(context, value),
        child: SimpleDialog(
          title: Text(strings.language),
          contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          children: [
            _languageOption('uz_Cyrl', strings.uzbekCyrillic),
            _languageOption('uz', strings.uzbekLatin),
            _languageOption('en', strings.english),
            _languageOption('ru', strings.russian),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await widget.controller.setLocale(selected);
    await _applySiteLanguage();
  }

  Widget _languageOption(String value, String label) => RadioListTile<String>(
    key: Key('language-$value'),
    value: value,
    title: Text(label),
  );

  Future<void> _handleSystemBack() async {
    if (await _webView.canGoBack()) {
      await _webView.goBack();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.homeRequests.removeListener(_goHome);
    widget.navigationRequests?.removeListener(_goToRequestedPage);
    _foregroundTimer?.cancel();
    _pullWatchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (_, _) => _handleSystemBack(),
    child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            WebViewWidget(controller: _webView),
            if (_pullDistance > 0) _pullIndicator(),
            if (_pageFailed)
              ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 52,
                        color: Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        strings.pageError,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _webView.reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(strings.retry),
                      ),
                    ],
                  ),
                ),
              ),
            if (_progress < 100)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  key: const Key('page-progress'),
                  minHeight: 2,
                  value: _progress / 100,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 60,
        padding: EdgeInsets.zero,
        child: DecoratedBox(
          // Hairline instead of elevation: the WebView scrolls right up to the
          // bar, and a shadow over arbitrary page content reads as grime.
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _navAction(
                  key: const Key('nav-back'),
                  icon: Icons.arrow_back_rounded,
                  label: strings.back,
                  enabled: _canBack,
                  onTap: _webView.goBack,
                ),
                _navAction(
                  key: const Key('nav-forward'),
                  icon: Icons.arrow_forward_rounded,
                  label: strings.forward,
                  enabled: _canForward,
                  onTap: _webView.goForward,
                ),
                _navAction(
                  key: const Key('nav-home'),
                  icon: Icons.home_rounded,
                  label: strings.home,
                  selected: isHomeUri(_currentUri),
                  onTap: _goHome,
                ),
                _navAction(
                  key: const Key('nav-refresh'),
                  icon: Icons.refresh_rounded,
                  label: strings.refresh,
                  onTap: _webView.reload,
                ),
                _navAction(
                  key: const Key('actions-menu'),
                  icon: Icons.tune_rounded,
                  label: strings.settings,
                  onTap: _openActions,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// The pull indicator: a spinner that rides down with the finger and fills
  /// as it approaches the threshold, so the release point is visible rather
  /// than guessed. `IgnorePointer` because the gesture lives in the page —
  /// this is a read-out, and must not eat the touches it is reporting on.
  Widget _pullIndicator() {
    final progress = (_pullDistance / _pullThreshold).clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      top: (_pullDistance * 0.5).clamp(0.0, _pullThreshold) + 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Material(
            key: const Key('pull-refresh-indicator'),
            elevation: 2,
            shape: const CircleBorder(),
            color: colors.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 22,
                height: 22,
                child: progress < 1
                    ? CircularProgressIndicator(
                        strokeWidth: 2.4,
                        value: progress,
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: 22,
                        color: colors.primary,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navAction({
    required Key key,
    required IconData icon,
    required String label,
    required FutureOr<void> Function() onTap,
    bool enabled = true,
    bool selected = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                key: selected ? const Key('home-selected') : null,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: selected ? colors.secondaryContainer : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: enabled
                      ? selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant
                      : colors.onSurface.withValues(alpha: 0.38),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: enabled
                      ? selected
                            ? colors.onSurface
                            : colors.onSurfaceVariant
                      : colors.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-lesson call toggle. Mirrors the home-screen widget's row icon: a filled
/// phone when the call is on, the same phone struck through when it is off.
class _LessonCallToggle extends StatelessWidget {
  const _LessonCallToggle({
    super.key,
    required this.enabled,
    required this.tooltip,
    required this.onPressed,
  });

  final bool enabled;
  final String tooltip;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(enabled ? Icons.call : Icons.phone_disabled),
      color: enabled ? colors.primary : colors.onSurfaceVariant,
      tooltip: tooltip,
      onPressed: () => onPressed(),
    );
  }
}
