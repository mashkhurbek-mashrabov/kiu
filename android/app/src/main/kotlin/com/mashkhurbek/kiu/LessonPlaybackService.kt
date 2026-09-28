package com.mashkhurbek.kiu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.SystemClock

/**
 * Keeps a playing lesson video alive and controllable outside the app.
 *
 * Owns one framework [MediaSession]. That single session is what the
 * notification, the lockscreen, Bluetooth/car (AVRCP) media keys *and* the
 * system PiP menu all drive, so none of them need their own wiring. Framework
 * classes rather than androidx media, because the module declares no androidx
 * dependency of its own (same reason as [LessonCallActivity]).
 *
 * Runs as a `mediaPlayback` foreground service so the process -- and the
 * WebView playing the audio -- is not frozen when the app leaves the screen.
 * It stays in the foreground while *paused*: restarting a foreground service
 * from the background (a car's "play" arriving while the app is hidden) is
 * blocked on Android 12+. Only "Close", leaving the video page, or the
 * activity being destroyed ends it.
 */
class LessonPlaybackService : Service() {
    private var session: MediaSession? = null
    private var foreground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        session = MediaSession(this, "KIU lesson").apply {
            @Suppress("DEPRECATION")
            setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = send("play")
                override fun onPause() = send("pause")
                override fun onRewind() = send("rewind")
                override fun onFastForward() = send("forward")
                // Car head units usually only have next/previous buttons; a
                // lesson has no "next track", so they seek instead.
                override fun onSkipToPrevious() = send("rewind")
                override fun onSkipToNext() = send("forward")
                override fun onStop() = close()
                override fun onCustomAction(action: String, extras: Bundle?) {
                    if (action == ACTION_CLOSE) close()
                }
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CLOSE -> {
                close()
                return START_NOT_STICKY
            }
            ACTION_PLAY -> send("play")
            ACTION_PAUSE -> send("pause")
            ACTION_REWIND -> send("rewind")
            ACTION_FORWARD -> send("forward")
        }
        render()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        session?.release()
        session = null
        super.onDestroy()
    }

    /** Stops the video, then everything native: the notification, the session, the service. */
    private fun close() {
        // Detached first: the pause below echoes back as a paused update, which
        // must not find (and re-post the notification of) a closing service.
        instance = null
        state = null
        send("pause")
        stopSelf()
    }

    /** Publishes [state] to the session and the notification; stops when there is none. */
    fun render() {
        val current = state
        val session = session
        if (current == null || session == null) {
            stopSelf()
            return
        }
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, current.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, "KIU")
                .putLong(MediaMetadata.METADATA_KEY_DURATION, current.durationMs)
                .build(),
        )
        // Position + speed + timestamp lets the system extrapolate the progress
        // bar, so Dart only reports state changes, never a per-second tick.
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_REWIND or
                        PlaybackState.ACTION_FAST_FORWARD or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_STOP,
                )
                // Android 13+ builds its media controls from the session, not the
                // notification's actions, so Close has to exist here too.
                .addCustomAction(
                    PlaybackState.CustomAction.Builder(
                        ACTION_CLOSE,
                        current.labels.close,
                        android.R.drawable.ic_menu_close_clear_cancel,
                    ).build(),
                )
                .setState(
                    if (current.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    current.positionMs,
                    current.speed,
                    SystemClock.elapsedRealtime(),
                )
                .build(),
        )
        val notification = buildNotification(current, session)
        if (!foreground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foreground = true
        } else {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(current: State, session: MediaSession): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Re-created every time on purpose: it is a no-op except that it
            // renames the channel when the app language changes.
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    current.labels.channelName,
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { setShowBadge(false) },
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val labels = current.labels
        // Content intent is an activity PendingIntent, and the actions target
        // this service, so nothing here is a notification trampoline.
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(current.title)
            .setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(false)
            .setOngoing(true)
            .addAction(action(android.R.drawable.ic_media_rew, labels.rewind, ACTION_REWIND))
            .addAction(
                if (current.playing) {
                    action(android.R.drawable.ic_media_pause, labels.pause, ACTION_PAUSE)
                } else {
                    action(android.R.drawable.ic_media_play, labels.play, ACTION_PLAY)
                },
            )
            .addAction(action(android.R.drawable.ic_media_ff, labels.forward, ACTION_FORWARD))
            .addAction(
                action(android.R.drawable.ic_menu_close_clear_cancel, labels.close, ACTION_CLOSE),
            )
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
            .build()
    }

    private fun action(icon: Int, label: String, action: String): Notification.Action =
        Notification.Action.Builder(
            Icon.createWithResource("android", icon),
            label,
            PendingIntent.getService(
                this,
                action.hashCode(),
                Intent(this, LessonPlaybackService::class.java).setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        ).build()

    data class Labels(
        val channelName: String,
        val play: String,
        val pause: String,
        val rewind: String,
        val forward: String,
        val close: String,
    )

    data class State(
        val playing: Boolean,
        val title: String,
        val positionMs: Long,
        val durationMs: Long,
        val speed: Float,
        val labels: Labels,
    )

    companion object {
        private const val CHANNEL_ID = "kiu_lesson_playback"
        private const val NOTIFICATION_ID = 7301
        private const val ACTION_PLAY = "com.mashkhurbek.kiu.action.MEDIA_PLAY"
        private const val ACTION_PAUSE = "com.mashkhurbek.kiu.action.MEDIA_PAUSE"
        private const val ACTION_REWIND = "com.mashkhurbek.kiu.action.MEDIA_REWIND"
        private const val ACTION_FORWARD = "com.mashkhurbek.kiu.action.MEDIA_FORWARD"
        private const val ACTION_CLOSE = "com.mashkhurbek.kiu.action.MEDIA_CLOSE"

        /** What the page last reported; null once playback is closed. Main thread only. */
        var state: State? = null

        /** Set by [MainActivity] while its engine is alive; forwards a control to Dart. */
        var commandSink: ((String) -> Unit)? = null

        /** The running service, so updates reach it without another (background-blocked) start. */
        var instance: LessonPlaybackService? = null
            private set

        private fun send(action: String) {
            commandSink?.invoke(action)
        }
    }
}
