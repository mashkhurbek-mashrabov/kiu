# CLAUDE.md

Guidance for Claude Code working in this repo.

## Project

KIU: Android-only Flutter LMS companion app (`com.mashkhurbek.kiu`, Android API 24+).

## Structure

- `lib/app/` — DI, state wiring
- `lib/domain/` — settings, lesson models
- `lib/data/` — non-secret state persistence
- `lib/services/` — sync, notifications, timezones, widget data
- `lib/web/` — injected JavaScript
- `lib/ui/` — WebView shell
- `test/` — mirrors lib/ structure; shared fakes in `test/support/`
- `android/app/src/main/kotlin/com/mashkhurbek/kiu/` — native channels, home-screen widget, lesson calls (alarms, receiver, activity, boot, link routing)
- `android/.../res/` — layouts (widget, lesson-call UI), drawables, provider metadata
- `dist/` — release APKs
- `kiu-logo.png` — branding source

## Commands

Flutter 3.47.2, Dart 3.13.2.

- `flutter pub get` — install deps
- `flutter run` — launch on device/emulator
- `dart format --output=none --set-exit-if-changed lib test` — format check
- `flutter analyze` — lints
- `flutter test` — unit/widget tests
- `flutter build apk --release --split-per-abi` — release APKs

## Style

`flutter_lints`, 2-space indent, trailing commas, formatter output. Files `lower_snake_case.dart`, types `UpperCamelCase`, members `lowerCamelCase`, tests `*_test.dart`. Keep WebView/parser/persistence/notification/native-widget/call concerns separated. Reuse existing gateways/constants — no speculative abstractions.

## Testing

Add focused tests per behavior change. Parser tests: malformed + duplicate LMS cards. Timezone tests: Asia/Tashkent source + DST-aware destinations. Widget/UI changes need widget tests; reminder changes need reconciliation tests. Run analyze + full test suite before building APK. Native widget and call changes: install on API-33 emulator, verify click/sync manually. Fake-trigger a call without waiting for a real lesson start — `LessonCallActivity`/`LessonCallReceiver` are `exported="true"` in `android/app/src/debug/AndroidManifest.xml` only, `false` in release:

```sh
adb shell "am broadcast -n com.mashkhurbek.kiu/.LessonCallReceiver \
  -a com.mashkhurbek.kiu.action.LESSON_CALL_RING --ei requestCode 1 \
  --es key 'k1' --es title 'Arabic Grammar' \
  --es displayStart '14:00 | 12-09-2026' \
  --es meetingUrl 'https://meet.google.com/abc-defg-hij'"
```

Outer double, inner single quotes required: `adb shell` re-parses on the device, and unquoted spaces or `|` corrupt the extras.

## Commits & PRs

Conventional Commits, imperative present tense, subject <72 chars (e.g. `fix(sync): accept LMS schedule container id`). PRs: describe user-visible behavior, list verification commands, link issues, screenshots for UI/widget changes. Never commit generated build dirs.

## Release notes

One markdown file per version in `.release-notes/` (e.g. `.release-notes/1.2.2.md`). Update current version's file after every change with concise, factual user-visible changes. Source for GitHub release summaries. `.release-notes/` is local-only — never commit/push.

## Security

Never embed/log/persist credentials or cookie values. Send WebView cookies only to exact trusted HTTPS LMS host; reject cross-host redirects. Gate JS and bridge actions by current trusted routes + validated payloads. Persist only non-secret settings, cached lessons, IDs, timestamps, statuses, user agent.

Calls: `SYSTEM_ALERT_WINDOW` declared. Answer routes only HTTPS links via trusted-host rule (`LessonLinkRouter`); non-HTTPS/blank/LMS-host links open the app instead of an external target.

## Lesson calls — constraints

Each cost real debugging; don't re-litigate.

- Scheduling rides the `home_widget` prefs payload, not a method channel — alarms must arm from the WorkManager background isolate, where `MainActivity`'s channel doesn't exist. `HomeLessonWidgetGateway.publish` writes `calls`; `KiuLessonWidgetProvider.onUpdate` and the boot receiver both call `LessonCallAlarms.rearm`. Don't add a second channel.
- A full-screen intent launches the activity only while locked/screen-off. Unlocked, Android downgrades to a heads-up banner. `LessonCallReceiver` therefore also calls `startActivity`, which needs `SYSTEM_ALERT_WINDOW`; without it the background activity start is blocked and only the banner shows. That's the designed fallback, not a bug.
- Notification actions that start an activity must be `getActivity` PendingIntents. Android 12+ blocks a broadcast receiver reached from a notification action as a "notification trampoline". Answer points at `LessonCallActivity`, which opens the link itself; `LessonCallReceiver` only ever stops things.
- Don't deep-link Settings' per-app overlay screen. `Settings$AppDrawOverlaySettingsActivity` requires `android.permission.INTERNAL_SYSTEM_WINDOW`, a signature permission no third-party app can hold. Use `ACTION_MANAGE_OVERLAY_PERMISSION` with a `package:` URI; AOSP ignores the URI and shows the full app list, which is accepted.
