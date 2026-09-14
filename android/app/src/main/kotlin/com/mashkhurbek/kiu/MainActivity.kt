package com.mashkhurbek.kiu

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SOUND_PICKER_REQUEST = 1001
        private const val INSTALL_RESULT_ACTION =
            "com.mashkhurbek.kiu.action.INSTALL_RESULT"
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

    // The PackageInstaller session reports back here (singleTop, so an existing
    // instance gets onNewIntent rather than a new activity).
    //
    // STATUS_PENDING_USER_ACTION carries the system's own confirmation prompt,
    // which has to be launched explicitly -- without this the commit succeeds
    // but the user is never asked anything and nothing installs.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action != INSTALL_RESULT_ACTION) return
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            }
            confirm?.let { runCatching { startActivity(it) } }
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

    // Streams a downloaded APK into a PackageInstaller session.
    //
    // Deliberately not ACTION_VIEW with the APK mime type: that is a generic
    // "open this file" request, so any app registered for
    // application/vnd.android.package-archive (a file manager, WPS Office)
    // competes for it and Android shows an "Open with" chooser. A session goes
    // straight to the system installer.
    //
    // Android still shows its own confirmation prompt, and always will for a
    // third-party app: silent install needs INSTALL_PACKAGES, a signature-level
    // permission only system or device-owner apps can hold.
    private fun installApk(path: String) {
        val file = File(path)
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        )
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            file.inputStream().use { input ->
                session.openWrite("kiu-update", 0, file.length()).use { output ->
                    input.copyTo(output, DEFAULT_BUFFER_SIZE)
                    session.fsync(output)
                }
            }
            // Must be mutable: the installer fills in the status extras.
            val intent = Intent(this, MainActivity::class.java)
                .setAction(INSTALL_RESULT_ACTION)
            // FLAG_MUTABLE only exists from API 31; below that a PendingIntent
            // is mutable by default and the constant is unavailable.
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            val pending = PendingIntent.getActivity(this, sessionId, intent, flags)
            session.commit(pending.intentSender)
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
                    // dir is where the update APK is written before it is
                    // streamed into the PackageInstaller session.
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
