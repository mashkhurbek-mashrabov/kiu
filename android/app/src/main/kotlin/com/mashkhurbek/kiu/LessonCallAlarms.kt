package com.mashkhurbek.kiu

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/**
 * (Re)arms one alarm per future call-enabled lesson occurrence, read from the "calls" entry the
 * Dart side already publishes into `home_widget` prefs. Works identically from the widget's
 * `onUpdate`, the boot receiver, and the WorkManager background isolate's widget refresh, since
 * none of them share a method channel with `MainActivity`.
 */
object LessonCallAlarms {
    private const val PREFS_NAME = "kiu_lesson_calls"
    private const val KEY_ARMED = "armed"
    private const val RING_URI_PREFIX = "kiu://lesson-call/"

    fun rearm(context: Context) {
        val alarmManager = context.alarmManager()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Each entry is "requestCode|key" - the key is needed to rebuild the exact PendingIntent
        // to cancel, since every alarm carries a distinct data Uri.
        prefs.getStringSet(KEY_ARMED, emptySet()).orEmpty().forEach { entry ->
            val requestCode = entry.substringBefore('|').toIntOrNull() ?: return@forEach
            val key = entry.substringAfter('|', "")
            cancelRing(context, alarmManager, requestCode, key)
        }

        val calls = runCatching {
            JSONArray(HomeWidgetPlugin.getData(context).getString("calls", "[]") ?: "[]")
        }.getOrDefault(JSONArray())
        val now = System.currentTimeMillis()
        val armed = mutableSetOf<String>()
        for (index in 0 until calls.length()) {
            val call = calls.optJSONObject(index) ?: continue
            val start = call.optLong("start", -1L)
            val requestCode = call.optInt("requestCode", -1)
            val key = call.optString("key")
            if (start <= now || requestCode == -1 || key.isBlank()) continue
            armRing(
                context = context,
                alarmManager = alarmManager,
                requestCode = requestCode,
                key = key,
                start = start,
                title = call.optString("title"),
                displayStart = call.optString("displayStart"),
                // optString maps a JSON null to the literal "null", not to "" - guard explicitly.
                meetingUrl = if (call.isNull("meetingUrl")) {
                    null
                } else {
                    call.optString("meetingUrl").takeIf { it.isNotBlank() }
                },
            )
            armed += "$requestCode|$key"
        }
        prefs.edit().putStringSet(KEY_ARMED, armed).apply()
    }

    /** Cancels the ring-timeout alarm [LessonCallReceiver] scheduled for one call occurrence. */
    fun cancel(context: Context, requestCode: Int, key: String) {
        val alarmManager = context.alarmManager()
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            timeoutIntent(context, key),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun ringIntent(context: Context, key: String) =
        Intent(context, LessonCallReceiver::class.java).apply {
            action = LessonCallReceiver.ACTION_RING
            data = Uri.parse("$RING_URI_PREFIX${Uri.encode(key)}")
        }

    private fun timeoutIntent(context: Context, key: String) =
        Intent(context, LessonCallReceiver::class.java).apply {
            action = LessonCallReceiver.ACTION_TIMEOUT
            data = Uri.parse("kiu://lesson-call-timeout/${Uri.encode(key)}")
        }

    private fun armRing(
        context: Context,
        alarmManager: AlarmManager,
        requestCode: Int,
        key: String,
        start: Long,
        title: String,
        displayStart: String,
        meetingUrl: String?,
    ) {
        val intent = ringIntent(context, key).apply {
            putExtra(LessonCallReceiver.EXTRA_REQUEST_CODE, requestCode)
            putExtra(LessonCallReceiver.EXTRA_KEY, key)
            putExtra(LessonCallReceiver.EXTRA_TITLE, title)
            putExtra(LessonCallReceiver.EXTRA_DISPLAY_START, displayStart)
            putExtra(LessonCallReceiver.EXTRA_MEETING_URL, meetingUrl)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val canScheduleExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        if (canScheduleExact) {
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(start, pendingIntent), pendingIntent)
            return
        }
        runCatching {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, start, pendingIntent)
        }.getOrElse {
            // ponytail: inexact tier can ring late; the existing exact-alarm prompt is the upgrade path.
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, start, pendingIntent)
        }
    }

    private fun cancelRing(context: Context, alarmManager: AlarmManager, requestCode: Int, key: String) {
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            ringIntent(context, key),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun Context.alarmManager() = getSystemService(Context.ALARM_SERVICE) as AlarmManager
}
