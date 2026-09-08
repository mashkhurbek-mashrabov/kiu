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
        appWidgetIds.forEach { widgetId ->
            val serviceIntent = Intent(context, KiuLessonWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            val views = RemoteViews(context.packageName, R.layout.kiu_lesson_widget).apply {
                setRemoteAdapter(R.id.lesson_list, serviceIntent)
                setEmptyView(R.id.lesson_list, R.id.lesson_empty)
                setContentDescription(R.id.widget_sync, widgetData.getString("syncLabel", "Sync"))
                setContentDescription(R.id.widget_sync_icon, widgetData.getString("syncLabel", "Sync"))
                val status = widgetData.getString("widgetStatus", "") ?: ""
                val syncing = widgetData.getString("widgetIsSyncing", "false") == "true"
                setViewVisibility(R.id.widget_sync_icon, if (syncing) View.GONE else View.VISIBLE)
                setViewVisibility(R.id.widget_sync_progress, if (syncing) View.VISIBLE else View.GONE)
                val statusVisibleUntil =
                    widgetData.getString("widgetStatusVisibleUntil", "0")?.toLongOrNull() ?: 0L
                setTextViewText(R.id.widget_status, status)
                setViewVisibility(
                    R.id.widget_status,
                    if (status.isNotBlank() &&
                        (statusVisibleUntil <= 0L || System.currentTimeMillis() < statusVisibleUntil)
                    ) {
                        View.VISIBLE
                    } else {
                        View.GONE
                    },
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
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                setPendingIntentTemplate(
                    R.id.lesson_list,
                    PendingIntent.getBroadcast(context, widgetId, template, flags),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.lesson_list)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_OPEN_LESSON) return
        val link = intent.getStringExtra(EXTRA_LINK) ?: return
        val uri = Uri.parse(link)
        if (!isValidHttps(uri)) return

        val target = if (uri.host.equals(TRUSTED_HOST, ignoreCase = true)) {
            Intent(context, MainActivity::class.java).apply {
                action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                data = uri
            }
        } else {
            Intent(Intent.ACTION_VIEW, uri)
        }
        target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(target) }
    }

    companion object {
        const val ACTION_OPEN_LESSON = "com.mashkhurbek.kiu.OPEN_WIDGET_LESSON"
        const val EXTRA_LINK = "lessonLink"
        const val TRUSTED_HOST = "uz.do-kazankiu.ru"

        fun isValidHttps(uri: Uri): Boolean =
            uri.scheme.equals("https", ignoreCase = true) &&
                !uri.host.isNullOrBlank() &&
                uri.userInfo.isNullOrBlank()
    }
}
