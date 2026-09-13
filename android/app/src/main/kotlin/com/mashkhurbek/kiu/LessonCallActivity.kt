package com.mashkhurbek.kiu

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.ImageButton
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin

/** Full-screen incoming-lesson-call UI; mirrors a phone call screen. */
class LessonCallActivity : Activity() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var countDownTimer: CountDownTimer? = null
    private var requestCode: Int = -1
    private var receiverRegistered = false

    /** Held so [onDestroy] can unschedule it; it re-posts itself while ringing. */
    private var answerNudge: Runnable? = null

    private val finishReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getIntExtra(LessonCallReceiver.EXTRA_REQUEST_CODE, -1) == requestCode) {
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setUpWindow()
        setContentView(R.layout.kiu_lesson_call)
        applyWindowInsets()

        requestCode = intent.getIntExtra(LessonCallReceiver.EXTRA_REQUEST_CODE, -1)
        val key = intent.getStringExtra(LessonCallReceiver.EXTRA_KEY) ?: ""
        val title = intent.getStringExtra(LessonCallReceiver.EXTRA_TITLE) ?: ""
        val displayStart = intent.getStringExtra(LessonCallReceiver.EXTRA_DISPLAY_START) ?: ""
        val meetingUrl = intent.getStringExtra(LessonCallReceiver.EXTRA_MEETING_URL)

        // Answer tapped on the notification instead of this screen. Activities may start
        // activities, so opening the link here is what sidesteps the trampoline block.
        if (intent.getBooleanExtra(LessonCallReceiver.EXTRA_AUTO_ANSWER, false)) {
            answer(key, title, displayStart, meetingUrl)
            return
        }

        val data = HomeWidgetPlugin.getData(this)
        val ringSeconds = data.getString("callRingSeconds", "60")?.toIntOrNull() ?: 60
        val answerLabel = data.getString("callAnswerLabel", null) ?: "Join"
        val declineLabel = data.getString("callDeclineLabel", null) ?: "Dismiss"
        findViewById<TextView>(R.id.call_incoming_label).text =
            data.getString("callIncomingLabel", null) ?: "Lesson starting"
        findViewById<TextView>(R.id.call_answer_label).text = answerLabel
        findViewById<TextView>(R.id.call_decline_label).text = declineLabel
        // Lesson name, and its start already converted to the user's selected time zone by Dart.
        findViewById<TextView>(R.id.call_title).text = title
        findViewById<TextView>(R.id.call_start).text = displayStart
        findViewById<TextView>(R.id.call_avatar).text = initialOf(title)

        findViewById<ImageButton>(R.id.call_answer).apply {
            contentDescription = answerLabel
            addPressFeedback()
            setOnClickListener {
                dismissKeyguard()
                answer(key, title, displayStart, meetingUrl)
            }
        }
        findViewById<ImageButton>(R.id.call_decline).apply {
            contentDescription = declineLabel
            addPressFeedback()
            setOnClickListener {
                sendCallAction(LessonCallReceiver.ACTION_DECLINE, key, title, displayStart, meetingUrl)
                finish()
            }
        }

        startHaloPulse()
        startAnswerNudge()
        registerFinishReceiver()
        startRinging(data)
        startCountdown(ringSeconds, data.getString("callSecondsLabel", null) ?: "s")
    }

    private fun setUpWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        goEdgeToEdge()
    }

    /**
     * Draws the call behind the system bars so the gradient fills the screen.
     * Framework APIs rather than androidx: this activity extends plain
     * [Activity] and the module declares no androidx.core dependency of its
     * own, so WindowCompat would only work by accident of Flutter's transitive
     * graph.
     */
    private fun goEdgeToEdge() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
    }

    /**
     * Pads the content back in by the bar heights. Without this the brand chip
     * sits under the status bar and the buttons under the navigation bar.
     */
    private fun applyWindowInsets() {
        val root = findViewById<View>(R.id.call_root)
        val basePaddingTop = root.paddingTop
        val basePaddingBottom = root.paddingBottom
        root.setOnApplyWindowInsetsListener { view, insets ->
            val top: Int
            val bottom: Int
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bars = insets.getInsets(
                    android.view.WindowInsets.Type.systemBars() or
                        android.view.WindowInsets.Type.displayCutout(),
                )
                top = bars.top
                bottom = bars.bottom
            } else {
                @Suppress("DEPRECATION")
                top = insets.systemWindowInsetTop
                @Suppress("DEPRECATION")
                bottom = insets.systemWindowInsetBottom
            }
            view.setPadding(
                view.paddingLeft,
                basePaddingTop + top,
                view.paddingRight,
                basePaddingBottom + bottom,
            )
            insets
        }
        root.requestApplyInsets()
    }

    private fun dismissKeyguard() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager)
                .requestDismissKeyguard(this, null)
        }
    }

    /**
     * Silences the call, then opens the meeting link from this activity. Routing from here
     * rather than from [LessonCallReceiver] is deliberate: a receiver reached from a
     * notification action is a "trampoline" and Android 12+ refuses its activity starts.
     */
    private fun answer(key: String, title: String, displayStart: String, meetingUrl: String?) {
        sendCallAction(LessonCallReceiver.ACTION_STOP, key, title, displayStart, meetingUrl)
        LessonLinkRouter.open(this, meetingUrl)
        finish()
    }

    private fun sendCallAction(
        action: String,
        key: String,
        title: String,
        displayStart: String,
        meetingUrl: String?,
    ) {
        sendBroadcast(
            Intent(this, LessonCallReceiver::class.java).apply {
                this.action = action
                putExtra(LessonCallReceiver.EXTRA_REQUEST_CODE, requestCode)
                putExtra(LessonCallReceiver.EXTRA_KEY, key)
                putExtra(LessonCallReceiver.EXTRA_TITLE, title)
                putExtra(LessonCallReceiver.EXTRA_DISPLAY_START, displayStart)
                putExtra(LessonCallReceiver.EXTRA_MEETING_URL, meetingUrl)
            },
        )
    }

    private fun registerFinishReceiver() {
        val filter = IntentFilter(LessonCallReceiver.ACTION_FINISH_CALL_UI)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(finishReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(finishReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun startRinging(data: SharedPreferences) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audioManager.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            val ringtoneUri = data.getString("callRingtoneUri", "")?.takeIf { it.isNotBlank() }
                ?.let(Uri::parse)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            runCatching {
                mediaPlayer = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(this@LessonCallActivity, ringtoneUri)
                    isLooping = true
                    prepare()
                    start()
                }
            }
        }

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 800, 600)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    /** First letter of the lesson name, so the avatar reads as a caller rather than a blank disc. */
    private fun initialOf(title: String): String =
        title.trim().firstOrNull { it.isLetterOrDigit() }?.uppercase() ?: "?"

    /**
     * Slow breathing halo behind the avatar - the only motion on the screen.
     *
     * Two rings, started a beat apart so they expand out of phase; in step they
     * read as one thick ring rather than a ripple.
     */
    private fun startHaloPulse() {
        pulse(findViewById(R.id.call_halo), 1.12f, 0.45f, 1100L)
        findViewById<View>(R.id.call_halo_outer)?.let { outer ->
            outer.postDelayed({
                if (!isFinishing && !isDestroyed) pulse(outer, 1.06f, 0.25f, 1400L)
            }, 550L)
        }
    }

    /**
     * Idle bob on the answer button, the way a phone dialer nudges the action
     * it wants. Only answer moves: animating both would make the screen busy
     * and stop the motion from pointing anywhere.
     */
    private fun startAnswerNudge() {
        val answer = findViewById<View>(R.id.call_answer) ?: return
        // translationY is in pixels, not dp - convert, or the bob is invisible
        // on a low-density screen and oversized on a high-density one.
        val lift = 14f * resources.displayMetrics.density
        val nudge = object : Runnable {
            override fun run() {
                if (isFinishing || isDestroyed) return
                answer.animate()
                    .translationY(-lift)
                    .setDuration(320L)
                    .setInterpolator(DecelerateInterpolator())
                    .withEndAction {
                        answer.animate()
                            .translationY(0f)
                            .setDuration(420L)
                            .setInterpolator(OvershootInterpolator(2.5f))
                            .start()
                    }
                    .start()
                // Long gap between bobs: a continuous bounce reads as a
                // loading spinner rather than an invitation to tap.
                answer.postDelayed(this, 2200L)
            }
        }
        answerNudge = nudge
        answer.postDelayed(nudge, 900L)
    }

    /** Shrinks a button while held, so a press registers before it resolves. */
    private fun View.addPressFeedback() {
        setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> view.animate()
                    .scaleX(0.9f).scaleY(0.9f).setDuration(90L).start()
                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL,
                -> view.animate()
                    .scaleX(1f).scaleY(1f).setDuration(140L)
                    .setInterpolator(OvershootInterpolator()).start()
            }
            // Never consume: the click listener still has to fire, and
            // returning true here would swallow it.
            false
        }
    }

    private fun pulse(view: View, scale: Float, dimTo: Float, duration: Long) {
        view.animate()
            .scaleX(scale)
            .scaleY(scale)
            .alpha(dimTo)
            .setDuration(duration)
            .withEndAction(object : Runnable {
                private var expanded = true

                override fun run() {
                    expanded = !expanded
                    view.animate()
                        .scaleX(if (expanded) scale else 1f)
                        .scaleY(if (expanded) scale else 1f)
                        .alpha(if (expanded) dimTo else 1f)
                        .setDuration(duration)
                        .withEndAction(this)
                        .start()
                }
            })
            .start()
    }

    private fun startCountdown(ringSeconds: Int, secondsLabel: String) {
        val countdownView = findViewById<TextView>(R.id.call_countdown)
        countDownTimer = object : CountDownTimer(ringSeconds * 1000L, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                // Unit suffix: a bare digit next to the start time read as part
                // of it rather than as a countdown.
                countdownView.text = "${millisUntilFinished / 1000L + 1} $secondsLabel"
            }

            override fun onFinish() {
                finish()
            }
        }.also { it.start() }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Each halo pulse re-arms itself from its own end action, and the answer nudge
        // re-posts itself; drop all of them or they keep the finished activity's views
        // alive.
        findViewById<View>(R.id.call_halo)?.animate()?.withEndAction(null)?.cancel()
        findViewById<View>(R.id.call_halo_outer)?.animate()?.withEndAction(null)?.cancel()
        findViewById<View>(R.id.call_answer)?.apply {
            answerNudge?.let { removeCallbacks(it) }
            animate().withEndAction(null).cancel()
        }
        answerNudge = null
        findViewById<View>(R.id.call_decline)?.animate()?.cancel()
        countDownTimer?.cancel()
        countDownTimer = null
        releasePlayer()
        vibrator?.cancel()
        vibrator = null
        if (receiverRegistered) {
            unregisterReceiver(finishReceiver)
            receiverRegistered = false
        }
    }

    private fun releasePlayer() {
        mediaPlayer?.let { player ->
            runCatching { player.stop() }
            player.release()
        }
        mediaPlayer = null
    }
}
