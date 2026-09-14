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
      final result = await controller.runPermissionOnboarding();

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

    final result = await controller.runPermissionOnboarding();

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

    final result = await controller.runPermissionOnboarding();

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

      await controller.runPermissionOnboarding();

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

    await controller.runPermissionOnboarding();

    // One wait per opened screen: without them the activities stack and the
    // user lands on the last one with the rest hidden behind it.
    expect(access.batterySettingsOpened, 1);
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
    await controller.runPermissionOnboarding();
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

    await expectLater(controller.runPermissionOnboarding(), throwsStateError);

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

    await controller.runPermissionOnboarding();

    expect(
      controller.shouldShowBackgroundExplainer,
      isFalse,
      reason: 'the flow already asked for the battery permission',
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

    await controller.runPermissionOnboarding();

    expect(controller.settings.callsEnabled, isTrue);
  });
}

class ThrowingNotificationGateway extends FakeNotificationGateway {
  @override
  Future<bool> requestNotificationPermission() async =>
      throw StateError('channel unavailable');
}
