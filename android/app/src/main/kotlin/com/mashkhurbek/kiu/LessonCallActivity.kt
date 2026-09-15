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

    /** Millis left on the ring window, so a re-ring keeps the deadline rather than extending it. */
    private var remainingMillis: Long = 0

    /** Set once the user answers or declines, so leaving afterwards does not re-ring. */
    private var resolved = false

    /** The call being shown, kept so [onUserLeaveHint] can hand it back to the receiver. */
    private var callKey: String = ""
    private var callTitle: String = ""
    private var callDisplayStart: String = ""
    private var callMeetingUrl: String? = null
    private var receiverRegistered = false

    /** Held so [onDestroy] can unschedule it; it re-posts itself while ringing. */
    private var answerNudge: Runnable? = null

    /** Taps on decline so far. It only declines on [DECLINE_TAPS_REQUIRED]. */
    private var declineTaps = 0

    private val random = java.util.Random()

    private val finishReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getIntExtra(LessonCallReceiver.EXTRA_REQUEST_CODE, -1) == requestCode) {
                // Something already stopped this call, so leaving now must not re-ring it.
                resolved = true
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setUpWindow()
        setContentView(R.layout.kiu_lesson_call)
        applyWindowInsets()
        hideAvatarIfCramped()

        requestCode = intent.getIntExtra(LessonCallReceiver.EXTRA_REQUEST_CODE, -1)
        val key = intent.getStringExtra(LessonCallReceiver.EXTRA_KEY) ?: ""
        val title = intent.getStringExtra(LessonCallReceiver.EXTRA_TITLE) ?: ""
        val displayStart = intent.getStringExtra(LessonCallReceiver.EXTRA_DISPLAY_START) ?: ""
        val meetingUrl = intent.getStringExtra(LessonCallReceiver.EXTRA_MEETING_URL)
        callKey = key
        callTitle = title
        callDisplayStart = displayStart
        callMeetingUrl = meetingUrl

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
                resolved = true
                dismissKeyguard()
                answer(key, title, displayStart, meetingUrl)
            }
        }
        findViewById<ImageButton>(R.id.call_decline).apply {
            contentDescription = declineLabel
            addPressFeedback()
            setOnClickListener {
                declineTaps++
                if (declineTaps < DECLINE_TAPS_REQUIRED) {
                    dodge()
                    return@setOnClickListener
                }
                resolved = true
                sendCallAction(LessonCallReceiver.ACTION_DECLINE, key, title, displayStart, meetingUrl)
                finish()
            }
        }

        startHaloPulse()
        startAnswerNudge()
        forwardDodgedTaps()
        registerFinishReceiver()
        startRinging(data)
        startCountdown(ringSeconds, data.getString("callSecondsLabel", null) ?: "s")
    }

    /**
     * Re-rings the call when the user leaves the screen with it still live.
     *
     * Home destroys this activity outright -- `excludeFromRecents` plus an empty
     * `taskAffinity` mean it is not kept around to come back to -- and the notification
     * posted beside a visible call screen is deliberately silent, so the call would survive
     * only as a mute status-bar icon for a lesson that is starting right now.
     *
     * [onUserLeaveHint] rather than [onPause] or [onStop]: it fires only for a deliberate
     * departure (Home, Recents), not when the screen is covered by a dialog, the keyguard, or
     * the activity finishing itself after Answer or Decline.
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (resolved || isFinishing || requestCode == -1) return
        sendBroadcast(
            Intent(this, LessonCallReceiver::class.java).apply {
                action = LessonCallReceiver.ACTION_RERING
                setPackage(packageName)
                putExtra(LessonCallReceiver.EXTRA_REQUEST_CODE, requestCode)
                putExtra(LessonCallReceiver.EXTRA_KEY, callKey)
                putExtra(LessonCallReceiver.EXTRA_TITLE, callTitle)
                putExtra(LessonCallReceiver.EXTRA_DISPLAY_START, callDisplayStart)
                putExtra(LessonCallReceiver.EXTRA_MEETING_URL, callMeetingUrl)
                putExtra(LessonCallReceiver.EXTRA_REMAINING_MILLIS, remainingMillis)
            },
        )
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

    /**
     * Drops the avatar and its halo when the screen is too short to seat the text below it.
     *
     * The identity block is weighted, so a LinearLayout hands it whatever height is left over
     * whether or not the content fits; the children then overflow their box rather than
     * shrinking. On a 533dp-tall screen that painted the countdown chip over a half-clipped
     * start-time pill. The avatar is the only decorative element here, so it is what yields --
     * the lesson name, its start time and the buttons all carry information or actions.
     *
     * Measured rather than gated on a dp qualifier: the title wraps to one or two lines
     * depending on its length, so the same device fits the avatar for one lesson and not for
     * another. values-h700dp still picks the roomy metrics; this only removes what cannot fit
     * after that choice is made.
     */
    private fun hideAvatarIfCramped() {
        val root = findViewById<View>(R.id.call_root)
        root.viewTreeObserver.addOnPreDrawListener(
            object : android.view.ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    root.viewTreeObserver.removeOnPreDrawListener(this)
                    val avatar = findViewById<View>(R.id.call_avatar_block)
                    val start = findViewById<View>(R.id.call_start)
                    val countdown = findViewById<View>(R.id.call_countdown)
                    if (avatar.visibility != View.VISIBLE) return true
                    // Overlap is the symptom that matters: the start-time pill running into
                    // the countdown means the weighted block overflowed its box.
                    //
                    // Screen coordinates, not View.y: these two live in different parents
                    // (the start pill inside the identity block, the countdown directly
                    // under the root), so their y values are not comparable.
                    val startPos = IntArray(2).also(start::getLocationOnScreen)
                    val countdownPos = IntArray(2).also(countdown::getLocationOnScreen)
                    // A gap, not merely "no overlap": the identity block clamps its content
                    // to its own bottom edge, so a cramped screen ends up with the start
                    // pill exactly touching the countdown, which reads as the two colliding.
                    val gap = countdownPos[1] - (startPos[1] + start.height)
                    if (gap < MIN_IDENTITY_GAP_DP * resources.displayMetrics.density) {
                        avatar.visibility = View.GONE
                    }
                    return true
                }
            },
        )
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

    /**
     * Throws decline to a random point on the screen instead of hanging up, so
     * a lesson cannot be dismissed by one reflex tap on a screen that woke the
     * user up. It only declines on the third tap, once the user has chased it.
     *
     * Both axes move and the target is re-rolled every tap: a fixed slide
     * along one line is easy to follow with the thumb already travelling, and
     * defeats the point.
     *
     * Two areas are excluded. The answer button plus a finger-sized margin,
     * because a decline button that lands on Join turns a miss into a joined
     * lesson; and a `call_dodge_margin` border inside the visible display
     * frame, so the whole circle stays on screen, clear of the system bars
     * and tappable. The jump is also bounded in length by a minimum and a
     * maximum travel. translationX/Y leave layout alone,
     * so nothing reflows - the root and the button's row already carry
     * clipChildren="false" for the answer nudge, which is what lets the
     * travelled button draw outside its row instead of being sheared.
     */
    private fun dodge() {
        val decline = findViewById<View>(R.id.call_decline) ?: return
        val answer = findViewById<View>(R.id.call_answer) ?: return
        val margin = resources.getDimension(R.dimen.call_dodge_margin)
        val size = decline.width.toFloat()
        if (size <= 0f) return

        // The caption cannot follow - it would have to dodge the answer label
        // too - and a "Dismiss" stranded under an empty column reads as a bug.
        // The button keeps its contentDescription, so the action stays
        // announced for screen readers after the text goes.
        findViewById<View>(R.id.call_decline_label)?.animate()
            ?.alpha(0f)?.setDuration(160L)?.start()

        // Where the button actually sits on screen. left/top are relative to
        // its own parent column, not to the root, so clamping the roll against
        // the root's box using them mixes two coordinate spaces and throws the
        // button off screen. Screen coordinates are the only frame both the
        // button and the display share.
        val spot = IntArray(2).also(decline::getLocationOnScreen)
        val answerSpot = IntArray(2).also(answer::getLocationOnScreen)

        // The area actually free to be landed on, not the raw display:
        // displayMetrics counts the pixels behind the status and navigation
        // bars, and this activity draws edge to edge, so a roll clamped to it
        // can put the button under a system bar where it cannot be tapped.
        val visible = android.graphics.Rect().also(decline.rootView::getWindowVisibleDisplayFrame)

        // getLocationOnScreen already includes the current translation, so
        // subtract it to get the laid-out origin - translationX/Y are measured
        // from there, not from wherever the last dodge left the button.
        val homeX = spot[0] - decline.translationX
        val homeY = spot[1] - decline.translationY
        val minX = visible.left + margin - homeX
        val maxX = visible.right - margin - size - homeX
        val minY = visible.top + margin - homeY
        val maxY = visible.bottom - margin - size - homeY
        if (maxX < minX || maxY < minY) return

        // Keep clear of answer by a finger's width, measured from the laid-out
        // answer box - it is only ever translated vertically by the nudge.
        val keepOut = size * 0.9f
        // Where it is right now, to measure the jump against.
        val fromX = decline.translationX
        val fromY = decline.translationY
        // A dodge must actually go somewhere: landing a few pixels away reads
        // as a twitch and leaves the button under the thumb already coming
        // down on it.
        //
        // Measured against the SHORTER screen edge, not the width. The button
        // can never travel further than the screen's own span minus its size
        // and margins, so a floor keyed to the width would, in landscape,
        // demand a jump the layout cannot deliver and relax away to nothing.
        // The short edge is the one dimension guaranteed to fit.
        val minTravel = 0.70f * minOf(visible.width(), visible.height())
        // Cap on the jump so the button does not always slam corner to corner,
        // which becomes predictable in its own way.
        val maxTravel = 0.80f * visible.height()
        var x = 0f
        var y = 0f
        // Rejection sampling: cheap, and unlike solving for the free region it
        // stays correct whatever the screen shape. The budget is bounded so a
        // pathological layout cannot spin here.
        repeat(DODGE_SAMPLES) { attempt ->
            x = minX + random.nextFloat() * (maxX - minX)
            y = minY + random.nextFloat() * (maxY - minY)
            val overlapsAnswer =
                homeX + x < answerSpot[0] + answer.width + keepOut &&
                    homeX + x + size > answerSpot[0] - keepOut &&
                    homeY + y < answerSpot[1] + answer.height + keepOut &&
                    homeY + y + size > answerSpot[1] - keepOut
            // Hold the full distance floor for most of the budget and only
            // concede over the last stretch. On a cramped screen the free area
            // may be too tight to ever clear it, and an unrelaxed floor would
            // exhaust the budget and fall through to the final roll with no
            // distance check at all - the opposite of what it is for. Relaxing
            // evenly instead would give ground on ordinary rolls that only
            // needed another try, since a floor this close to the screen's own
            // span is unreachable from some start points.
            //
            // The ceiling never relaxes: it only rules candidates out, so it
            // can never be the reason sampling fails.
            val slack = ((attempt - DODGE_STRICT_SAMPLES).toFloat() /
                (DODGE_SAMPLES - DODGE_STRICT_SAMPLES)).coerceAtLeast(0f)
            val required = minTravel * (1f - slack)
            val dx = x - fromX
            val dy = y - fromY
            val travelled = dx * dx + dy * dy
            val farEnough = travelled >= required * required
            val notTooFar = travelled <= maxTravel * maxTravel
            if (!overlapsAnswer && farEnough && notTooFar) {
                dodgeTo(decline, x, y)
                return
            }
        }
        dodgeTo(decline, x, y)
    }

    private fun dodgeTo(decline: View, x: Float, y: Float) {
        decline.animate()
            .translationX(x)
            .translationY(y)
            .setDuration(260L)
            // Decelerate, NOT overshoot: an overshoot interpolator sails past
            // its target before settling, so a roll that legitimately lands on
            // the edge margin still throws the circle off screen mid-flight.
            // The clamp bounds the destination; only a non-overshooting curve
            // bounds the path taken to it.
            .setInterpolator(DecelerateInterpolator())
            .start()
    }

    /**
     * Routes taps that land on the dodged button back to it.
     *
     * Touch dispatch uses a view's *layout* bounds, which translation does not
     * change: clipChildren="false" only lets the button draw outside its row,
     * so once it has dodged, the circle the user can see is dead and its
     * original slot is still live. Without this the screen looks interactive
     * and is not.
     *
     * Installed on the root because the button leaves its own row entirely, so
     * no closer ancestor still contains it. Returns false for everything else,
     * leaving answer and the rest of the screen untouched.
     */
    private fun forwardDodgedTaps() {
        val root = findViewById<View>(R.id.call_root) ?: return
        val decline = findViewById<View>(R.id.call_decline) ?: return
        root.setOnTouchListener { _, event ->
            if (decline.translationX == 0f && decline.translationY == 0f) {
                return@setOnTouchListener false
            }
            val spot = IntArray(2).also(decline::getLocationOnScreen)
            val hit = event.rawX >= spot[0] && event.rawX <= spot[0] + decline.width &&
                event.rawY >= spot[1] && event.rawY <= spot[1] + decline.height
            if (!hit) return@setOnTouchListener false
            if (event.actionMasked == MotionEvent.ACTION_UP) decline.performClick()
            true
        }
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
        remainingMillis = ringSeconds * 1000L
        countDownTimer = object : CountDownTimer(ringSeconds * 1000L, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                // Tracked so a re-ring can keep this deadline instead of restarting it.
                remainingMillis = millisUntilFinished
                // Unit suffix: a bare digit next to the start time read as part
                // of it rather than as a countdown.
                countdownView.text = "${millisUntilFinished / 1000L + 1} $secondsLabel"
            }

            override fun onFinish() {
                // The timeout alarm cancels the notification itself; re-ringing on the way
                // out would resurrect a call that just expired.
                resolved = true
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
        findViewById<View>(R.id.call_decline_label)?.animate()?.cancel()
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

    private companion object {
        /**
         * Clearance the start-time pill needs below it before the avatar is worth keeping.
         *
         * Not zero: the weighted identity block clamps its content to its own bottom edge, so
         * a cramped screen leaves the pill exactly touching the countdown chip, which reads as
         * the two colliding even though neither technically overflows.
         */
        const val MIN_IDENTITY_GAP_DP = 12

        /** Taps needed to actually decline; the first two only move the button. */
        const val DECLINE_TAPS_REQUIRED = 3

        /** Candidate positions tried per dodge before taking what is left. */
        const val DODGE_SAMPLES = 160

        /** How many of those hold the full distance floor before it concedes. */
        const val DODGE_STRICT_SAMPLES = 120
    }
}
