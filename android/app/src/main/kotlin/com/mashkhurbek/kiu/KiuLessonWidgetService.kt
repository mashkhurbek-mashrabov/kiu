package com.mashkhurbek.kiu

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

class KiuLessonWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = LessonFactory(applicationContext)
}

private class LessonFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var rows: List<WidgetRow> = emptyList()
    private var dark: Boolean = false

    override fun onCreate() = load()

    override fun onDataSetChanged() = load()

    override fun onDestroy() = Unit

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews = when (val row = rows.getOrNull(position)) {
        is WidgetRow.Header -> RemoteViews(context.packageName, R.layout.kiu_lesson_widget_group_header).apply {
            setTextViewText(R.id.lesson_group_title, row.title)
            setTextColor(R.id.lesson_group_title, WidgetTheme.muted(dark))
            setInt(R.id.lesson_group_rule, "setBackgroundColor", WidgetTheme.rule(dark))
        }
        is WidgetRow.Lesson -> lessonView(row.lesson, position)
        null -> RemoteViews(context.packageName, R.layout.kiu_lesson_widget_group_header)
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 3

    override fun getItemId(position: Int): Long = when (val row = rows.getOrNull(position)) {
        is WidgetRow.Header -> (row.title.hashCode().toLong() shl 32) xor position.toLong()
        is WidgetRow.Lesson -> row.lesson.optLong("start", position.toLong()).xor(position.toLong())
        null -> position.toLong()
    }

    override fun hasStableIds(): Boolean = true

    private fun load() {
        val data = HomeWidgetPlugin.getData(context)
        dark = data.getString("widgetDark", "false") == "true"
        val lessons = runCatching {
            JSONArray(data.getString("lessons", "[]") ?: "[]")
        }.getOrDefault(JSONArray())
        val loadedRows = mutableListOf<WidgetRow>()
        var previousGroup: String? = null
        for (index in 0 until lessons.length()) {
            val lesson = lessons.optJSONObject(index) ?: continue
            val group = lesson.optString("group", "Others")
            if (group != previousGroup) {
                loadedRows += WidgetRow.Header(group)
                previousGroup = group
            }
            loadedRows += WidgetRow.Lesson(lesson)
        }
        rows = loadedRows
    }

    private fun lessonView(lesson: JSONObject, position: Int): RemoteViews {
        val started = lesson.optLong("start", Long.MAX_VALUE) <= System.currentTimeMillis()
        val today = lesson.optString("groupKey") == "today"
        val layout = if (started || today) {
            R.layout.kiu_lesson_widget_item
        } else {
            R.layout.kiu_lesson_widget_item_other
        }
        return RemoteViews(context.packageName, layout).apply {
            setTextViewText(R.id.lesson_title, lesson.optString("title"))
            setTextViewText(R.id.lesson_time, lesson.optString("displayStart"))
            setInt(
                R.id.lesson_item,
                "setBackgroundResource",
                if (started || today) {
                    WidgetTheme.lessonItem(dark)
                } else {
                    WidgetTheme.lessonItemOther(dark)
                },
            )
            setInt(R.id.lesson_time, "setBackgroundResource", WidgetTheme.lessonTime(dark))
            setTextColor(R.id.lesson_title, WidgetTheme.lessonTitle(dark, started, today))
            setTextColor(R.id.lesson_time, WidgetTheme.lessonTimeText(dark, started, today))
            setViewVisibility(R.id.lesson_scheduled_accent, if (!started && today) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.lesson_started_accent, if (started) View.VISIBLE else View.GONE)

            // optString maps a JSON null to the literal "null", not to "" - guard explicitly.
            val meetingUrl = if (lesson.isNull("meetingUrl")) {
                null
            } else {
                lesson.optString("meetingUrl").takeIf { it.isNotBlank() }
            }
            val canJoin = started && meetingUrl != null && KiuLessonWidgetProvider.isValidHttps(Uri.parse(meetingUrl))

            val callKey = lesson.optString("key")
            val callEnabled = lesson.optBoolean("callEnabled", false)
            val labels = HomeWidgetPlugin.getData(context)
            if (canJoin) {
                setImageViewResource(R.id.lesson_call_toggle, R.drawable.ic_call_join)
                setContentDescription(
                    R.id.lesson_call_toggle,
                    labels.getString("callJoinLabel", null) ?: "Join the lesson",
                )
                setOnClickFillInIntent(
                    R.id.lesson_call_toggle,
                    Intent().apply {
                        data = Uri.parse("kiu://widget-lesson/$position")
                        putExtra(KiuLessonWidgetProvider.EXTRA_LINK, meetingUrl)
                        putExtra(KiuLessonWidgetProvider.EXTRA_ACTION, KiuLessonWidgetProvider.ACTION_VALUE_OPEN)
                    },
                )
            } else {
                setImageViewResource(
                    R.id.lesson_call_toggle,
                    if (callEnabled) R.drawable.ic_call else R.drawable.ic_call_off,
                )
                setContentDescription(
                    R.id.lesson_call_toggle,
                    if (callEnabled) {
                        labels.getString("callToggleOffLabel", null) ?: "Turn off the call for this lesson"
                    } else {
                        labels.getString("callToggleOnLabel", null) ?: "Turn on the call for this lesson"
                    },
                )
                if (callKey.isNotBlank()) {
                    setOnClickFillInIntent(
                        R.id.lesson_call_toggle,
                        Intent().apply {
                            data = Uri.parse("kiu://widget-call-toggle/$position")
                            putExtra(KiuLessonWidgetProvider.EXTRA_ACTION, KiuLessonWidgetProvider.ACTION_VALUE_TOGGLE)
                            putExtra(KiuLessonWidgetProvider.EXTRA_KEY, callKey)
                            putExtra(KiuLessonWidgetProvider.EXTRA_CALL_ENABLED, callEnabled)
                        },
                    )
                }
            }

            if (canJoin) {
                setOnClickFillInIntent(
                    R.id.lesson_item,
                    Intent().apply {
                        data = Uri.parse("kiu://widget-lesson/$position")
                        putExtra(KiuLessonWidgetProvider.EXTRA_LINK, meetingUrl)
                        putExtra(KiuLessonWidgetProvider.EXTRA_ACTION, KiuLessonWidgetProvider.ACTION_VALUE_OPEN)
                    },
                )
            }
        }
    }

    private sealed interface WidgetRow {
        data class Header(val title: String) : WidgetRow

        data class Lesson(val lesson: JSONObject) : WidgetRow
    }

}
