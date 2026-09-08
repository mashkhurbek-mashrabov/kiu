import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/l10n/app_localizations.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('switches all four supported interface languages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    final notifications = FakeNotificationGateway();
    final reconciler = ReminderReconciler(
      repository: repository,
      notifications: notifications,
    );
    final controller = AppController(
      repository: repository,
      syncService: ScheduleSyncService(
        fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
        repository: repository,
        reconciler: reconciler,
      ),
      reconciler: reconciler,
      notifications: notifications,
      scheduler: FakeBackgroundScheduler(),
    );
    final requests = ValueNotifier<int>(0);
    await tester.pumpWidget(
      KiuApp(
        controller: controller,
        homeRequests: requests,
        homeOverride: Builder(
          builder: (context) => Text(AppLocalizations.of(context).home),
        ),
      ),
    );

    expect(find.text('Бош саҳифа'), findsOneWidget);
    for (final entry in const {
      'uz': 'Bosh sahifa',
      'en': 'Home',
      'ru': 'Главная',
      'uz_Cyrl': 'Бош саҳифа',
    }.entries) {
      await controller.setLocale(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}
