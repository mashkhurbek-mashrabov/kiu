# KIU Architecture

## Runtime Shape

KIU is an Android-only Flutter WebView shell for the Kazan Islamic University LMS. `main.dart` initializes timezone data, notifications, WorkManager, home-widget callbacks, persistence, and `AppController`. `BrowserPage` owns visible browsing, navigation controls, loading state, playback injection, and the bridge used by “Mark as watched.”

Dependencies remain split by responsibility:

- `SettingsRepository`: non-secret preferences, cached lessons, notification IDs, sync metadata, and WebView user agent.
- `ScheduleFetcher` and `ScheduleParser`: authenticated LMS retrieval and HTML-to-lesson conversion.
- `ReminderReconciler` and `LocalNotificationGateway`: desired reminder calculation, replacement, cancellation, and Android delivery.
- `TimeZoneService`: LMS wall-time interpretation and selected-zone display.
- `HomeLessonWidgetGateway`: serialized lesson snapshot and localized widget labels.

## Synchronization Flow

When authenticated Home finishes loading, on Home refresh, on app resume, or after “Sync now,” Flutter reads the active WebView user agent and starts a sync. A foreground timer repeats every 10 minutes while the app is visible; it does not reload or navigate the displayed page.

`AndroidCookieProvider` reads current WebView cookies. `ScheduleFetcher` sends them only to `https://uz.do-kazankiu.ru/uz/profile/my-online-lessons`, disables automatic redirects, rejects cross-host redirects, and never persists or logs cookie values. Missing cookies, redirects to sign-in, or HTML without `#enroll-courses`/`.enroll-courses` produce sign-in-required status without deleting cached reminders.

WorkManager chains unique network-constrained one-off work every 5 minutes when background synchronization is enabled. Android may defer work under Doze; this is best effort. Widget Sync invokes the same pipeline immediately. Force-stopping KIU prevents background execution until Android permits work again.

## Timezones and Reminders

Every parsed `yyyy-MM-dd HH:mm` value is treated as wall time in `Asia/Tashkent`, converted once to UTC, then converted to the selected IANA timezone for notification/widget display. This preserves one absolute lesson instant across device and app timezone changes, including DST destinations.

`ReminderReconciler` deduplicates offsets, ignores expired triggers, derives stable KIU-owned notification IDs, schedules exact alarms when allowed, and falls back to `inexactAllowWhileIdle`. Each successful snapshot adds or reschedules desired reminders and cancels stale KIU IDs. Timezone, locale, reminder, or offset changes reconcile cached lessons immediately.

## Home-Screen Widget

Flutter stores chronological lesson JSON and localized labels through `home_widget`. Native `KiuLessonWidgetService` renders future lessons yellow and started lessons green. Started rows become clickable only when a validated HTTPS meeting URL exists. Trusted LMS links reopen KIU; other valid HTTPS links use Android’s associated app/browser. Widget Sync dispatches a background callback, reuses cached WebView cookies, updates status, reconciles reminders, and refreshes widget data. Scheduled widget refreshes run at future lesson start instants so colors can change without a new LMS fetch.

## Trust Boundaries

The WebView may navigate HTTPS pages, but privileged JavaScript runs only when current URL matches the trusted LMS host. “Mark as watched” additionally requires a lesson/video route and confirmation. `KiuBridge` accepts only `{type, requestId, ok, code, payload}` results matching the active request; duplicate submissions are blocked and requests time out. Schedule data cannot trigger notifications until it passes same-host fetch checks, HTML parsing, date validation, offset bounds, and reminder reconciliation. Widget URLs require HTTPS with no user information before native launch routing.
