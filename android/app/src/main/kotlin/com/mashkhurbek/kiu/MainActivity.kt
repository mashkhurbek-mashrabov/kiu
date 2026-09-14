package com.mashkhurbek.kiu

import android.app.NotificationManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SOUND_PICKER_REQUEST = 1001
    }

    private var pendingSoundResult: MethodChannel.Result? = null

    @Deprecated("Deprecated in Android API; required by FlutterActivity's picker flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SOUND_PICKER_REQUEST) return
        val result = pendingSoundResult ?: return
        pendingSoundResult = null
        val sound = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data?.getParcelableExtra(
                RingtoneManager.EXTRA_RINGTONE_PICKED_URI,
                Uri::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra<Uri>(
                RingtoneManager.EXTRA_RINGTONE_PICKED_URI,
            )
        }
        if (sound == null) {
            result.success(null)
            return
        }
        val name = RingtoneManager.getRingtone(applicationContext, sound)
            ?.getTitle(applicationContext)
            ?: sound.lastPathSegment
        result.success(mapOf("uri" to sound.toString(), "name" to name))
    }

    /**
     * Opens Android's "Display over other apps" screen.
     *
     * The `package:` URI is honoured on OEM builds that support it and lands straight on KIU's
     * own toggle; AOSP ignores it and shows the full app list instead, which is accepted.
     *
     * Do not try to deep-link Settings' per-app overlay screen directly: launching
     * `Settings$AppDrawOverlaySettingsActivity` fails with "requires
     * android.permission.INTERNAL_SYSTEM_WINDOW", a signature permission no third-party app can
     * hold. Verified on an API-33 emulator.
     */
    private fun openOverlaySettings() {
        runCatching {
            startActivity(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                    .setData(Uri.parse("package:$packageName")),
            )
        }
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName")),
            )
        }
    }

    // Hands a downloaded APK to the system installer.
    //
    // The file lives in the app's cache directory, which is not world
    // readable, so it is exposed through a FileProvider rather than a
    // `file://` URI -- the latter throws FileUriExposedException on API 24+.
    // The read grant is scoped to this one intent.
    private fun installApk(path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.updates",
            file,
        )
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mashkhurbek.kiu/platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    val installedVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION")
                        packageInfo.versionCode.toLong()
                    }
                    // Flutter prefixes split-APK version codes with ABI * 1000.
                    val versionCode = if (installedVersionCode >= 1000) {
                        installedVersionCode % 1000
                    } else {
                        installedVersionCode
                    }
                    // The prefix itself is reported separately: stripping it
                    // makes the build number comparable to the release marker,
                    // but the updater still needs to know which ABI's APK to
                    // download, and that is unrecoverable once it is gone.
                    val abi = (installedVersionCode / 1000).toInt()
                    result.success(
                        mapOf(
                            "versionName" to packageInfo.versionName,
                            "versionCode" to versionCode,
                            "abi" to abi,
                        ),
                    )
                }
                "getUpdateCacheDir" -> {
                    // Dart's Directory.systemTemp resolves to /tmp, which does
                    // not exist on Android -- writing there throws. The cache
                    // dir is also what the FileProvider's <cache-path> exposes,
                    // so the installer can read what we download.
                    result.success(cacheDir.absolutePath)
                }
                "canInstallPackages" -> {
                    result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls(),
                    )
                }
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_path", "Missing APK path.", null)
                    } else {
                        runCatching { installApk(path) }
                            .onSuccess { result.success(null) }
                            .onFailure {
                                result.error("install_failed", it.message, null)
                            }
                    }
                }
                "isBatteryOptimizationDisabled" -> {
                    val manager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(manager.isIgnoringBatteryOptimizations(packageName))
                }
                "openBatteryOptimizationSettings" -> {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                "canUseFullScreenIntent" -> {
                    val canUse = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                            .canUseFullScreenIntent()
                    } else {
                        true
                    }
                    result.success(canUse)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                                .setData(Uri.parse("package:$packageName")),
                        )
                    }
                    result.success(null)
                }
                "canDrawOverlays" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }
                "openOverlaySettings" -> {
                    openOverlaySettings()
                    result.success(null)
                }
                "selectNotificationSound" -> {
                    if (pendingSoundResult != null) {
                        result.error("sound_picker_in_progress", "Sound picker is already open", null)
                        return@setMethodCallHandler
                    }
                    pendingSoundResult = result
                    val currentSound = call.argument<String>("currentSound")
                    val ringtoneType = if (call.argument<String>("type") == "ringtone") {
                        RingtoneManager.TYPE_RINGTONE
                    } else {
                        RingtoneManager.TYPE_NOTIFICATION
                    }
                    val picker = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                        .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, ringtoneType)
                        .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                        .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                    currentSound?.let {
                        picker.putExtra(
                            RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                            Uri.parse(it),
                        )
                    }
                    startActivityForResult(picker, SOUND_PICKER_REQUEST)
                }
                else -> result.notImplemented()
            }
        }
    }
}
