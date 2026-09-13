# KIU Architecture

Android-only Flutter shell around the Kazan Islamic University LMS
(`uz.do-kazankiu.ru`). The app is a WebView over the real site plus everything
the site cannot do on a phone: schedule sync, reminders, a home-screen widget,
and phone-call-style lesson alerts.

## Layers

```
       ui/            browser_page.dart — WebView shell, settings sheets
        |
       app/           app.dart (KiuApp) · app_controller.dart (state, DI root)
        |
  ┌─────┴──────┬──────────────┐
services/     data/         domain/
  |             |             |
  |        settings_       lesson.dart
  |        repository     app_settings.dart
  |        (SharedPrefs)
  |
  ├── schedule_fetcher / schedule_parser   LMS HTML → Lesson
  ├── reminder_reconciler                  Lesson → notifications
  ├── notification_service                 Android delivery
  ├── lesson_widget_service                Lesson → home_widget prefs
  ├── time_zone_service                    wall time → UTC → display zone
  ├── background_access_service            battery/overlay/FSI permissions
  └── app_version_service                  package metadata

core/    constants (trusted hosts, URLs) · theme
web/     injected JavaScript (playback, site theme, mark-watched)
l10n/    .arb sources + committed generated Dart
```

Dependencies point inward: `ui` → `app` → `services` → `data`/`domain`. Every
platform-touching service sits behind an `abstract interface class` gateway
(`NotificationGateway`, `LessonWidgetGateway`, `CookieProvider`,
`BackgroundAccessGateway`, `BackgroundScheduler`, `AppVersionProvider`) with a
fake in `test/support/fakes.dart`, which is why the suite runs without a device.

`AppController` is the composition root and the only `ChangeNotifier`. Note the
deliberate split in how it publishes state — see "Rebuild discipline" below.

## Synchronization flow

Triggers: authenticated Home finishing load, Home refresh, app resume, "Sync
now", the 10-minute foreground timer, the WorkManager chain, and widget Sync.

1. Flutter reads the live WebView user agent.
2. `AndroidCookieProvider` reads current WebView cookies.
3. `ScheduleFetcher` sends them **only** to
   `https://uz.do-kazankiu.ru/<lang>/profile/my-online-lessons`, with redirects
   disabled and cross-host redirects rejected. Cookie values are never logged or
   persisted.
4. `ScheduleParser` converts `#enroll-courses` / `.enroll-courses` cards into
   `Lesson`s, deduplicating by key and validating lesson ids and meeting URLs.
5. `ReminderReconciler` caches the snapshot, prunes stale call overrides, and
   reconciles notifications.
6. `HomeLessonWidgetGateway` publishes widget + call payloads.

Missing cookies, a redirect to sign-in, or HTML without the schedule container
all yield `signInRequired` **without** deleting cached reminders — an expired
session must not silently cancel a student's alarms.

Overlapping syncs coalesce: `AppController.synchronize` holds the in-flight
future, so resume-on-Home (which triggers two) performs one fetch.

## Background isolate boundary

This constraint shapes the whole call feature. WorkManager and `home_widget`
callbacks run in a **separate Dart isolate** with no `MainActivity`, therefore
no method channel to it.

Consequences, all load-bearing:

- Call scheduling data rides the `home_widget` SharedPreferences payload (a
  `calls` JSON array), not a channel. `KiuLessonWidgetProvider.onUpdate` and
  `LessonCallBootReceiver` both call `LessonCallAlarms.rearm`, reading the same
  payload. Adding a second channel would break background arming.
- `ReminderReconciler` loads `AppLocalizations.delegate` directly instead of
  reading a `BuildContext`, which does not exist there.
- Background sync is a self-chaining 5-minute one-off (WorkManager's periodic
  floor is 15 minutes). Each run reschedules the next in a `finally`; without
  that, one thrown exception ends all future reminders until the app reopens.

## Timezones

Every parsed `yyyy-MM-dd HH:mm` is wall time in `Asia/Tashkent`, converted once
to UTC, then rendered in the user's selected IANA zone. One absolute instant
survives device and app timezone changes, including DST destinations.

