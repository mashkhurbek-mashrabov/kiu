# Repository Guidelines

## Project Structure & Module Organization

KIU is an Android-only Flutter LMS companion (`com.mashkhurbek.kiu`, Android API 24+). Dart code lives under `lib/`: `app/` wires dependencies and state, `domain/` holds settings and lesson models, `data/` persists non-secret state, `services/` owns synchronization, notifications, timezones, and widget data, `web/` builds injected JavaScript, and `ui/` renders the WebView shell. Tests mirror these responsibilities in `test/`; shared fakes belong in `test/support/`. Native Android channels and home-screen widget code live in `android/app/src/main/kotlin/com/mashkhurbek/kiu/`, with layouts and provider metadata under `res/`. Branding source is `kiu-logo.png`; release APKs go in `dist/`.

## Build, Test, and Development Commands

Use Flutter 3.47.2 with Dart 3.13.2.

- `flutter pub get` installs locked dependencies.
- `flutter run` launches KIU on a connected Android device or emulator.
- `dart format --output=none --set-exit-if-changed lib test` checks formatting.
- `flutter analyze` runs configured Flutter lints.
- `flutter test` runs unit and widget tests.
- `flutter build apk --release --split-per-abi` produces per-ABI release APKs.

## Coding Style & Naming Conventions

Follow `flutter_lints`, two-space Dart indentation, trailing commas, and formatter output. Name Dart files `lower_snake_case.dart`, types `UpperCamelCase`, members `lowerCamelCase`, and tests `*_test.dart`. Keep WebView, parser, persistence, notification, and native-widget responsibilities separated. Reuse existing gateways and constants; avoid speculative abstractions.

## Testing Guidelines

Add focused tests for behavior changes. Parser tests must cover malformed and duplicate LMS cards. Timezone tests must include Asia/Tashkent source times and DST-aware destinations. Widget/UI changes need widget tests; reminder changes need reconciliation tests. Run analysis and all tests before building an APK. Native widget changes also require installation on an API-33 emulator and manual click/sync verification.

## Commit & Pull Request Guidelines

Git history is not included in this workspace. Use Conventional Commits in imperative present tense, for example `fix(sync): accept LMS schedule container id`, and keep subjects under 72 characters. Pull requests should explain user-visible behavior, list verification commands, link issues, and include screenshots for UI or widget changes. Do not commit generated build directories.

## Security & Configuration

Never embed, log, or persist credentials or cookie values. Send WebView cookies only to the exact trusted HTTPS LMS host and reject cross-host redirects. Keep JavaScript and bridge actions gated by current trusted routes and validated payloads. Persist only non-secret settings, cached lessons, IDs, timestamps, statuses, and user agent.
