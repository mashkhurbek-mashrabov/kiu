import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/update_downloader.dart';
import '../services/update_service.dart';
import '../ui/browser_page.dart';
import '../ui/update_gate.dart';
import 'app_controller.dart';

class KiuApp extends StatelessWidget {
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: 'KIU',
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
      home: homeOverride ?? _home(),
    ),
  );

  /// A mandatory update replaces the browser entirely rather than covering it,
  /// so the WebView is never alive behind the block.
  Widget _home() {
    final downloader = updateDownloader;
    final browser = BrowserPage(
      controller: controller,
      homeRequests: homeRequests,
      navigationRequests: navigationRequests,
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
