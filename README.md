# KIU

Kazan Islamic University LMS companion for Android (API 24+).

## Build release APKs

Prerequisites:

- Flutter 3.47.2 with Dart 3.13.2
- Android SDK installed and accepted by `flutter doctor`
- JDK 17

From repository root:

```sh
flutter pub get
flutter build apk --release --split-per-abi
```

Build creates one APK per ABI:

- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`

Release builds currently use debug signing. Configure a production signing
config before distributing APKs publicly.
