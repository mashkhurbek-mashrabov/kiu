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

    /** Brand green; lightened in dark mode so it stays readable on #2B2939. */
    fun brand(dark: Boolean): Int = if (dark) Color.rgb(127, 209, 168) else Color.rgb(23, 107, 69)

    fun muted(dark: Boolean): Int = if (dark) Color.rgb(169, 163, 188) else Color.rgb(104, 116, 109)

    fun divider(dark: Boolean): Int = if (dark) Color.rgb(92, 86, 112) else Color.rgb(166, 180, 171)

    fun rule(dark: Boolean): Int = if (dark) Color.rgb(70, 65, 92) else Color.rgb(217, 228, 220)

    fun lessonTitle(dark: Boolean, started: Boolean, today: Boolean): Int = when {
        started -> brand(dark)
        today -> if (dark) Color.rgb(242, 201, 76) else Color.rgb(167, 120, 0)
        dark -> Color.rgb(230, 227, 240)
        else -> Color.rgb(52, 65, 58)
    }

    fun lessonTimeText(dark: Boolean, started: Boolean, today: Boolean): Int = when {
        started -> brand(dark)
        today -> if (dark) Color.rgb(224, 179, 65) else Color.rgb(138, 101, 0)
        else -> muted(dark)
    }
}
