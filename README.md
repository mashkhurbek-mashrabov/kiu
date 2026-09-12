# KIU

Kazan Islamic University LMS companion for Android (API 24+).

## Verify and build release APKs

Prerequisites:

- Flutter 3.47.2 with Dart 3.13.2, installed locally
- Android SDK installed and accepted by `flutter doctor`
- JDK 17

Do not download or install Flutter during builds. `flutter --version` must
report Flutter 3.47.2 and Dart 3.13.2 before continuing.

From repository root:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Build creates one APK per ABI:

- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`

Copy release artifacts to `dist/` using version from `pubspec.yaml`:

```sh
VERSION="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' pubspec.yaml)"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  "dist/KIU-${VERSION}-arm64-v8a.apk"
cp build/app/outputs/flutter-apk/app-x86_64-release.apk \
  "dist/KIU-${VERSION}-x86_64.apk"
```

Release builds currently use debug signing. Configure a production signing
config before distributing APKs publicly.
