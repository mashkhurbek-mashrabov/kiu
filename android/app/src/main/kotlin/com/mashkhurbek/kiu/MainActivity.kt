package com.mashkhurbek.kiu

import android.app.NotificationManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
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
                    result.success(
                        mapOf(
                            "versionName" to packageInfo.versionName,
                            "versionCode" to versionCode,
                        ),
                    )
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
