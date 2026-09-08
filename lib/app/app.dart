import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import '../ui/browser_page.dart';
import 'app_controller.dart';

class KiuApp extends StatelessWidget {
  const KiuApp({
    super.key,
    required this.controller,
    required this.homeRequests,
    this.navigationRequests,
    this.homeOverride,
  });

  final AppController controller;
  final ValueNotifier<int> homeRequests;
  final ValueNotifier<Uri?>? navigationRequests;
  final Widget? homeOverride;

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B45)),
        useMaterial3: true,
      ),
      home:
          homeOverride ??
          BrowserPage(
            controller: controller,
            homeRequests: homeRequests,
            navigationRequests: navigationRequests,
          ),
    ),
  );
}
