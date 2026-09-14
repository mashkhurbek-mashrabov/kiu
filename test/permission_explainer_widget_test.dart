import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/core/constants.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/permission_onboarding.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:kiu/ui/widgets/settings_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'support/fake_webview_platform.dart';
import 'support/fakes.dart';

Future<AppController> buildController(
  FakeBackgroundAccessGateway access,
) async {
  final repository = SettingsRepository(await SharedPreferences.getInstance());
  final notifications = FakeNotificationGateway();
  final reconciler = ReminderReconciler(
    repository: repository,
    notifications: notifications,
  );
  return AppController(
    repository: repository,
    syncService: ScheduleSyncService(
      fetcher: ScheduleFetcher(cookieProvider: EmptyCookieProvider()),
      repository: repository,
      reconciler: reconciler,
    ),
    reconciler: reconciler,
    notifications: notifications,
    scheduler: FakeBackgroundScheduler(),
    backgroundAccess: access,
    onboarding: PermissionOnboarding(
      notifications: notifications,
      backgroundAccess: access,
      resumeWaiter: ImmediateResumeWaiter(),
      settleDelay: Duration.zero,
    ),
  );
}

class ImmediateResumeWaiter implements ResumeWaiter {
  @override
  Future<void> waitForResume() async {}
}

void main() {
  setUp(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
    SharedPreferences.setMockInitialValues({'kiu.locale': 'en'});
  });

  testWidgets('the explainer states why, with the detail behind a tooltip', (
    tester,
  ) async {
    final access = FakeBackgroundAccessGateway()..overlaysAllowed = false;
    final controller = await buildController(access);
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );

    // Drive the real trigger: finishing the Home page is what starts the flow,
    // so this exercises the actual dialog rather than a stand-in callback.
    finishPage?.call(homeUrl);
    await tester.pumpAndSettle();

    // Notifications come first, and they get an explainer of their own -- the
    // Android dialog must never be the first thing the user sees.
    expect(
      find.text('So KIU can tell you before a lesson starts.'),
      findsOneWidget,
      reason: 'the notification permission is explained before Android asks',
    );
    await tester.tap(find.byKey(const Key('permission-explainer-allow')));
    await tester.pumpAndSettle();

    // The short reason is on the dialog itself...
    expect(
      find.text('So a lesson call can open while you are using your phone.'),
      findsOneWidget,
    );
    const detail =
        'Lets the call screen open while you are using the phone. '
        'Without it the call shows only as a notification banner.';
    // ...while the long explanation stays inside the tooltip until asked for.
    expect(find.text(detail), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('permission-explainer')),
        matching: find.byType(InfoHint),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(detail), findsOneWidget);
  });

  testWidgets('"Not now" opens no Android screen', (tester) async {
    final access = FakeBackgroundAccessGateway()..overlaysAllowed = false;
    final controller = await buildController(access);
    await tester.pumpWidget(
      KiuApp(controller: controller, homeRequests: ValueNotifier<int>(0)),
    );

    finishPage?.call(homeUrl);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('permission-explainer')),
      findsOneWidget,
      reason: 'the explainer must appear before any Android screen',
    );
    // Past notifications, then decline the overlay explainer.
    await tester.tap(find.byKey(const Key('permission-explainer-allow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('permission-explainer-decline')));
    await tester.pumpAndSettle();

    // "Not now" has to mean nothing opens.
    expect(access.overlaySettingsOpened, 0);
  });
}
