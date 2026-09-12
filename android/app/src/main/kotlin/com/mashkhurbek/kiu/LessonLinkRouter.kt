package com.mashkhurbek.kiu

import android.content.Context
import android.content.Intent
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Routes a lesson/meeting link the same way everywhere it can be opened from: widget row taps,
 * the widget's Answer action, and the lesson-call notification/activity Answer button.
 */
object LessonLinkRouter {
    fun open(context: Context, link: String?) {
        val uri = link?.takeIf { it.isNotBlank() }?.let(Uri::parse)
        val target = if (uri != null && KiuLessonWidgetProvider.isValidHttps(uri)) {
            if (uri.host.equals(KiuLessonWidgetProvider.TRUSTED_HOST, ignoreCase = true)) {
                Intent(context, MainActivity::class.java).apply {
                    action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                    data = uri
                }
            } else {
                Intent(Intent.ACTION_VIEW, uri)
            }
        } else {
            // Blank, unparseable, or non-HTTPS link: fall back to opening the app itself.
            Intent(context, MainActivity::class.java)
        }
        target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(target) }
    }
}
