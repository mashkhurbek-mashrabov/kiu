import 'dart:async';

import 'package:flutter/widgets.dart';

import 'background_access_service.dart';
import 'notification_service.dart';

/// What the first-launch sequence actually managed to obtain.
///
/// Every field is the state re-queried *after* the user came back from the
/// relevant screen, not what was asked for -- the only honest answer, since
/// launching a settings screen tells us nothing about what the user did there.
class OnboardingResult {
  const OnboardingResult({
    required this.notifications,
    required this.exactAlarms,
    required this.battery,
    required this.overlay,
    required this.fullScreen,
  });

  final bool notifications;
  final bool exactAlarms;
  final bool battery;
  final bool overlay;
  final bool fullScreen;

  /// Lesson calls need all three to work as designed: the notification to post,
  /// the overlay to start the activity from the background, and the full-screen
  /// intent to own the screen while locked. Missing any one of them degrades
  /// the call to a plain heads-up banner, so calls stay off instead.
  bool get callsUsable => notifications && overlay && fullScreen;
}

/// Asks Android for everything KIU needs, once, on the first launch.
///
/// Only `POST_NOTIFICATIONS` has a real runtime dialog. Battery optimization,
/// overlay and full-screen intent can only be reached by launching a system
/// settings screen -- there is no dialog API for them -- so this walks the user
/// through those screens one at a time.
class PermissionOnboarding {
  PermissionOnboarding({
    required NotificationGateway notifications,
    required BackgroundAccessGateway backgroundAccess,
    ResumeWaiter? resumeWaiter,
  }) : _notifications = notifications,
       _backgroundAccess = backgroundAccess,
       _resumeWaiter = resumeWaiter ?? LifecycleResumeWaiter();

  final NotificationGateway _notifications;
  final BackgroundAccessGateway _backgroundAccess;
  final ResumeWaiter _resumeWaiter;

  Future<OnboardingResult> run() async {
    final notifications = await _notifications.requestNotificationPermission();

    // Exact alarms first, and through the plugin rather than a settings screen:
    // it is the one settings-backed permission with a request API, so it costs
    // the user the least, and every reminder below depends on it.
    if (!await _notifications.canScheduleExactly()) {
      await _notifications.requestExactAlarmPermission();
    }
    final exactAlarms = await _notifications.canScheduleExactly();

    final battery = await _step(
      isGranted: _backgroundAccess.isBatteryOptimizationDisabled,
      openSettings: _backgroundAccess.openBatteryOptimizationSettings,
    );
    final overlay = await _step(
      isGranted: _backgroundAccess.canDrawOverlays,
      openSettings: _backgroundAccess.openOverlaySettings,
    );
    final fullScreen = await _step(
      isGranted: _backgroundAccess.canUseFullScreenIntent,
      openSettings: _backgroundAccess.openFullScreenIntentSettings,
    );

    return OnboardingResult(
      notifications: notifications,
      exactAlarms: exactAlarms,
      battery: battery,
      overlay: overlay,
      fullScreen: fullScreen,
    );
  }

  /// Queries first and only opens the screen when the permission is missing,
  /// then waits for the app to be resumed before returning.
  ///
  /// The wait is what keeps the screens sequential. `startActivity` returns as
  /// soon as the activity is *started*, so firing these back to back without
  /// it stacks every settings screen at once and the user lands on the last
  /// one with three more hidden behind it.
  Future<bool> _step({
    required Future<bool> Function() isGranted,
    required Future<void> Function() openSettings,
  }) async {
    if (await isGranted()) return true;
    await openSettings();
    await _resumeWaiter.waitForResume();
    return isGranted();
  }
}

/// Waits for the app to come back to the foreground.
abstract interface class ResumeWaiter {
  Future<void> waitForResume();
}

/// Completes on the next `AppLifecycleState.resumed`, with a timeout.
///
/// The timeout matters: on an OEM build where a settings screen never opens at
/// all, `startActivity` silently does nothing and no resume ever arrives. Without
/// it the sequence would hang forever and the remaining permissions would never
/// be asked for.
class LifecycleResumeWaiter
    with WidgetsBindingObserver
    implements ResumeWaiter {
  static const _timeout = Duration(minutes: 2);

  Completer<void>? _pending;

  @override
  Future<void> waitForResume() {
    final completer = Completer<void>();
    _pending = completer;
    WidgetsBinding.instance.addObserver(this);
    return completer.future.timeout(_timeout, onTimeout: () {}).whenComplete(
      () {
        WidgetsBinding.instance.removeObserver(this);
        _pending = null;
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}
