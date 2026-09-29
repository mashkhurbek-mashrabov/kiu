import 'package:flutter/foundation.dart';

/// Whether this build runs on iOS.
///
/// Read through [defaultTargetPlatform] rather than `dart:io` so widget tests,
/// which default to Android, keep exercising the Android paths unless a test
/// opts into iOS with `debugDefaultTargetPlatformOverride`.
///
/// iOS has no equivalent for several Android features -- the APK updater,
/// full-screen lesson calls, battery/overlay/exact-alarm permissions, and
/// picking a system sound by URI -- so those paths are skipped or hidden there
/// rather than stubbed behind gateways that could never succeed.
bool get runsOnIOS => defaultTargetPlatform == TargetPlatform.iOS;

/// The App Group the app and the iOS widget extension share. `home_widget`
/// writes the widget payload into its `UserDefaults` suite, and the lesson-call
/// alarms read their schedule from there too. Must match both
/// `.entitlements` files.
const iosAppGroupId = 'group.com.mashkhurbek.kiu';

/// The WidgetKit `kind` of the lesson widget in `ios/KiuLessonWidget`.
const iosLessonWidgetKind = 'KiuLessonWidget';
