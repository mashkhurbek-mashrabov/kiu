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
- `android/app/src/main/kotlin/com/mashkhurbek/kiu/` — native channels, home-screen widget
- `android/.../res/` — layouts, provider metadata
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

`flutter_lints`, 2-space indent, trailing commas, formatter output. Files `lower_snake_case.dart`, types `UpperCamelCase`, members `lowerCamelCase`, tests `*_test.dart`. Keep WebView/parser/persistence/notification/native-widget concerns separated. Reuse existing gateways/constants — no speculative abstractions.

## Testing

Add focused tests per behavior change. Parser tests: malformed + duplicate LMS cards. Timezone tests: Asia/Tashkent source + DST-aware destinations. Widget/UI changes need widget tests; reminder changes need reconciliation tests. Run analyze + full test suite before building APK. Native widget changes: also install on API-33 emulator, verify click/sync manually.

## Commits & PRs

Conventional Commits, imperative present tense, subject <72 chars (e.g. `fix(sync): accept LMS schedule container id`). PRs: describe user-visible behavior, list verification commands, link issues, screenshots for UI/widget changes. Never commit generated build dirs.

## Release notes

One markdown file per version in `.release-notes/` (e.g. `.release-notes/1.2.2.md`). Update current version's file after every change with concise, factual user-visible changes. Source for GitHub release summaries. `.release-notes/` is local-only — never commit/push.

## Security

Never embed/log/persist credentials or cookie values. Send WebView cookies only to exact trusted HTTPS LMS host; reject cross-host redirects. Gate JS and bridge actions by current trusted routes + validated payloads. Persist only non-secret settings, cached lessons, IDs, timestamps, statuses, user agent.
