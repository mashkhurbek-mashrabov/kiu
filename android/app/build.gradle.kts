plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mashkhurbek.kiu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mashkhurbek.kiu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 32-bit ARM is dropped on purpose. Every device this ships to is arm64;
    // armeabi-v7a only added a third APK nobody installed. x86_64 stays for
    // the emulator.
    //
    // Build with `flutter build apk --release --split-per-abi`. One APK per
    // ABI keeps the arm64 download at ~20.8 MB; a combined APK carrying both
    // is 41.6 MB, half of it x86_64 that no phone ever runs.
    //
    // This must be a `splits` block rather than `defaultConfig.ndk.abiFilters`
    // -- Gradle refuses to configure when both are set ("Conflicting
    // configuration ... in ndk abiFilters cannot be present when splits abi
    // filters are set"), and `--split-per-abi` populates the splits side
    // itself. `reset()` clears Flutter's default list before naming our own.
    //
    // Flutter's tooling still expects an armeabi-v7a file afterwards and
    // prints "Gradle build failed to produce an .apk file"; the APKs in
    // build/app/outputs/flutter-apk/ are built and valid regardless.
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Measured on this project: without R8 the release APK is
            // 25.2 MB with ~15.9 MB of dex (workmanager pulls in a large
            // dependency tree); with it, 19.8 MB and ~1.9 MB of dex. Turning
            // this off costs roughly 5 MB.
            //
            // Every class the manifest names reflectively is protected in
            // proguard-rules.pro -- R8 cannot see those call sites, and a
            // missing keep breaks the widget or lesson calls *silently*, with
            // no crash. Re-verify calls, widget, alarms, and notifications on
            // a device after touching either file.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