## Reminders

`ReminderReconciler` deduplicates offsets, bounds them to 0–10080 minutes,
derives KIU-owned notification ids from a stable FNV hash, schedules exact
alarms when permitted and falls back to `inexactAllowWhileIdle`, then cancels
only its own stale ids. A due-but-undelivered inexact alarm is retained for a
one-hour grace window. A single failing `schedule` call is logged and skipped
rather than aborting the batch. Bodies come from the `.arb` files.

## Persistence contract

`SharedPreferences` is the only store, and `loadSettings()` runs in
`AppController`'s **initializer list** — so a throw there is an unrecoverable
launch crash the user can only fix by reinstalling. Every read is therefore
tolerant: shape-check, drop unusable entries, fall back to a default
(`Lesson.tryFromJson`, `_loadReminderOffsets`, `_loadCallOverrides`).

Nullable sound settings use an `_unset` sentinel in `copyWith` plus
`_writeOrRemove` on save, so "reset to default" actually persists.

Only non-secret data is stored: settings, cached lessons, notification ids,
timestamps, status, and the user agent. Never credentials or cookies.

## Home-screen widget

Flutter writes chronological lesson JSON and pre-localized labels through
`home_widget`; `KiuLessonWidgetService` renders rows (future yellow, started
green). Started rows are clickable only with a validated HTTPS meeting URL.
Trusted LMS links reopen KIU; other HTTPS links go to the associated app or
browser. The widget follows the **in-app** appearance choice, not the OS
night-mode qualifier, so the resolved mode travels as a `widgetDark` flag and
`WidgetTheme` tints the RemoteViews.

Widget refreshes are scheduled at future lesson starts so colors change without
a fetch, capped at 16 to avoid one AlarmManager wake-up per lesson.

## Lesson calls

```
LessonCallAlarms.rearm       reads `calls` payload, arms one alarm per occurrence
        ↓ (AlarmManager, setAlarmClock or exact-and-allow-while-idle)
LessonCallReceiver.ring      posts notification + startActivity, arms timeout
        ↓
LessonCallActivity           full-screen ring UI; Answer opens the link itself
        ↓
LessonCallReceiver.stop      cancels notification, timeout alarm, and the UI
```

Three settled constraints (see CLAUDE.md — each cost real debugging):

- A full-screen intent only auto-launches while locked or screen-off. Unlocked,
  Android downgrades to a heads-up banner, so the receiver also calls
  `startActivity`, which needs `SYSTEM_ALERT_WINDOW`. Without it the banner is
  the designed fallback, not a bug.
- Notification actions that start an activity must be `getActivity` pending
  intents; a receiver reached from a notification action is a blocked
  "trampoline" on Android 12+. Hence Answer targets the activity, and the
  receiver only ever stops things.
- Whether the call screen will appear is decided **before** `startActivity`,
  because a blocked background start is silently dropped rather than throwing.
  That decision picks the silent vs. loud notification channel.

## Trust boundaries

- The WebView may browse any HTTPS page, but privileged JavaScript runs only
  when the current URL is the exact trusted LMS host (`isTrustedHttps`).
  `isSiteHttps` is broader (LMS + exam platform) and grants only language-prefix
  rewriting.
- "Mark as watched" additionally requires a lesson/video route and explicit
  confirmation. `KiuBridge` accepts only a `{type, requestId, ok, code, payload}`
  envelope matching the active request; duplicates are blocked and it times out.
- Schedule data cannot produce a notification until it passes same-host fetch
  checks, HTML parsing, date validation, offset bounds, and reconciliation.
- Widget and call URLs must be HTTPS with no user-info component before native
  routing (`LessonLinkRouter`).

## Build

R8 (`isMinifyEnabled` + `isShrinkResources`) is enabled: measured 25.2 MB → 19.8
MB, with dex dropping 15.9 MB → 1.9 MB. Manifest-instantiated classes are kept
explicitly in `android/app/proguard-rules.pro`; a missing rule fails silently at
runtime, so device verification is mandatory after touching it.
