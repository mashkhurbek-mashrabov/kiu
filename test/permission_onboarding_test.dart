import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/app/app_controller.dart';
import 'package:kiu/data/settings_repository.dart';
import 'package:kiu/services/permission_onboarding.dart';
import 'package:kiu/services/reminder_reconciler.dart';
import 'package:kiu/services/schedule_fetcher.dart';
import 'package:kiu/services/schedule_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Returns immediately rather than waiting on a real lifecycle event: no
/// settings activity ever starts in a unit test, so a real waiter would only
/// ever hit its timeout.
class ImmediateResumeWaiter implements ResumeWaiter {
  int waits = 0;

  @override
  Future<void> waitForResume() async => waits++;
}

/// Stands in for a user who taps Allow on every explainer.
Future<bool> agreeAll(PermissionKind permission) async => true;

/// Stands in for a user who taps "Not now" on every explainer.
Future<bool> declineAll(PermissionKind permission) async => false;

/// Records which explainers were shown, in order.
class RecordingExplainer {
  final List<PermissionKind> shown = [];

  Future<bool> call(PermissionKind permission) async {
    shown.add(permission);
    return true;
  }
}

Future<AppController> createController({
  required FakeNotificationGateway notifications,
  required FakeBackgroundAccessGateway backgroundAccess,
  required ResumeWaiter resumeWaiter,
  FakeLessonWidgetGateway? lessonWidgets,
}) async {
  final repository = SettingsRepository(await SharedPreferences.getInstance());
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
    backgroundAccess: backgroundAccess,
    lessonWidgets: lessonWidgets,
    onboarding: PermissionOnboarding(
      notifications: notifications,
      backgroundAccess: backgroundAccess,
      resumeWaiter: resumeWaiter,
      // No real pause in tests; the delay is asserted separately.
      settleDelay: Duration.zero,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'enables lesson calls when every required permission is granted',
    () async {
      final notifications = FakeNotificationGateway()..permission = true;
      final access = FakeBackgroundAccessGateway()
        ..overlaysAllowed = true
        ..fullScreenIntentAllowed = true;
      final controller = await createController(
        notifications: notifications,
        backgroundAccess: access,
        resumeWaiter: ImmediateResumeWaiter(),
      );

      expect(controller.needsPermissionOnboarding, isTrue);
      final result = await controller.runPermissionOnboarding(
        explain: agreeAll,
      );

      expect(result.callsUsable, isTrue);
      expect(controller.settings.callsEnabled, isTrue);
      final reloaded = SettingsRepository(await SharedPreferences.getInstance())
          .loadSettings();
      expect(reloaded.callsEnabled, isTrue, reason: 'must survive a reload');
    },
  );

  test('leaves calls off when the overlay permission is refused', () async {
    final notifications = FakeNotificationGateway()..permission = true;
    final access = FakeBackgroundAccessGateway()..overlaysAllowed = false;
    final controller = await createController(
      notifications: notifications,
      backgroundAccess: access,
      resumeWaiter: ImmediateResumeWaiter(),
    );

    final result = await controller.runPermissionOnboarding(explain: agreeAll);

    expect(result.overlay, isFalse);
    expect(result.callsUsable, isFalse);
    expect(controller.settings.callsEnabled, isFalse);
    expect(access.overlaySettingsOpened, 1, reason: 'should have asked once');
  });

  test('leaves calls off when notifications are refused', () async {
    final notifications = FakeNotificationGateway()..permission = false;
    final controller = await createController(
      notifications: notifications,
      backgroundAccess: FakeBackgroundAccessGateway(),
      resumeWaiter: ImmediateResumeWaiter(),
    );

    final result = await controller.runPermissionOnboarding(explain: agreeAll);

    expect(result.notifications, isFalse);
    expect(result.callsUsable, isFalse);
    expect(controller.settings.callsEnabled, isFalse);
  });

  test(
    'never opens a settings screen for an already-granted permission',
    () async {
      final access = FakeBackgroundAccessGateway()
        ..batteryOptimizationDisabled = true
        ..overlaysAllowed = true
        ..fullScreenIntentAllowed = true;
      final waiter = ImmediateResumeWaiter();
      final controller = await createController(
        notifications: FakeNotificationGateway(),
        backgroundAccess: access,
        resumeWaiter: waiter,
      );

      await controller.runPermissionOnboarding(explain: agreeAll);

      expect(access.batteryDialogShown, 0);
      expect(access.batterySettingsOpened, 0);
      expect(access.overlaySettingsOpened, 0);
      expect(access.fullScreenSettingsOpened, 0);
      expect(waiter.waits, 0, reason: 'nothing to wait for when all granted');
    },
  );

  test('waits for a resume between each settings screen it opens', () async {
    final access = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false
      ..overlaysAllowed = false
      ..fullScreenIntentAllowed = false;
    final waiter = ImmediateResumeWaiter();
    final controller = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: access,
      resumeWaiter: waiter,
    );

    await controller.runPermissionOnboarding(explain: agreeAll);

    // One wait per opened screen: without them the activities stack and the
    // user lands on the last one with the rest hidden behind it.
    // Battery uses its one-tap dialog, not the app list the other two fall to.
    expect(access.batteryDialogShown, 1);
    expect(access.batterySettingsOpened, 0);
    expect(access.overlaySettingsOpened, 1);
    expect(access.fullScreenSettingsOpened, 1);
    expect(waiter.waits, 3);
  });

  test('runs only once per install', () async {
    final controller = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: FakeBackgroundAccessGateway(),
      resumeWaiter: ImmediateResumeWaiter(),
    );

    expect(controller.needsPermissionOnboarding, isTrue);
    await controller.runPermissionOnboarding(explain: agreeAll);
    expect(controller.needsPermissionOnboarding, isFalse);

    // A fresh controller over the same storage is the next launch.
    final next = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: FakeBackgroundAccessGateway(),
      resumeWaiter: ImmediateResumeWaiter(),
    );
    expect(next.needsPermissionOnboarding, isFalse);
  });

  test('marks itself shown even when the sequence throws partway', () async {
    final controller = await createController(
      notifications: ThrowingNotificationGateway(),
      backgroundAccess: FakeBackgroundAccessGateway(),
      resumeWaiter: ImmediateResumeWaiter(),
    );

    await expectLater(
      controller.runPermissionOnboarding(explain: agreeAll),
      throwsStateError,
    );

    // The marker is what stops a crash mid-flow from replaying the whole
    // sequence on every single launch.
    expect(controller.needsPermissionOnboarding, isFalse);
  });

  test('suppresses the background explainer it would duplicate', () async {
    final controller = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: FakeBackgroundAccessGateway(),
      resumeWaiter: ImmediateResumeWaiter(),
    );

    await controller.runPermissionOnboarding(explain: agreeAll);

    expect(
      controller.shouldShowBackgroundExplainer,
      isFalse,
      reason: 'the flow already asked for the battery permission',
    );
  });

  test('declining an explainer opens nothing for that permission', () async {
    final access = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false
      ..overlaysAllowed = false
      ..fullScreenIntentAllowed = false;
    final waiter = ImmediateResumeWaiter();
    final controller = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: access,
      resumeWaiter: waiter,
    );

    final result = await controller.runPermissionOnboarding(
      explain: declineAll,
    );

    // "Not now" has to mean nothing opens -- not "the screen appears anyway".
    expect(access.batteryDialogShown, 0);
    expect(access.batterySettingsOpened, 0);
    expect(access.overlaySettingsOpened, 0);
    expect(access.fullScreenSettingsOpened, 0);
    expect(waiter.waits, 0);
    expect(result.callsUsable, isFalse);
  });

  test('a decline skips only that permission, not the rest', () async {
    final access = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false
      ..overlaysAllowed = false
      ..fullScreenIntentAllowed = false;
    final controller = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: access,
      resumeWaiter: ImmediateResumeWaiter(),
    );

    await controller.runPermissionOnboarding(
      explain: (permission) async => permission != PermissionKind.battery,
    );

    expect(access.batteryDialogShown, 0, reason: 'declined');
    expect(access.overlaySettingsOpened, 1, reason: 'still offered');
    expect(access.fullScreenSettingsOpened, 1, reason: 'still offered');
  });

  test('explains every missing permission, in order', () async {
    final explainer = RecordingExplainer();
    final controller = await createController(
      notifications: FakeNotificationGateway()..exact = false,
      backgroundAccess: FakeBackgroundAccessGateway()
        ..batteryOptimizationDisabled = false
        ..overlaysAllowed = false
        ..fullScreenIntentAllowed = false,
      resumeWaiter: ImmediateResumeWaiter(),
    );

    await controller.runPermissionOnboarding(explain: explainer.call);

    expect(explainer.shown, [
      PermissionKind.notifications,
      PermissionKind.exactTiming,
      PermissionKind.battery,
      PermissionKind.overlay,
      PermissionKind.fullScreen,
    ]);
  });

  test('never explains an already-granted permission', () async {
    final explainer = RecordingExplainer();
    final controller = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: FakeBackgroundAccessGateway(),
      resumeWaiter: ImmediateResumeWaiter(),
    );

    await controller.runPermissionOnboarding(explain: explainer.call);

    // Notifications are always explained: Android reports no "already asked"
    // state, so the flow cannot know it is redundant.
    expect(explainer.shown, [PermissionKind.notifications]);
  });

  test('the settings row still opens the list, not the dialog', () async {
    final access = FakeBackgroundAccessGateway()
      ..batteryOptimizationDisabled = false;
    final controller = await createController(
      notifications: FakeNotificationGateway(),
      backgroundAccess: access,
      resumeWaiter: ImmediateResumeWaiter(),
    );

    await controller.openBatteryOptimizationSettings();

    // Android shows the dialog at most once per app; after a denial it becomes
    // a no-op. The settings row has to keep working after that, so it stays on
    // the list, which always renders.
    expect(access.batterySettingsOpened, 1);
    expect(access.batteryDialogShown, 0);
  });

  test('asks nothing else until the settle delay has passed', () async {
    final explainer = RecordingExplainer();
    final onboarding = PermissionOnboarding(
      notifications: FakeNotificationGateway()..exact = false,
      backgroundAccess: FakeBackgroundAccessGateway()
        ..batteryOptimizationDisabled = false
        ..overlaysAllowed = false
        ..fullScreenIntentAllowed = false,
      resumeWaiter: ImmediateResumeWaiter(),
      settleDelay: const Duration(milliseconds: 120),
    );

    final running = onboarding.run(explain: explainer.call);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(explainer.shown, [
      PermissionKind.notifications,
    ], reason: 'only notifications may be asked before the settle delay');

    await running;
    expect(
      explainer.shown.length,
      greaterThan(1),
      reason: 'the rest resume once the delay elapses',
    );
  });

  test('defaults the settle delay to 15 seconds', () {
    // The delay is the whole point of the pause; a default that silently
    // shrank would make the flow an interrogation again.
    expect(
      PermissionOnboarding(
        notifications: FakeNotificationGateway(),
        backgroundAccess: FakeBackgroundAccessGateway(),
        resumeWaiter: ImmediateResumeWaiter(),
      ).settleDelay,
      const Duration(seconds: 15),
    );
  });

  test('does not disable calls the user turned on by hand', () async {
    final notifications = FakeNotificationGateway()..permission = true;
    final controller = await createController(
      notifications: notifications,
      backgroundAccess: FakeBackgroundAccessGateway()..overlaysAllowed = false,
      resumeWaiter: ImmediateResumeWaiter(),
    );
    await controller.setCallsEnabled(true);

    await controller.runPermissionOnboarding(explain: agreeAll);

    expect(controller.settings.callsEnabled, isTrue);
  });
}

class ThrowingNotificationGateway extends FakeNotificationGateway {
  @override
  Future<bool> requestNotificationPermission() async =>
      throw StateError('channel unavailable');
}
