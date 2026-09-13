package com.mashkhurbek.kiu

import android.graphics.Color

/**
 * Palette for the home-screen widget. The widget follows the in-app Appearance
 * choice, not the OS night-mode qualifier, so Dart publishes the resolved mode
 * as `widgetDark` and both the provider and the list factory tint from here.
 */
internal object WidgetTheme {
    fun background(dark: Boolean): Int =
        if (dark) R.drawable.kiu_widget_background_dark else R.drawable.kiu_widget_background

    fun syncButton(dark: Boolean): Int =
        if (dark) R.drawable.kiu_widget_sync_button_dark else R.drawable.kiu_widget_sync_button

    fun lessonItem(dark: Boolean): Int =
        if (dark) R.drawable.kiu_widget_lesson_item_dark else R.drawable.kiu_widget_lesson_item

    fun lessonItemOther(dark: Boolean): Int =
        if (dark) {
            R.drawable.kiu_widget_lesson_item_other_dark
        } else {
            R.drawable.kiu_widget_lesson_item_other
        }

    fun lessonTime(dark: Boolean): Int =
        if (dark) R.drawable.kiu_widget_lesson_time_dark else R.drawable.kiu_widget_lesson_time

    /**
     * Text colors. These duplicate res/values/colors.xml on purpose: RemoteViews
     * setTextColor takes a resolved int, not a resource id, and the widget picks
     * its mode from the in-app setting rather than the -night qualifier, so the
     * resource system cannot pick the variant for us. Keep the two in step.
     */
    fun brand(dark: Boolean): Int = if (dark) Color.rgb(111, 211, 160) else Color.rgb(23, 107, 69)

    fun muted(dark: Boolean): Int = if (dark) Color.rgb(168, 180, 172) else Color.rgb(92, 102, 96)

    fun rule(dark: Boolean): Int = if (dark) Color.rgb(58, 66, 61) else Color.rgb(220, 229, 222)

    fun lessonTitle(dark: Boolean, started: Boolean, today: Boolean): Int = when {
        started -> brand(dark)
        today -> if (dark) Color.rgb(227, 184, 95) else Color.rgb(122, 85, 0)
        dark -> Color.rgb(227, 230, 227)
        else -> Color.rgb(26, 28, 26)
    }

    fun lessonTimeText(dark: Boolean, started: Boolean, today: Boolean): Int = when {
        started -> brand(dark)
        today -> if (dark) Color.rgb(212, 170, 82) else Color.rgb(138, 101, 0)
        else -> muted(dark)
    }
}
