# KIU

Kazan Islamic University LMS companion for Android (API 24+).

A WebView shell over `uz.do-kazankiu.ru` plus the things the site cannot do on a
phone:

- **Schedule sync** — reads your online-lesson schedule using the session you
  are already signed into, in the foreground and in the background.
- **Reminders** — configurable offsets before each lesson, with per-offset
  sounds and exact-alarm support.
- **Home-screen widget** — upcoming lessons grouped by day, colour-coded, with
  one-tap join and per-lesson call toggles.
- **Lesson calls** — a full incoming-call screen when a lesson starts, so it is
  as hard to miss as a phone call.
- **Playback speed**, in-app PDF reader, and four languages (Uzbek Cyrillic and
  Latin, Russian, English) applied to the app *and* the site.

Documentation: [ARCHITECTURE.md](ARCHITECTURE.md) for how it fits together,
[CLAUDE.md](CLAUDE.md) for contributor guidance and the non-obvious invariants.

## Setup

Prerequisites: Flutter 3.47.2 / Dart 3.13.2, the Android SDK accepted by
`flutter doctor`, and JDK 17.

The SDK is pinned and **not on `PATH`** (see `android/local.properties`):

```bash
export PATH="/home/dev/.cache/kiu-flutter-3.47.2/flutter/bin:$PATH"
```

Do not download or install Flutter during a build. `flutter --version` must
report 3.47.2 / 3.13.2 before continuing.

```bash
flutter pub get
```

## Verify

All three must pass before any build or delivery:

```bash
flutter analyze && flutter test && dart format --output=none --set-exit-if-changed lib test
```

After editing any `lib/l10n/*.arb`, regenerate and confirm no drift — the
generated Dart is committed:

```bash
flutter gen-l10n && git status --short lib/l10n/
```

Native widget, alarm, and lesson-call changes are **not** covered by the test
suite. R8 is enabled, and a stripped reflective entry point fails silently
rather than crashing, so install on an API-33 emulator and verify by hand. See
the testing section of [CLAUDE.md](CLAUDE.md), including the `adb` command that
fakes an incoming call without waiting for a real lesson.

## Build release APKs

```bash
flutter build apk --release --split-per-abi
```

Produces one APK per ABI under `build/app/outputs/flutter-apk/`:

| ABI | Size |
|---|---|
| `app-arm64-v8a-release.apk` | ~19.8 MB |
| `app-x86_64-release.apk` | ~21.3 MB |
| `app-armeabi-v7a-release.apk` | ~17.6 MB |

Copy artifacts to `dist/` using the version from `pubspec.yaml`:

```bash
VERSION="$(sed -n 's/^version: \([0-9.+]*\).*/\1/p' pubspec.yaml)"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "dist/KIU-${VERSION}-arm64-v8a.apk"
cp build/app/outputs/flutter-apk/app-x86_64-release.apk "dist/KIU-${VERSION}-x86_64.apk"
```

Install the x86_64 APK on an API-33 emulator to verify; ship the ARM64 one.

> **Release builds currently use debug signing.** Configure a production signing
> config before distributing APKs publicly.
