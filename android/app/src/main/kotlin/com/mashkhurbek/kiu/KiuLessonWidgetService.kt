package com.mashkhurbek.kiu

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class KiuLessonWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = LessonFactory(applicationContext)
}

private class LessonFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var lessons = JSONArray()

    override fun onCreate() = load()
    override fun onDataSetChanged() = load()
    override fun onDestroy() = Unit
    override fun getCount(): Int = lessons.length()

    override fun getViewAt(position: Int): RemoteViews {
        val item = lessons.optJSONObject(position)
            ?: return RemoteViews(context.packageName, R.layout.kiu_lesson_widget_item)
        val started = item.optLong("start", Long.MAX_VALUE) <= System.currentTimeMillis()
        val meetingUrl = item.optString("meetingUrl").takeIf { it.isNotBlank() }
        return RemoteViews(context.packageName, R.layout.kiu_lesson_widget_item).apply {
            setTextViewText(R.id.lesson_title, item.optString("title"))
            setTextViewText(R.id.lesson_time, item.optString("displayStart"))
            setInt(
                R.id.lesson_item,
                "setBackgroundColor",
                if (started) Color.rgb(183, 228, 199) else Color.rgb(255, 225, 107),
            )
            if (started && meetingUrl != null) {
                val uri = android.net.Uri.parse(meetingUrl)
                if (KiuLessonWidgetProvider.isValidHttps(uri)) {
                    setOnClickFillInIntent(
                        R.id.lesson_item,
                        Intent().putExtra(KiuLessonWidgetProvider.EXTRA_LINK, meetingUrl),
                    )
                }
            }
        }
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long =
        (lessons.optJSONObject(position)?.optLong("start", position.toLong())
            ?: position.toLong()).xor(position.toLong())
    override fun hasStableIds(): Boolean = true

    private fun load() {
        val raw = HomeWidgetPlugin.getData(context).getString("lessons", "[]") ?: "[]"
        lessons = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
    }
}
