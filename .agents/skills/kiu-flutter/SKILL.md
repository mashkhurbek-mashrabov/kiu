---
name: kiu-flutter
description: Build and verify KIU Android Flutter changes involving its LMS WebView, schedule synchronization, reminders, or home-screen widget; do not use for unrelated Flutter projects.
---

# KIU Flutter Invariants

- Keep package `com.mashkhurbek.kiu`, Android minimum API 24, and Flutter/Dart compatibility at 3.47.2/3.13.2. Update `pubspec.yaml` version intentionally; version UI reads Android package metadata.
- Treat `https://uz.do-kazankiu.ru/uz/profile/my-online-lessons` as Home and `Asia/Tashkent` as LMS source timezone. Convert source wall time to UTC before selected-zone display or scheduling.
- Never embed, log, or persist credentials or cookie values. Read WebView cookies at request time, attach them only to exact trusted HTTPS host, disable automatic redirects, and reject cross-host redirects.
- Gate playback injection and `KiuBridge` messages by trusted current URL. Gate completion submission by lesson route, confirmation, unique request ID, duplicate prevention, validated envelope, and timeout.
- Preserve 10-minute foreground sync and unique 15-minute network-constrained WorkManager sync. Background timing is best effort; cached reminders survive auth expiry.
- When lesson/schema fields change, update Dart serialization, parser, widget JSON, Kotlin `RemoteViews`, persistence, and tests together.
- Build only with preinstalled Flutter 3.47.2/Dart 3.13.2; never download or install SDK during build. Verify with `flutter --version` first.
- Before delivery run `flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, then `flutter build apk --release --split-per-abi`.
- Copy `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` and `app-x86_64-release.apk` to `dist/KIU-<pubspec version>-arm64-v8a.apk` and `dist/KIU-<pubspec version>-x86_64.apk`. Install x86-64 APK on API-33 emulator; verify navigation, More/version, widget rendering, widget Sync, click routing, and no fatal logs. Deliver ARM64 APK from `dist/`, below 30 MB.
