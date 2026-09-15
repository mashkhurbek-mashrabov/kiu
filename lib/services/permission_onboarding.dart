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

/// The permissions the first-launch flow explains before requesting.
enum PermissionKind { notifications, exactTiming, battery, overlay, fullScreen }

/// Shows KIU's own "why we need this" dialog and reports whether the user
/// agreed to continue to the Android screen.
typedef PermissionExplainer = Future<bool> Function(PermissionKind permission);

/// Asks Android for everything KIU needs, once, on the first launch.
///
/// Each permission past notifications is introduced by KIU's own dialog first.
/// Android's screens say *what* is being granted but never *why* this app wants
/// it, and a settings screen that appears unannounced reads as the app having
/// done something wrong. Declining an explainer skips that permission and moves
/// on -- the settings sheet stays the way back.
class PermissionOnboarding {
  PermissionOnboarding({
    required NotificationGateway notifications,
    required BackgroundAccessGateway backgroundAccess,
    ResumeWaiter? resumeWaiter,
    Duration? settleDelay,
  }) : _notifications = notifications,
       _backgroundAccess = backgroundAccess,
       _resumeWaiter = resumeWaiter ?? LifecycleResumeWaiter(),
       settleDelay = settleDelay ?? const Duration(seconds: 15);

  final NotificationGateway _notifications;
  final BackgroundAccessGateway _backgroundAccess;
  final ResumeWaiter _resumeWaiter;

  /// How long to leave the user alone after the notification prompt before
  /// asking for anything else. Back-to-back permission requests on a first
  /// launch read as an interrogation; this puts the rest after a pause, once
  /// the user has had a moment with the app itself.
  final Duration settleDelay;

  Future<OnboardingResult> run({required PermissionExplainer explain}) async {
    // Notifications first: everything else here exists to deliver one, so there
    // is nothing to ask for if the user does not want them at all.
    final notifications = await _step(
      permission: PermissionKind.notifications,
      explain: explain,
    );

    await Future<void>.delayed(settleDelay);

    final exactAlarms = await _step(
      permission: PermissionKind.exactTiming,
      explain: explain,
    );
    // Battery is the one background permission with a real dialog, so it uses
    // that rather than the settings list: one tap in place, no app list to
    // scroll. The gateway falls back to the list when the dialog cannot be
    // launched, so this still resolves to a screen the user can act on.
    final battery = await _step(
      permission: PermissionKind.battery,
      explain: explain,
    );
    final overlay = await _step(
      permission: PermissionKind.overlay,
      explain: explain,
    );
    final fullScreen = await _step(
      permission: PermissionKind.fullScreen,
      explain: explain,
    );

    return OnboardingResult(
      notifications: notifications,
      exactAlarms: exactAlarms,
      battery: battery,
      overlay: overlay,
      fullScreen: fullScreen,
    );
  }

  /// Takes one permission straight to Android, for a settings row.
  ///
  /// No explainer. The first-launch sequence explains because its screens
  /// arrive unannounced, one after another, before the user has asked for
  /// anything. A settings row is the opposite: the user tapped a row whose
  /// label and ⓘ already say what it is for, so a dialog in between is one
  /// more tap between the intent and the screen.
  ///
  /// Returns the state after the user acted, re-queried rather than assumed.
  Future<bool> request({required PermissionKind permission}) async {
    final isGranted = _isGranted(permission);
    // The request path when something is actually missing -- battery's gives
    // Android's one-tap dialog rather than the app list -- and the plain
    // settings screen when it is already held, since a request is a no-op
    // then: requestBatteryExemption returns early without launching anything
    // once the app is exempt, which would leave the row dead on tap.
    final open = await isGranted() ? _reveal(permission) : _request(permission);
    await open();
    // Notifications resolve in place; everything else is a trip out to a
    // settings screen that has to be waited on before re-querying.
    if (permission != PermissionKind.notifications) {
      await _resumeWaiter.waitForResume();
    }
    return isGranted();
  }

  Future<bool> Function() _isGranted(PermissionKind permission) =>
      switch (permission) {
        // Android owns the grant state and gives no "already asked" signal, so
        // the request itself is the query.
        PermissionKind.notifications => () async => false,
        PermissionKind.exactTiming => _notifications.canScheduleExactly,
        PermissionKind.battery =>
          _backgroundAccess.isBatteryOptimizationDisabled,
        PermissionKind.overlay => _backgroundAccess.canDrawOverlays,
        PermissionKind.fullScreen => _backgroundAccess.canUseFullScreenIntent,
      };

  Future<Object?> Function() _request(
    PermissionKind permission,
  ) => switch (permission) {
    PermissionKind.notifications =>
      _notifications.requestNotificationPermission,
    PermissionKind.exactTiming => _notifications.requestExactAlarmPermission,
    // The dialog, not the settings list — the gateway falls back to the
    // list by itself when the dialog cannot launch.
    PermissionKind.battery => _backgroundAccess.requestBatteryExemption,
    PermissionKind.overlay => _backgroundAccess.openOverlaySettings,
    PermissionKind.fullScreen => _backgroundAccess.openFullScreenIntentSettings,
  };

  /// Explains, then requests, then re-queries what the user actually did.
  ///
  /// Nothing happens for an already-granted permission: no dialog, no screen.
  /// A declined explainer returns the current state without ever reaching
  /// Android, so "Not now" really means nothing opens.
  ///
  /// The resume wait is what keeps the screens sequential. `startActivity`
  /// returns as soon as the activity is *started*, so firing these back to back
  /// without it stacks every settings screen at once and the user lands on the
  /// last one with the rest hidden behind it.
  ///
  /// [request] returns `Object?` so the void settings-screen openers and the
  /// two that report a bool both fit. The value is not consulted: what the user
  /// did is re-queried either way.
  /// The Android screen that *shows* a permission, for a row tapped while it
  /// is already granted.
  ///
  /// Distinct from the request paths above because a request is a no-op once
  /// the permission is held: battery's in particular returns without launching
  /// anything, so the settings list is the only thing left that can display —
  /// or let the user revoke — the exemption.
  Future<Object?> Function() _reveal(
    PermissionKind permission,
  ) => switch (permission) {
    PermissionKind.battery => _backgroundAccess.openBatteryOptimizationSettings,
    PermissionKind.exactTiming => _notifications.requestExactAlarmPermission,
    PermissionKind.overlay => _backgroundAccess.openOverlaySettings,
    PermissionKind.fullScreen => _backgroundAccess.openFullScreenIntentSettings,
    // Notifications never reach here: their isGranted is a stub that
    // always reports false, so the request path owns them.
    PermissionKind.notifications =>
      _notifications.requestNotificationPermission,
  };

  Future<bool> _step({
    required PermissionKind permission,
    required PermissionExplainer explain,
  }) async {
    final isGranted = _isGranted(permission);
    if (await isGranted()) return true;
    if (!await explain(permission)) return false;
    final requested = await _request(permission)();
    // The notification dialog resolves in place rather than sending the user
    // to Settings, so there is no trip away from the app to wait on and its
    // own answer is the outcome.
    if (permission == PermissionKind.notifications) {
      return requested is bool ? requested : isGranted();
    }
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
