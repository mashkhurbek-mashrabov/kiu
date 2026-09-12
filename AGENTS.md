# Repository Guidelines

## Project Structure & Module Organization

KIU is an Android-only Flutter LMS companion (`com.mashkhurbek.kiu`, Android API 24+). Dart code lives under `lib/`: `app/` wires dependencies and state, `domain/` holds settings and lesson models, `data/` persists non-secret state, `services/` owns synchronization, notifications, timezones, and widget data, `web/` builds injected JavaScript, and `ui/` renders the WebView shell. Tests mirror these responsibilities in `test/`; shared fakes belong in `test/support/`. Native Android channels, home-screen widget code, and lesson-call handling (alarms, receiver, full-screen activity, boot receiver, link routing) live in `android/app/src/main/kotlin/com/mashkhurbek/kiu/`, with layouts (widget and lesson-call UI), drawable resources, and provider metadata under `res/`. Branding source is `kiu-logo.png`; release APKs go in `dist/`.

## Build, Test, and Development Commands

Use Flutter 3.47.2 with Dart 3.13.2.

- `flutter pub get` installs locked dependencies.
- `flutter run` launches KIU on a connected Android device or emulator.
- `dart format --output=none --set-exit-if-changed lib test` checks formatting.
- `flutter analyze` runs configured Flutter lints.
- `flutter test` runs unit and widget tests.
- `flutter build apk --release --split-per-abi` produces per-ABI release APKs.

## Coding Style & Naming Conventions

Follow `flutter_lints`, two-space Dart indentation, trailing commas, and formatter output. Name Dart files `lower_snake_case.dart`, types `UpperCamelCase`, members `lowerCamelCase`, and tests `*_test.dart`. Keep WebView, parser, persistence, notification, native-widget, and call-handling responsibilities separated. Reuse existing gateways and constants; avoid speculative abstractions.

## Testing Guidelines

Add focused tests for behavior changes. Parser tests must cover malformed and duplicate LMS cards. Timezone tests must include Asia/Tashkent source times and DST-aware destinations. Widget/UI changes need widget tests; reminder changes need reconciliation tests. Run analysis and all tests before building an APK. Native widget and call changes require installation on an API-33 emulator and manual click/sync verification. A lesson call can be triggered without waiting for a real lesson start, because `LessonCallActivity` and `LessonCallReceiver` are marked `exported="true"` in `android/app/src/debug/AndroidManifest.xml` only and remain `exported="false"` in release builds:

```sh
adb shell "am broadcast -n com.mashkhurbek.kiu/.LessonCallReceiver \
  -a com.mashkhurbek.kiu.action.LESSON_CALL_RING --ei requestCode 1 \
  --es key 'k1' --es title 'Arabic Grammar' \
  --es displayStart '14:00 | 12-09-2026' \
  --es meetingUrl 'https://meet.google.com/abc-defg-hij'"
```

The quoting matters: `adb shell` re-parses the command on the device, so unquoted spaces and the `|` character corrupt the extras. Use outer double quotes with inner single quotes.

## Commit & Pull Request Guidelines

Git history is not included in this workspace. Use Conventional Commits in imperative present tense, for example `fix(sync): accept LMS schedule container id`, and keep subjects under 72 characters. Pull requests should explain user-visible behavior, list verification commands, link issues, and include screenshots for UI or widget changes. Do not commit generated build directories.

## Local Release Notes

Maintain one Markdown file per app version in `.release-notes/` (for example, `.release-notes/1.2.2.md`). After every change, update current version file with concise, factual user-visible changes. Use its contents to draft GitHub release summaries. `.release-notes/` is local-only: never commit or push it.

## Security & Configuration

Never embed, log, or persist credentials or cookie values. Send WebView cookies only to the exact trusted HTTPS LMS host and reject cross-host redirects. Keep JavaScript and bridge actions gated by current trusted routes and validated payloads. Persist only non-secret settings, cached lessons, IDs, timestamps, statuses, and user agent.

For lesson calls, the `SYSTEM_ALERT_WINDOW` permission is declared. The Answer button routes only HTTPS links through the existing trusted-host validation in `LessonLinkRouter`; non-HTTPS, blank, or LMS-host links open the KIU app instead of an external target.

## Lesson Call Constraints

Each of the following cost real debugging time to establish, so treat them as settled rather than re-deriving them.

Call scheduling data rides the `home_widget` SharedPreferences payload rather than a method channel, because alarms must be armable from the background WorkManager isolate, where `MainActivity`'s method channel does not exist. `HomeLessonWidgetGateway.publish` writes a `calls` entry, and both `KiuLessonWidgetProvider.onUpdate` and the boot receiver call `LessonCallAlarms.rearm`. Do not introduce a second method channel for this.

A full-screen intent only launches the call activity while the device is locked or the screen is off; when the phone is unlocked and in use, Android downgrades it to a heads-up notification. `LessonCallReceiver` therefore also calls `startActivity` directly, which requires `SYSTEM_ALERT_WINDOW`. Without that permission Android blocks the background activity start and only the heads-up banner appears, which is the designed fallback rather than a defect.

Notification actions that need to start an activity must use `getActivity` PendingIntents. Android 12 and later block a broadcast receiver reached from a notification action as a "notification trampoline". The Answer action therefore points at `LessonCallActivity`, which opens the meeting link itself, while `LessonCallReceiver` only ever stops the call.

Do not attempt to deep-link Settings' per-app overlay screen. Launching `Settings$AppDrawOverlaySettingsActivity` fails because it requires `android.permission.INTERNAL_SYSTEM_WINDOW`, a signature permission no third-party app can hold. Use `ACTION_MANAGE_OVERLAY_PERMISSION` with a `package:` URI instead; AOSP ignores the URI and shows the full app list, and that is accepted.
