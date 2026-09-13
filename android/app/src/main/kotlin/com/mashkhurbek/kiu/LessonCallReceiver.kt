package com.mashkhurbek.kiu

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import es.antonborri.home_widget.HomeWidgetPlugin

/** Rings, answers, declines, and times out a single lesson-call occurrence. */
class LessonCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val requestCode = intent.getIntExtra(EXTRA_REQUEST_CODE, -1)
        val key = intent.getStringExtra(EXTRA_KEY)
        if (requestCode == -1 || key.isNullOrBlank()) return
        when (intent.action) {
            ACTION_RING -> ring(
                context = context,
                requestCode = requestCode,
                key = key,
                title = intent.getStringExtra(EXTRA_TITLE) ?: "",
                displayStart = intent.getStringExtra(EXTRA_DISPLAY_START) ?: "",
                meetingUrl = intent.getStringExtra(EXTRA_MEETING_URL),
            )
            // No ACTION_ANSWER here on purpose: Android 12+ blocks a receiver reached from a
            // notification action from starting an activity ("notification trampoline"), so the
            // Answer action is a getActivity PendingIntent straight to LessonCallActivity, which
            // opens the link itself. This receiver only ever stops things.
            ACTION_STOP, ACTION_DECLINE, ACTION_TIMEOUT -> stop(context, requestCode, key)
        }
    }

    /** Cancels the notification and the pending timeout alarm, then tells a visible call screen to close. */
    private fun stop(context: Context, requestCode: Int, key: String) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(requestCode)
        LessonCallAlarms.cancel(context, requestCode, key)
        context.sendBroadcast(
            Intent(ACTION_FINISH_CALL_UI).apply {
                setPackage(context.packageName)
                putExtra(EXTRA_REQUEST_CODE, requestCode)
            },
        )
    }

    private fun ring(
        context: Context,
        requestCode: Int,
        key: String,
        title: String,
        displayStart: String,
        meetingUrl: String?,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val ringSeconds = prefs.getString("callRingSeconds", "60")?.toIntOrNull() ?: 60
        val ringtoneUri = prefs.getString("callRingtoneUri", "")?.takeIf { it.isNotBlank() }
            ?.let(Uri::parse)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val incomingLabel = prefs.getString("callIncomingLabel", null) ?: "Lesson starting"
        val answerLabel = prefs.getString("callAnswerLabel", null) ?: "Join"
        val declineLabel = prefs.getString("callDeclineLabel", null) ?: "Dismiss"

        val fullScreenIntent = Intent(context, LessonCallActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
            putExtra(EXTRA_REQUEST_CODE, requestCode)
            putExtra(EXTRA_KEY, key)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_DISPLAY_START, displayStart)
            putExtra(EXTRA_MEETING_URL, meetingUrl)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // When the call screen comes up it already shows the lesson and both buttons, so a
        // heads-up banner on top of it is pure duplication: post silently in that case and let
        // the notification sit in the shade as the way back. The loud heads-up only matters
        // when no call screen appears, because then it is the entire UI.
        //
        // This must be decided up front rather than from startActivity's result: a blocked
        // background activity start does NOT throw, it is silently dropped, so a
        // runCatching around it reports success either way and would leave the fallback mute.
        val willShowCallScreen = canDrawOverlays(context) || screenIsOff(context)
        val channelId = ensureChannel(context, ringtoneUri, silent = willShowCallScreen)
        runCatching { context.startActivity(fullScreenIntent) }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        @Suppress("DEPRECATION")
        val notification = builder
            .setContentTitle(incomingLabel)
            .setContentText(title)
            .setSmallIcon(R.drawable.ic_notification)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(if (willShowCallScreen) Notification.PRIORITY_LOW else Notification.PRIORITY_HIGH)
            .setOngoing(true)
            .setAutoCancel(false)
            // Re-asserting the full-screen intent while the screen is already up would make
            // Android relaunch it; only arm it when it is still needed.
            .apply { if (!willShowCallScreen) setFullScreenIntent(fullScreenPendingIntent, true) }
            .setContentIntent(fullScreenPendingIntent)
            .addAction(
                R.drawable.ic_lesson_call_decline,
                declineLabel,
                actionPendingIntent(context, requestCode, key, title, displayStart, meetingUrl, ACTION_DECLINE),
            )
            .addAction(
                R.drawable.ic_lesson_call_answer,
                answerLabel,
                PendingIntent.getActivity(
                    context,
                    requestCode + 1,
                    Intent(fullScreenIntent).apply { putExtra(EXTRA_AUTO_ANSWER, true) },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            .build()

        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(requestCode, notification)

        val timeoutPendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, LessonCallReceiver::class.java).apply {
                action = ACTION_TIMEOUT
                data = Uri.parse("kiu://lesson-call-timeout/${Uri.encode(key)}")
                putExtra(EXTRA_REQUEST_CODE, requestCode)
                putExtra(EXTRA_KEY, key)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fireAt = System.currentTimeMillis() + ringSeconds * 1000L
        runCatching {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, timeoutPendingIntent)
        }.getOrElse {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, timeoutPendingIntent)
        }
    }

    private fun actionPendingIntent(
        context: Context,
        requestCode: Int,
        key: String,
        title: String,
        displayStart: String,
        meetingUrl: String?,
        action: String,
    ): PendingIntent {
        val intent = Intent(context, LessonCallReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("kiu://lesson-call-action/${Uri.encode(action)}/${Uri.encode(key)}")
            putExtra(EXTRA_REQUEST_CODE, requestCode)
            putExtra(EXTRA_KEY, key)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_DISPLAY_START, displayStart)
            putExtra(EXTRA_MEETING_URL, meetingUrl)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Holding this is what exempts the direct `startActivity` from background-launch blocking. */
    private fun canDrawOverlays(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /**
     * Locked or screen-off, in which case Android honours the full-screen intent and brings the
     * call screen up by itself, with no background-launch restriction involved.
     */
    private fun screenIsOff(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return !power.isInteractive || keyguard.isKeyguardLocked
    }

    /**
     * Creates (or reuses) the ring notification channel. Android caches a channel's sound once
     * created, so the ringtone's hash rides in the channel id - the same trick
     * `reminderNotificationChannelId` in `lib/services/notification_service.dart` uses - so
     * changing the ringtone actually takes effect on the next ring.
     */
    private fun ensureChannel(context: Context, ringtoneUri: Uri, silent: Boolean): String {
        // Two channels: the loud one is the standalone fallback, the silent one only backs the
        // already-visible call screen (which does its own ringing and vibrating).
        val id = if (silent) {
            "kiu_lesson_call_quiet"
        } else {
            "kiu_lesson_call_${channelSuffix(ringtoneUri.toString())}"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(id) == null) {
                val importance = if (silent) {
                    NotificationManager.IMPORTANCE_LOW
                } else {
                    NotificationManager.IMPORTANCE_HIGH
                }
                val channel = NotificationChannel(id, "Lesson calls", importance).apply {
                    description = "Incoming lesson-call alerts"
                    enableVibration(!silent)
                    setBypassDnd(false)
                    if (silent) {
                        setSound(null, null)
                    } else {
                        setSound(
                            ringtoneUri,
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build(),
                        )
                    }
                }
                manager.createNotificationChannel(channel)
            }
        }
        return id
    }

    companion object {
        const val ACTION_RING = "com.mashkhurbek.kiu.action.LESSON_CALL_RING"
        const val ACTION_STOP = "com.mashkhurbek.kiu.action.LESSON_CALL_STOP"
        const val ACTION_DECLINE = "com.mashkhurbek.kiu.action.LESSON_CALL_DECLINE"
        const val ACTION_TIMEOUT = "com.mashkhurbek.kiu.action.LESSON_CALL_TIMEOUT"
        const val ACTION_FINISH_CALL_UI = "com.mashkhurbek.kiu.action.LESSON_CALL_FINISH_UI"
        const val EXTRA_KEY = "key"
        const val EXTRA_TITLE = "title"
        const val EXTRA_DISPLAY_START = "displayStart"
        const val EXTRA_MEETING_URL = "meetingUrl"
        const val EXTRA_REQUEST_CODE = "requestCode"
        const val EXTRA_AUTO_ANSWER = "autoAnswer"

        // Same idea as reminderNotificationChannelId in notification_service.dart, but this
        // value never crosses the Dart boundary, so it only has to be stable and to change
        // when the ringtone does - it is deliberately not bit-identical to the Dart hash.
        private fun channelSuffix(value: String): String {
            var hash = 0x811c9dc5L.toInt()
            for (ch in value) {
                hash = hash xor ch.code
                hash *= 0x01000193
            }
            return (hash and 0x7fffffff).toString(36)
        }
    }
}
