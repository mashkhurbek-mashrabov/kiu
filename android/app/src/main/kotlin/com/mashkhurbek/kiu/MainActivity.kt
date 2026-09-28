package com.mashkhurbek.kiu

import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Bundle
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SOUND_PICKER_REQUEST = 1001
        private const val INSTALL_RESULT_ACTION =
            "com.mashkhurbek.kiu.action.INSTALL_RESULT"
    }

    private var pendingSoundResult: MethodChannel.Result? = null

    /// Held so an install result arriving in [onNewIntent] can be pushed to
    /// Dart, which is the only thing that can clear the gate's "installing"
    /// state. Cleared in [cleanUpFlutterEngine] so a destroyed engine is never
    /// called into.
    private var platformChannel: MethodChannel? = null

    /// Media session + PiP, on its own channel because the Dart side of
    /// [platformChannel] already has its one handler. Nulled with the engine.
    private var mediaChannel: MethodChannel? = null

    /// Whether the page's lesson video is playing; gates PiP entry.
    private var videoPlaying = false

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
    //
    // Every *other* status is terminal, and must be forwarded to Dart. The user
    // declining or dismissing that prompt is the common case, and it used to be
    // dropped here: the gate stayed on "installing" with no button and, being
    // mandatory, no way back into the app until the process was force-stopped.
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
            // A prompt that cannot be launched is itself a dead end, so it is
            // reported rather than left to hang the gate.
            val launched = confirm?.let {
                runCatching { startActivity(it) }.isSuccess
            } ?: false
            if (!launched) notifyInstallResult(false)
            return
        }
        // STATUS_SUCCESS needs no message: the process is replaced by the new
        // APK before anything could render it. Reporting it anyway is harmless
        // and keeps the contract "every terminal status is forwarded".
        notifyInstallResult(status == PackageInstaller.STATUS_SUCCESS)
    }

    /**
     * Tells Dart the install finished, so the gate can leave its "installing"
     * state. Safe to call when the engine is gone -- the channel is null until
     * [configureFlutterEngine] runs and after the engine is destroyed.
     */
    private fun notifyInstallResult(success: Boolean) {
        platformChannel?.invokeMethod(
            "installResult",
            mapOf("success" to success),
        )
    }

    /**
     * Shows the one-tap "allow KIU to ignore battery optimizations?" dialog.
     *
     * Unlike every other background permission this one has a real dialog, reached by
     * ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS with a `package:` URI. Sending it without
     * holding REQUEST_IGNORE_BATTERY_OPTIMIZATIONS throws, and sending it while already exempt
     * does nothing at all -- the system dismisses it immediately -- so both cases fall back to
     * the settings list, which always renders something the user can act on.
     *
     * Returns true when the dialog was actually launched, so the caller knows whether to expect
     * an answer or whether it dropped back to the list.
     */
    private fun requestBatteryExemption(): Boolean {
        val manager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (manager.isIgnoringBatteryOptimizations(packageName)) return false
        val launched = runCatching {
            @android.annotation.SuppressLint("BatteryLife")
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:$packageName"))
            startActivity(intent)
        }.isSuccess
        if (!launched) {
            runCatching {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }
        }
        return launched
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

    /**
     * Mirrors a `videoState` from the page into [LessonPlaybackService].
     *
     * The service is only *started* for a playing video, which only happens
     * while the app is visible -- a background FGS start is blocked on Android
     * 12+. Later updates (a pause from the car, say) reach the running
     * instance directly instead of starting it again.
     */
    private fun updatePlayback(call: MethodCall) {
        val playing = call.argument<Boolean>("playing") == true
        videoPlaying = playing
        LessonPlaybackService.state = LessonPlaybackService.State(
            playing = playing,
            title = call.argument<String>("title").orEmpty(),
            positionMs = ((call.argument<Double>("position") ?: 0.0) * 1000).toLong(),
            durationMs = ((call.argument<Double>("duration") ?: 0.0) * 1000).toLong(),
            speed = (call.argument<Double>("speed") ?: 1.0).toFloat(),
            labels = LessonPlaybackService.Labels(
                channelName = call.argument<String>("channelName") ?: "Lesson video",
                play = call.argument<String>("playLabel") ?: "Play",
                pause = call.argument<String>("pauseLabel") ?: "Pause",
                rewind = call.argument<String>("rewindLabel") ?: "-10 s",
                forward = call.argument<String>("forwardLabel") ?: "+10 s",
                close = call.argument<String>("closeLabel") ?: "Close",
            ),
        )
        // A car "play" while the screen is off: the WebView was already told
        // it is hidden, which would leave the video stuck.
        if (playing && window.decorView.windowVisibility != View.VISIBLE) {
            keepWebViewsVisible()
        }
        val running = LessonPlaybackService.instance
        if (running != null) {
            running.render()
        } else if (playing) {
            val intent = Intent(this, LessonPlaybackService::class.java)
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            }
        }
        updatePipParams()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A 0x0 sentinel, because the window-visibility callback is only
        // public on a View (the ViewTreeObserver listener is hidden API and
        // crashes on API 33). Posted, so it runs after the system's GONE has
        // reached every view, the WebView included.
        addContentView(
            object : View(this) {
                override fun onWindowVisibilityChanged(visibility: Int) {
                    super.onWindowVisibilityChanged(visibility)
                    if (visibility != VISIBLE && videoPlaying) post { keepWebViewsVisible() }
                }
            }.apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO },
            ViewGroup.LayoutParams(0, 0),
        )
    }

    /**
     * Tells every WebView its window is still visible.
     *
     * Chromium suspends a WebView's media once its *window* stops being
     * visible (screen off, PiP swiped away). A JS `play()` does not help:
     * verified on the API-33 emulator, the video then reports "playing" while
     * its position never moves. Window visibility is the one signal the WebView
     * gates media on, so while a lesson plays it is re-asserted here; the real
     * VISIBLE arrives on its own when the window comes back.
     *
     * ponytail: the WebView keeps ticking animation frames while hidden; add a
     * JS rAF throttle if battery use with the screen off ever shows up.
     */
    private fun keepWebViewsVisible(view: View = window.decorView) {
        when (view) {
            is WebView -> view.dispatchWindowVisibilityChanged(View.VISIBLE)
            is ViewGroup -> for (i in 0 until view.childCount) {
                keepWebViewsVisible(view.getChildAt(i))
            }
        }
    }

    private fun stopPlayback() {
        videoPlaying = false
        LessonPlaybackService.state = null
        stopService(Intent(this, LessonPlaybackService::class.java))
        updatePipParams()
    }

    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        // Android 12+ enters PiP by itself on Home/gesture while this is set,
        // which animates far better than entering from onUserLeaveHint.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(videoPlaying)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching { setPictureInPictureParams(pipParams()!!) }
    }

    // Android 8-11 have no auto-enter; leaving the app is the cue instead.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!videoPlaying) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            runCatching { enterPictureInPictureMode(pipParams()!!) }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        mediaChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    // The WebView playing the audio dies with the activity, so the
    // notification and session must not outlive it.
    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val media = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mashkhurbek.kiu/media",
        )
        mediaChannel = media
        LessonPlaybackService.commandSink = { action ->
            mediaChannel?.invokeMethod("command", action)
        }
        media.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> updatePlayback(call)
                "clear" -> stopPlayback()
                else -> return@setMethodCallHandler result.notImplemented()
            }
            result.success(null)
        }
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mashkhurbek.kiu/platform",
        )
        platformChannel = channel
        channel.setMethodCallHandler { call, result ->
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
                "requestBatteryExemption" -> {
                    result.success(requestBatteryExemption())
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        platformChannel = null
        mediaChannel = null
        LessonPlaybackService.commandSink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
