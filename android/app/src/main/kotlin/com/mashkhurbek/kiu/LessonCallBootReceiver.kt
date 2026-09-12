package com.mashkhurbek.kiu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** AlarmManager alarms don't survive a reboot or app update, so re-arm lesson calls after both. */
class LessonCallBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            LessonCallAlarms.rearm(context)
        }
    }
}
