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
import android.view.View
import android.view.WindowManager
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
            setOnClickListener {
                dismissKeyguard()
                answer(key, title, displayStart, meetingUrl)
            }
        }
        findViewById<ImageButton>(R.id.call_decline).apply {
            contentDescription = declineLabel
            setOnClickListener {
                sendCallAction(LessonCallReceiver.ACTION_DECLINE, key, title, displayStart, meetingUrl)
                finish()
            }
        }

        startHaloPulse()
        registerFinishReceiver()
        startRinging(data)
        startCountdown(ringSeconds)
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

    /** Slow breathing halo behind the avatar - the only motion on the screen. */
    private fun startHaloPulse() {
        val halo = findViewById<View>(R.id.call_halo)
        halo.animate()
            .scaleX(1.12f)
            .scaleY(1.12f)
            .alpha(0.45f)
            .setDuration(1100L)
            .withEndAction(object : Runnable {
                private var expanded = true

                override fun run() {
                    expanded = !expanded
                    halo.animate()
                        .scaleX(if (expanded) 1.12f else 1f)
                        .scaleY(if (expanded) 1.12f else 1f)
                        .alpha(if (expanded) 0.45f else 1f)
                        .setDuration(1100L)
                        .withEndAction(this)
                        .start()
                }
            })
            .start()
    }

    private fun startCountdown(ringSeconds: Int) {
        val countdownView = findViewById<TextView>(R.id.call_countdown)
        countDownTimer = object : CountDownTimer(ringSeconds * 1000L, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                countdownView.text = (millisUntilFinished / 1000L + 1).toString()
            }

            override fun onFinish() {
                finish()
            }
        }.also { it.start() }
    }

    override fun onDestroy() {
        super.onDestroy()
        // The halo pulse re-arms itself from its own end action; drop it or it keeps the
        // finished activity's view alive.
        findViewById<View>(R.id.call_halo)?.animate()?.withEndAction(null)?.cancel()
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
