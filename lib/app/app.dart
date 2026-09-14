import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/update_downloader.dart';
import '../services/update_service.dart';
import '../ui/browser_page.dart';
import '../ui/update_gate.dart';
import 'app_controller.dart';

class KiuApp extends StatefulWidget {
  const KiuApp({
    super.key,
    required this.controller,
    required this.homeRequests,
    this.navigationRequests,
    this.homeOverride,
    this.updateDownloader,
  });

  final AppController controller;
  final ValueNotifier<int> homeRequests;
  final ValueNotifier<Uri?>? navigationRequests;
  final Widget? homeOverride;
  final UpdateDownloader? updateDownloader;

  @override
  State<KiuApp> createState() => _KiuAppState();
}

class _KiuAppState extends State<KiuApp> {
  /// Needed to reach the Navigator from outside the tree the gate replaces.
  /// The gate swaps the widget behind `home:`, which does not pop routes — an
  /// open settings sheet is a pushed route and stayed on top of the block.
  final _navigatorKey = GlobalKey<NavigatorState>();

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.availableUpdate.addListener(_dismissRoutesForGate);
  }

  @override
  void dispose() {
    controller.availableUpdate.removeListener(_dismissRoutesForGate);
    super.dispose();
  }

  /// Clears anything pushed above the browser so the gate really owns the
  /// screen.
  ///
  /// Popped immediately rather than post-frame: `_home()` swaps the browser
  /// for the gate as soon as this notifier changes, and a sheet still mounted
  /// at that moment is torn down mid-build, which throws on its deactivated
  /// StatefulBuilder.
  void _dismissRoutesForGate() {
    final update = controller.availableUpdate.value;
    if (update == null || !update.mandatory) return;
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: 'KIU',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: controller.settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: kiuTheme(Brightness.light),
      darkTheme: kiuTheme(Brightness.dark),
      themeMode: controller.settings.themeMode,
      home: widget.homeOverride ?? _home(),
    ),
  );

  /// A mandatory update replaces the browser entirely rather than covering it,
  /// so the WebView is never alive behind the block.
  Widget _home() {
    final downloader = widget.updateDownloader;
    final browser = BrowserPage(
      controller: controller,
      homeRequests: widget.homeRequests,
      navigationRequests: widget.navigationRequests,
      updateDownloader: downloader,
    );
    if (downloader == null) return browser;
    return ValueListenableBuilder<AppUpdate?>(
      valueListenable: controller.availableUpdate,
      builder: (context, update, child) => update != null && update.mandatory
          ? UpdateGate(update: update, downloader: downloader)
          : child!,
      child: browser,
    );
  }
}
