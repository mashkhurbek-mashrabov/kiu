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
- `lib/l10n/` — `.arb` sources (template `app_uz_Cyrl.arb`) + committed generated output
- `lib/ui/widgets/` — shared settings building blocks (`SettingsSection`,
  `SettingsRow`, `SettingsSwitchRow`, `InfoHint`, `SheetHeader`)
- `lib/core/` — constants, trusted-host rules, theme
- `test/` — mirrors lib/ structure; shared fakes in `test/support/`
- `android/app/src/main/kotlin/com/mashkhurbek/kiu/` — native channels, home-screen widget, lesson calls (alarms, receiver, activity, boot, link routing)
- `android/.../res/` — layouts (widget, lesson-call UI), drawables, provider metadata
- `dist/` — release APKs
- `kiu-logo.png` — branding source

## Commands

Flutter 3.47.2, Dart 3.13.2. **The SDK is not on `PATH`** — it lives at
`/home/dev/.cache/kiu-flutter-3.47.2/flutter` (see `android/local.properties`).
Prefix every command:

```sh
export PATH="/home/dev/.cache/kiu-flutter-3.47.2/flutter/bin:$PATH"
```

- `flutter pub get` — install deps
- `flutter run` — launch on device/emulator
- `dart format --output=none --set-exit-if-changed lib test` — format check
- `flutter analyze` — lints
- `flutter test` — unit/widget tests
- `flutter gen-l10n` — regenerate `lib/l10n/app_localizations*.dart` after any
  `.arb` edit; the generated files are committed and must not drift
- `flutter build apk --release --split-per-abi` — release APKs

## Style

`flutter_lints`, 2-space indent, trailing commas, formatter output. Files `lower_snake_case.dart`, types `UpperCamelCase`, members `lowerCamelCase`, tests `*_test.dart`. Keep WebView/parser/persistence/notification/native-widget/call concerns separated. Reuse existing gateways/constants — no speculative abstractions.

## Rules

Non-obvious invariants. Each one cost a real bug.

**Persistence reads must be tolerant.** `SettingsRepository.loadSettings()` runs
in `AppController`'s initializer list and in the WorkManager background isolate.
A throw there is an unrecoverable launch crash: SharedPreferences is the only
store, so the user cannot clear the bad value without reinstalling. Never
`as`-cast decoded JSON or use `int.parse` on stored values. Follow
`_loadCallOverrides` / `_loadReminderOffsets` / `Lesson.tryFromJson`: check the
shape, drop what is unusable, return a default.

**Nullable settings clear via a sentinel.** `AppSettings.copyWith` uses
`_unset` for the four nullable sound fields so `null` means *clear* and omission
means *keep*; `saveSettings` pairs this with `_writeOrRemove`. A plain
`value ?? this.value` plus `if (value != null) setString(...)` makes a reset
impossible — the old sound silently returns on next load.

**Do not call `notifyListeners()` for sync progress.** `KiuApp` rebuilds the
whole `MaterialApp`, WebView included, and the foreground sync runs every 10
minutes while the user may be watching a lesson. Sync state goes through
`AppController.syncState` (a `ValueNotifier`) and is rendered by exactly one
`ValueListenableBuilder` in the settings sheet. Reserve `notifyListeners()` for
state the main tree actually renders.

**`synchronize()` coalesces.** Resuming on Home fires a sync from both the
lifecycle observer and `_pageFinished`. The `_inFlightSync` guard collapses
overlapping calls into one fetch; don't bypass it.

**R8 is on.** `isMinifyEnabled` + `isShrinkResources` save ~5 MB (25.2 MB → 19.8
MB; dex 15.9 MB → 1.9 MB). Everything the manifest instantiates by name is
listed in `android/app/proguard-rules.pro`. A missing `-keep` breaks the widget
or lesson calls **silently at runtime** — no crash, no log. Keep the rules
narrow: an over-broad `-keep pkg.** { *; }` measurably *grows* the dex under
`proguard-android-optimize`. Re-verify on a device after touching either file.

**Settings rows stay one line; long prose goes in an `InfoHint`.** A row shows
a short label and at most its current value. Any explanation longer than that
is passed as `hint:` and reached by tapping the ⓘ — never as a wrapped
subtitle, which is what made the old sheets scroll for pages. `InfoHint` uses
`TooltipTriggerMode.manual` on purpose: hover tooltips never fire on a touch
screen, so a plain `Tooltip` would make the help unreachable on the only
platform this app ships to.

**A settings container must be a `Material`, not a `DecoratedBox`.**
`ListTile` paints its ink splash on the nearest `Material` ancestor, so a bare
colored box around the rows silently swallows every tap ripple — no error, the
taps just stop feeling like taps. `SettingsSection` already does this; reuse it
rather than hand-rolling a container.

