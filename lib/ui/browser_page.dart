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
    setState(() {
      if (uri != null) _currentUri = uri;
      _pageFailed = false;
      _progress = 0;
    });
  }

  Future<void> _pageFinished(String url) async {
    final uri = Uri.tryParse(url);
    _canBack = await _webView.canGoBack();
    _canForward = await _webView.canGoForward();
    if (uri != null && isTrustedHttps(uri)) {
      await _applyPlaybackRate();
      await _applySiteTheme();
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
        title: Text(strings.backgroundAccess),
        content: Text(strings.backgroundAccessHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.openSettings),
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
      if (decoded is! Map<String, dynamic> ||
          decoded['type'] != 'markWatchedResult' ||
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

  Future<void> _markWatched() async {
    if (_marking || !isLessonUri(_currentUri)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.onlyLesson)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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

  Future<void> _openActions() async {
    var selected = widget.controller.settings.playbackRate;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.videoSpeed,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: <double>[1, 1.5, 1.7, 2, 2.5]
                      .map(
                        (rate) => ChoiceChip(
                          label: Text(
                            '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}×',
                          ),
                          selected: (selected - rate).abs() < 0.01,
                          onSelected: (_) async {
                            selected = rate;
                            setSheetState(() {});
                            await _setPlaybackRate(rate);
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Text('${strings.customSpeed}: ${selected.toStringAsFixed(2)}×'),
                Slider(
                  value: selected.clamp(0.5, 4.0).toDouble(),
                  min: 0.5,
                  max: 4,
                  divisions: 70,
                  onChanged: (value) => setSheetState(() => selected = value),
                  onChangeEnd: _setPlaybackRate,
                ),
                const Divider(),
                FilledButton.icon(
                  onPressed: _marking
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          _markWatched();
                        },
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_marking ? strings.marking : strings.markWatched),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(strings.notificationSettings),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openNotificationSettings();
                  },
                ),
                ListTile(
                  key: const Key('scheduled-lessons-menu'),
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(strings.scheduledLessons),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openScheduledLessons();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(strings.timezone),
                  subtitle: Text(widget.controller.settings.timeZoneId),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _selectTimeZone();
                  },
                ),
                ListTile(
                  key: const Key('theme-mode-menu'),
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: Text(strings.appearance),
                  subtitle: Text(
                    _themeModeLabel(widget.controller.settings.themeMode),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _selectThemeMode();
                  },
                ),
                ListTile(
                  key: const Key('language-menu'),
                  leading: const Icon(Icons.language),
                  title: Text(strings.language),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _selectLanguage();
                  },
                ),
                ListTile(
                  key: const Key('useful-links-menu'),
                  leading: const Icon(Icons.link),
                  title: Text(strings.usefulLinks),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openUsefulLinks();
                  },
                ),
                if (widget.controller.appVersion case final version?) ...[
                  const Divider(),
                  Text(
                    version.label(strings.version),
                    key: const Key('app-version'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openScheduledLessons() async {
    final scheduledLessons = widget.controller.scheduledLessons;
    final lessons = buildLessonWidgetPayload(
      scheduledLessons,
      widget.controller.settings,
      TimeZoneService(),
    );
    final lessonsByKey = {
      for (final lesson in scheduledLessons) lesson.callKey: lesson,
    };
    final returnToActions = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final settings = widget.controller.settings;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 24, 8),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('scheduled-lessons-back'),
                          icon: const Icon(Icons.arrow_back),
                          tooltip: strings.back,
                          onPressed: () => Navigator.pop(context, true),
                        ),
                        Expanded(
                          child: Text(
                            strings.scheduledLessons,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: lessons.isEmpty
                        ? Center(child: Text(strings.noScheduledLessons))
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
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (startsGroup)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        16,
                                        8,
                                        4,
                                      ),
                                      child: Text(
                                        lesson['group']! as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                  Card(
                                    child: ListTile(
                                      key: Key('scheduled-lesson-$index'),
                                      title: Text(lesson['title']! as String),
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
                                              enabled: settings.callEnabledFor(
                                                lessonEntity,
                                              ),
                                              tooltip:
                                                  strings.callForThisLesson,
                                              onPressed: () async {
                                                await widget.controller
                                                    .setLessonCallEnabled(
                                                      lessonEntity,
                                                      !settings.callEnabledFor(
                                                        lessonEntity,
                                                      ),
                                                    );
                                                setSheetState(() {});
                                              },
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

  Future<void> _openNotificationSettings() async {
    final customController = TextEditingController();
    var customUnitHours = false;
    var fullScreenIntentRefreshStarted = false;
    final returnToMainSettings = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (!fullScreenIntentRefreshStarted) {
            fullScreenIntentRefreshStarted = true;
            // Fire-and-forget: the sheet must render immediately rather
            // than block on a platform channel round trip, so the
            // full-screen-access tile appears a frame later once this
            // resolves.
            widget.controller.refreshFullScreenIntentAccess().then((_) {
              if (mounted) setSheetState(() {});
            });
            widget.controller.refreshOverlayAccess().then((_) {
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

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          key: const Key('notification-settings-back'),
                          tooltip: strings.back,
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            strings.notificationSettings,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: Text(strings.reminders),
                      subtitle: Text(strings.remindersHelp),
                      value: settings.remindersEnabled,
                      onChanged: (value) async {
                        await widget.controller.setRemindersEnabled(value);
                        setSheetState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: Text(strings.backgroundSync),
                      subtitle: Text(strings.backgroundSyncHelp),
                      value: settings.backgroundSyncEnabled,
                      onChanged: (value) async {
                        await widget.controller.setBackgroundSyncEnabled(value);
                        setSheetState(() {});
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.battery_saver),
                      title: Text(strings.backgroundAccess),
                      subtitle: Text(strings.backgroundAccessHelp),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: widget.controller.openBatteryOptimizationSettings,
                    ),
                    ListTile(
                      key: const Key('notification-sound-settings'),
                      leading: const Icon(Icons.music_note_outlined),
                      title: Text(strings.notificationSound),
                      subtitle: Text(
                        settings.reminderSoundUri == null
                            ? strings.defaultSound
                            : settings.reminderSoundName ??
                                  strings.soundSelected,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openSoundSettings,
                    ),
                    const Divider(),
                    SwitchListTile(
                      key: const Key('lesson-calls-switch'),
                      title: Text(strings.lessonCalls),
                      subtitle: Text(strings.lessonCallsHelp),
                      value: settings.callsEnabled,
                      onChanged: (value) async {
                        await widget.controller.setCallsEnabled(value);
                        setSheetState(() {});
                      },
                    ),
                    ListTile(
                      key: const Key('call-ring-duration'),
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(strings.ringDuration),
                      subtitle: Text(
                        strings.ringDurationValue(settings.callRingSeconds),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: settings.callsEnabled
                          ? () async {
                              await _openCallRingDurationDialog(settings);
                              setSheetState(() {});
                            }
                          : null,
                    ),
                    ListTile(
                      key: const Key('call-ringtone'),
                      leading: const Icon(Icons.ring_volume_outlined),
                      title: Text(strings.callRingtone),
                      subtitle: Text(
                        settings.callRingtoneName ?? strings.defaultSound,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: settings.callsEnabled
                          ? () async {
                              await widget.controller.selectCallRingtone();
                              setSheetState(() {});
                            }
                          : null,
                    ),
                    if (settings.callsEnabled &&
                        !widget.controller.canUseFullScreenIntent)
                      ListTile(
                        key: const Key('full-screen-access'),
                        leading: const Icon(Icons.fullscreen),
                        title: Text(strings.fullScreenAccess),
                        subtitle: Text(strings.fullScreenAccessHelp),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () async {
                          await widget.controller
                              .openFullScreenIntentSettings();
                          setSheetState(() {});
                        },
                      ),
                    // Android grants this one only from its own settings screen, so the
                    // switch reflects the current state and both directions deep-link
                    // there rather than toggling anything locally.
                    if (settings.callsEnabled)
                      SwitchListTile(
                        key: const Key('overlay-access-tile'),
                        secondary: const Icon(Icons.picture_in_picture_alt),
                        title: Text(strings.overlayAccess),
                        subtitle: Text(strings.overlayAccessHelp),
                        value: widget.controller.canDrawOverlays,
                        onChanged: (_) async {
                          await widget.controller.openOverlaySettings();
                          setSheetState(() {});
                        },
                      ),
                    for (final option in <(int, String)>[
                      (180, strings.threeHours),
                      (60, strings.oneHour),
                      (15, strings.fifteenMinutes),
                      (0, strings.atStart),
                    ]) ...[
                      CheckboxListTile(
                        title: Text(option.$2),
                        value: offsets.contains(option.$1),
                        onChanged: settings.remindersEnabled
                            ? (value) => toggleOffset(option.$1, value ?? false)
                            : null,
                      ),
                    ],
                    for (final value
                        in offsets
                            .where((value) => !{180, 60, 15, 0}.contains(value))
                            .toList()
                          ..sort((a, b) => b.compareTo(a))) ...[
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 16),
                        title: Text(_reminderOffsetLabel(value)),
                        trailing: IconButton(
                          tooltip: strings.remove,
                          onPressed: () => toggleOffset(value, false),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ],
                    Text(
                      strings.customReminder,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              hintText: '1–168',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<bool>(
                          value: customUnitHours,
                          items: [
                            DropdownMenuItem(
                              value: false,
                              child: Text(strings.minutes),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text(strings.hours),
                            ),
                          ],
                          onChanged: (value) => setSheetState(
                            () => customUnitHours = value ?? false,
                          ),
                        ),
                        IconButton(
                          tooltip: strings.add,
                          onPressed: settings.remindersEnabled
                              ? () async {
                                  final amount = int.tryParse(
                                    customController.text,
                                  );
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
                          icon: const Icon(Icons.add_circle),
                        ),
                      ],
                    ),
                    if (!widget.controller.exactTiming)
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: Text(strings.reducedPrecision),
                        trailing: TextButton(
                          onPressed: () async {
                            await widget.controller.requestExactTiming();
                            setSheetState(() {});
                          },
                          child: Text(strings.grantPermission),
                        ),
                      )
                    else
                      ListTile(
                        leading: const Icon(Icons.alarm_on),
                        title: Text(strings.exactTiming),
                      ),
                    ListTile(
                      leading: const Icon(Icons.sync),
                      title: Text(strings.syncNow),
                      subtitle: Text(_syncStatusText()),
                      onTap: () async {
                        await _synchronize();
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
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

  String _syncStatusText() {
    final status = widget.controller.syncStatus;
    if (status == ScheduleSyncStatus.syncing) return strings.syncing;
    if (status == ScheduleSyncStatus.signInRequired) {
      return strings.signInToSync;
    }
    if (status == ScheduleSyncStatus.failed) return strings.syncFailed;
    final date = widget.controller.lastSuccessfulSync;
    return strings.lastSync(
      date == null
          ? strings.never
          : DateFormat('yyyy-MM-dd HH:mm').format(date),
    );
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
        title: Text(strings.ringDuration),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: '10–300'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: strings.add,
                  onPressed: () {
                    final amount = int.tryParse(customController.text);
                    if (amount == null) return;
                    Navigator.pop(context, amount);
                  },
                  icon: const Icon(Icons.check_circle),
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

  Future<void> _openSoundSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => StatefulBuilder(
        builder: (context, setPageState) {
          final settings = widget.controller.settings;
          final offsets = settings.reminderOffsetsMinutes.toSet().toList()
            ..sort((a, b) => b.compareTo(a));
          return Scaffold(
            appBar: AppBar(title: Text(strings.soundSettings)),
            body: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                ListTile(
                  key: const Key('main-notification-sound'),
                  leading: const Icon(Icons.volume_up_outlined),
                  title: Text(strings.mainSound),
                  subtitle: Text(
                    settings.reminderSoundUri == null
                        ? strings.defaultSound
                        : settings.reminderSoundName ?? strings.soundSelected,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await widget.controller.selectMainReminderSound();
                      setPageState(() {});
                    },
                    child: Text(strings.chooseSound),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    strings.individualSounds,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    strings.soundOverridesHelp,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final offset in offsets)
                  _reminderSoundOverrideTile(
                    offset,
                    settings,
                    () => setPageState(() {}),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Future<void> _openUsefulLinks() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(strings.usefulLinks)),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                strings.testPlatforms,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final link in const [
              ('ibodati-islomiya.com', 'https://ibodati-islomiya.com'),
              ('nurul-izoh.com', 'https://nurul-izoh.com'),
              ('etiqod-durdonalari.xyz', 'https://etiqod-durdonalari.xyz'),
            ])
              Card(
                child: ListTile(
                  title: Text(link.$1),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchExternal(link.$2),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                strings.pdfBooks,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final link in const [
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
            ])
              Card(
                child: ListTile(
                  title: Text(link.$1),
                  trailing: const Icon(Icons.picture_as_pdf_outlined),
                  onTap: () => _launchExternal(link.$2),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                strings.apps,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
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
              Card(
                child: ListTile(
                  title: Text(link.$1),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchExternal(link.$2),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _launchExternal(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Widget _reminderSoundOverrideTile(
    int offsetMinutes,
    AppSettings settings,
    VoidCallback refresh,
  ) {
    final hasOverride = settings.reminderSoundOverrides.containsKey(
      offsetMinutes,
    );
    return ListTile(
      key: Key('notification-sound-$offsetMinutes'),
      leading: Icon(hasOverride ? Icons.music_note : Icons.music_note_outlined),
      title: Text(_reminderOffsetLabel(offsetMinutes)),
      subtitle: Text(
        hasOverride
            ? settings.reminderSoundOverrideNames[offsetMinutes] ??
                  strings.customSound
            : strings.inheritsMainSound,
      ),
      trailing: hasOverride
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: Key('notification-sound-inherit-$offsetMinutes'),
                  onPressed: () async {
                    await widget.controller.clearReminderSoundOverride(
                      offsetMinutes,
                    );
                    refresh();
                  },
                  child: Text(strings.useMainSound),
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
                  icon: const Icon(Icons.edit_outlined),
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
            content: SizedBox(
              width: double.maxFinite,
              height: 430,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: strings.searchTimezone,
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: widget.controller.settings.timeZoneId,
                      onChanged: (value) => Navigator.pop(context, value),
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final zone = filtered[index];
                          return RadioListTile<String>(
                            value: zone,
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

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => strings.themeSystem,
    ThemeMode.light => strings.themeLight,
    ThemeMode.dark => strings.themeDark,
  };

  Future<void> _selectThemeMode() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => RadioGroup<ThemeMode>(
        groupValue: widget.controller.settings.themeMode,
        onChanged: (value) => Navigator.pop(context, value),
        child: SimpleDialog(
          title: Text(strings.appearance),
          children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                key: Key('theme-mode-${mode.name}'),
                value: mode,
                title: Text(_themeModeLabel(mode)),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await widget.controller.setThemeMode(selected);
    await _applySiteTheme();
  }

  Future<void> _selectLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => RadioGroup<String>(
        groupValue: widget.controller.settings.localeTag,
        onChanged: (value) => Navigator.pop(context, value),
        child: SimpleDialog(
          title: Text(strings.language),
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
            if (_pageFailed)
              ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48),
                      const SizedBox(height: 12),
                      Text(strings.pageError),
                      TextButton.icon(
                        onPressed: _webView.reload,
                        icon: const Icon(Icons.refresh),
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
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _navAction(
                key: const Key('nav-back'),
                icon: Icons.arrow_back,
                label: strings.back,
                enabled: _canBack,
                onTap: _webView.goBack,
              ),
              _navAction(
                key: const Key('nav-forward'),
                icon: Icons.arrow_forward,
                label: strings.forward,
                enabled: _canForward,
                onTap: _webView.goForward,
              ),
              _navAction(
                key: const Key('nav-home'),
                icon: Icons.home,
                label: strings.home,
                selected: isHomeUri(_currentUri),
                onTap: _goHome,
              ),
              _navAction(
                key: const Key('nav-refresh'),
                icon: Icons.refresh,
                label: strings.refresh,
                onTap: _webView.reload,
              ),
              _navAction(
                key: const Key('actions-menu'),
                icon: Icons.more_vert,
                label: strings.actions,
                onTap: _openActions,
              ),
            ],
          ),
        ),
      ),
    ),
  );

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
              DecoratedBox(
                key: selected ? const Key('home-selected') : null,
                decoration: BoxDecoration(
                  color: selected ? colors.secondaryContainer : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
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
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: enabled
                      ? colors.onSurfaceVariant
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
