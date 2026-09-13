package com.mashkhurbek.kiu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class KiuLessonWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val dark = widgetData.getString("widgetDark", "false") == "true"
        appWidgetIds.forEach { widgetId ->
            val serviceIntent = Intent(context, KiuLessonWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                // RemoteViews services are cached by Intent identity; include widget ID.
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            val views = RemoteViews(context.packageName, R.layout.kiu_lesson_widget).apply {
                setInt(R.id.widget_container, "setBackgroundResource", WidgetTheme.background(dark))
                setInt(R.id.widget_sync_icon, "setBackgroundResource", WidgetTheme.syncButton(dark))
                setTextColor(R.id.widget_title, WidgetTheme.brand(dark))
                // Subtitle is secondary now that it sits under the brand rather
                // than beside it; brand green on both made the header shout.
                setTextColor(R.id.widget_subtitle, WidgetTheme.muted(dark))
                setTextColor(R.id.widget_status, WidgetTheme.brand(dark))
                setTextColor(R.id.widget_last_sync, WidgetTheme.muted(dark))
                setTextColor(R.id.lesson_empty, WidgetTheme.muted(dark))
                setRemoteAdapter(R.id.lesson_list, serviceIntent)
                setEmptyView(R.id.lesson_list, R.id.lesson_empty)
                setContentDescription(R.id.widget_sync, widgetData.getString("syncLabel", "Sync"))
                setContentDescription(R.id.widget_sync_icon, widgetData.getString("syncLabel", "Sync"))
                setTextViewText(
                    R.id.widget_subtitle,
                    widgetData.getString("widgetSubtitle", "Scheduled online lessons"),
                )
                val status = widgetData.getString("widgetStatus", "") ?: ""
                val syncing = widgetData.getString("widgetIsSyncing", "false") == "true"
                setViewVisibility(R.id.widget_sync_icon, if (syncing) View.GONE else View.VISIBLE)
                setViewVisibility(R.id.widget_sync_progress, if (syncing) View.VISIBLE else View.GONE)
                setTextViewText(R.id.widget_status, status)
                setViewVisibility(
                    R.id.widget_status,
                    if (status.isNotBlank()) View.VISIBLE else View.GONE,
                )
                setTextViewText(
                    R.id.widget_last_sync,
                    widgetData.getString("widgetLastSync", ""),
                )
                setTextViewText(
                    R.id.lesson_empty,
                    widgetData.getString("emptyLabel", "No scheduled lessons"),
                )
                setOnClickPendingIntent(
                    R.id.widget_container,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
                setOnClickPendingIntent(
                    R.id.widget_sync_icon,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("kiu://widget-sync"),
                    ),
                )
                val template = Intent(context, KiuLessonWidgetProvider::class.java).apply {
                    action = ACTION_OPEN_LESSON
                }
                setPendingIntentTemplate(
                    R.id.lesson_list,
                    PendingIntent.getBroadcast(
                        context,
                        widgetId,
                        template,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.lesson_list)
        }
        LessonCallAlarms.rearm(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_OPEN_LESSON) return
        when (intent.getStringExtra(EXTRA_ACTION) ?: ACTION_VALUE_OPEN) {
            ACTION_VALUE_TOGGLE -> toggleCall(context, intent)
            else -> LessonLinkRouter.open(context, intent.getStringExtra(EXTRA_LINK))
        }
    }

    /** Flips a single lesson's call override; the same URI shape the Dart background isolate expects. */
    private fun toggleCall(context: Context, intent: Intent) {
        val key = intent.getStringExtra(EXTRA_KEY) ?: return
        val next = !intent.getBooleanExtra(EXTRA_CALL_ENABLED, false)
        HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("kiu://widget-call-toggle/${Uri.encode(key)}?on=${if (next) "1" else "0"}"),
        ).send()
    }

    companion object {
        const val ACTION_OPEN_LESSON = "com.mashkhurbek.kiu.OPEN_WIDGET_LESSON"
        const val EXTRA_LINK = "lessonLink"
        const val EXTRA_ACTION = "action"
        const val EXTRA_KEY = "callKey"
        const val EXTRA_CALL_ENABLED = "callEnabled"
        const val ACTION_VALUE_OPEN = "open"
        const val ACTION_VALUE_TOGGLE = "toggle"
        const val TRUSTED_HOST = "uz.do-kazankiu.ru"

        fun isValidHttps(uri: Uri): Boolean =
            uri.scheme.equals("https", ignoreCase = true) &&
                !uri.host.isNullOrBlank() &&
                uri.userInfo.isNullOrBlank()
    }
}