**The widget palette is duplicated, not shared.** `res/values/colors.xml` and
`WidgetTheme.kt` mirror `lib/core/theme.dart` on purpose: `RemoteViews`
`setTextColor` needs a resolved int, and the widget follows the in-app
Appearance setting rather than the `-night` resource qualifier, so Android
cannot pick the variant. Change the Dart palette and both native copies
together or the widget drifts from the app.

**The call screen must never scroll.** `kiu_lesson_call.xml` is a plain
`LinearLayout`, not a `ScrollView`: the brand row, countdown and button row are
fixed and the identity block takes `layout_weight="1"`, so Answer can never be
pushed off screen. It also draws edge to edge and re-applies the system-bar
insets as padding in `applyWindowInsets()` — framework `WindowInsets`, not
androidx, because the activity extends plain `Activity` and the module declares
no androidx.core dependency of its own.

**`clipChildren="false"` must be set on *every* ancestor.** The answer button's
idle nudge translates it beyond its row, and a single parent still clipping
shears a flat edge off the circle. The root `call_root`, the button row and both
button columns all carry it — setting it on the inner containers alone is not
enough and looks correct until the animation reaches its peak.

**`values-hNdp` means "at least N dp", never "at most".** A height qualifier
can only add space for taller screens; it cannot rescue a shorter one. So the
compact call metrics live in plain `values/dimens.xml` as the floor and
`values-h700dp` opens the layout up on a normal phone. Getting this backwards
silently clips the start-time pill on small devices while looking fine on the
one you happen to be testing.

**Reminder text is localized.** `ReminderReconciler` loads
`AppLocalizations.delegate` directly (no `BuildContext` in the background
isolate). Add strings to all four `.arb` files, never inline them.

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

During development the file is an append-only running log — one bullet per change, however granular. **When the GitHub release is published, summarize that version's file** into the shipped notes: merge bullets that describe the same user-visible feature (a feature plus its later fixes is one bullet), drop churn that never reached the user (work reverted or superseded inside the same version), and order by what the user notices first — new features, then changes, then fixes. Keep it factual and user-facing; no commit hashes, file paths, or internal refactor notes. Publish the summarized text as the GitHub release body and overwrite the version's file with it, so the file matches what shipped.

## Branching & versions

Branch per feature, tag per version — no version branches, no `develop`. Work on `feat/<slug>` or `fix/<slug>` off `main`, merge back, then bump `version:` in `pubspec.yaml` in its own `chore(release): <version>` commit and tag `v<version>`. Build release APKs from the tag. Bump the build number (`+N`) on every release and never reuse one — Android rejects a duplicate on upgrade. Create a `release/<x.y>.x` branch only if a shipped version actually needs a patch after `main` has moved on.

## Security

Never embed/log/persist credentials or cookie values. Send WebView cookies only to exact trusted HTTPS LMS host; reject cross-host redirects. Gate JS and bridge actions by current trusted routes + validated payloads. Persist only non-secret settings, cached lessons, IDs, timestamps, statuses, user agent.

Calls: `SYSTEM_ALERT_WINDOW` declared. Answer routes only HTTPS links via trusted-host rule (`LessonLinkRouter`); non-HTTPS/blank/LMS-host links open the app instead of an external target.

## Lesson calls — constraints

Each cost real debugging; don't re-litigate.

- Background sync is a **self-chaining 5-minute one-off**, not a `PeriodicWorkRequest` (WorkManager's floor is 15 min). Each run schedules the next in a `finally`; drop that and the chain dies permanently until the app is reopened. Foreground sync is a separate 10-minute timer.
- Scheduling rides the `home_widget` prefs payload, not a method channel — alarms must arm from the WorkManager background isolate, where `MainActivity`'s channel doesn't exist. `HomeLessonWidgetGateway.publish` writes `calls`; `KiuLessonWidgetProvider.onUpdate` and the boot receiver both call `LessonCallAlarms.rearm`. Don't add a second channel.
- A full-screen intent launches the activity only while locked/screen-off. Unlocked, Android downgrades to a heads-up banner. `LessonCallReceiver` therefore also calls `startActivity`, which needs `SYSTEM_ALERT_WINDOW`; without it the background activity start is blocked and only the banner shows. That's the designed fallback, not a bug.
- Notification actions that start an activity must be `getActivity` PendingIntents. Android 12+ blocks a broadcast receiver reached from a notification action as a "notification trampoline". Answer points at `LessonCallActivity`, which opens the link itself; `LessonCallReceiver` only ever stops things.
- Don't deep-link Settings' per-app overlay screen. `Settings$AppDrawOverlaySettingsActivity` requires `android.permission.INTERNAL_SYSTEM_WINDOW`, a signature permission no third-party app can hold. Use `ACTION_MANAGE_OVERLAY_PERMISSION` with a `package:` URI; AOSP ignores the URI and shows the full app list, which is accepted.
