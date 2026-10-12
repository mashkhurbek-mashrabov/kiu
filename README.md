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

Prerequisites: global Flutter stable (3.47.x) with a Dart satisfying `^3.13.2`,
the Android SDK accepted by `flutter doctor`, and JDK 17.

Flutter is the global Homebrew install, already on `PATH`
(`/opt/homebrew/bin/flutter`) — no PATH prefix needed. `ANDROID_HOME` and
`JAVA_HOME` come from `~/.zshrc`, which also puts `adb` and `emulator` on
`PATH`. If a shell did not load it, export them first:

```bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
```

Do not download or install Flutter during a build. `flutter --version` must
report Flutter 3.47.x stable before continuing.

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
rather than crashing, so install on the `pixel_api35` emulator (API 35) and
verify by hand. See the testing section of [CLAUDE.md](CLAUDE.md), including
the `adb` command that fakes an incoming call without waiting for a real lesson.

## Build release APKs

```bash
flutter build apk --release --split-per-abi
```

Produces one APK per ABI under `build/app/outputs/flutter-apk/`:

| ABI | Size |
|---|---|
| `app-arm64-v8a-release.apk` | ~21.0 MB |
| `app-x86_64-release.apk` | ~22.5 MB |

`armeabi-v7a` is deliberately not built (see `android/app/build.gradle.kts`).
Flutter still looks for that APK and ends with `Gradle build failed to produce
an .apk file`; that message is expected, and the two APKs above are complete.

Copy artifacts to `dist/` using the version from `pubspec.yaml`:

```bash
VERSION="$(sed -n 's/^version: \([0-9.+]*\).*/\1/p' pubspec.yaml)"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "dist/KIU-${VERSION}-arm64-v8a.apk"
cp build/app/outputs/flutter-apk/app-x86_64-release.apk "dist/KIU-${VERSION}-x86_64.apk"
```

Install the ARM64 APK on the `pixel_api35` emulator (Pixel 8, API 35,
arm64-v8a) to verify, and ship that same ARM64 APK. The x86_64 APK does not
install on this emulator.

```bash
emulator -avd pixel_api35 &   # wait until the next line prints 1
adb shell getprop sys.boot_completed
adb install -r "dist/KIU-${VERSION}-arm64-v8a.apk"
```

> **Release builds are signed with the real keystore** through
> `android/key.properties` (gitignored, as is the `*.jks`). If that file is
> missing, Gradle silently falls back to the debug key; never publish that
> build. See [CLAUDE.md](CLAUDE.md) and
> `.claude/skills/publish-release/SKILL.md` for the signer check.
