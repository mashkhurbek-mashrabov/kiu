package com.mashkhurbek.kiu

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment

/**
 * Lesson-video downloads through the system [DownloadManager], so a download
 * keeps going after the app is closed and shows its own notification.
 *
 * Files land in the app-private external files dir (`Movies/lessons/`): no
 * storage permission, removed on uninstall. Dart validates the URL and owns the
 * index; this only enqueues, reports and removes.
 */
object LessonVideoDownloads {
    private const val SUBDIR = "lessons"

    fun enqueue(context: Context, url: String, fileName: String, title: String): Long {
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(title)
            .setMimeType("video/mp4")
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
            )
            .setDestinationInExternalFilesDir(
                context,
                Environment.DIRECTORY_MOVIES,
                "$SUBDIR/$fileName",
            )
        return manager(context).enqueue(request)
    }

    fun query(context: Context, ids: LongArray): List<Map<String, Any?>> {
        if (ids.isEmpty()) return emptyList()
        val rows = mutableListOf<Map<String, Any?>>()
        manager(context).query(DownloadManager.Query().setFilterById(*ids))?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val status = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            val done = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val total = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            val local = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
            while (cursor.moveToNext()) {
                rows += mapOf(
                    "id" to cursor.getLong(id),
                    "status" to statusName(cursor.getInt(status)),
                    "downloaded" to cursor.getLong(done),
                    "total" to cursor.getLong(total),
                    "path" to cursor.getString(local)?.let { Uri.parse(it).path },
                )
            }
        }
        return rows
    }

    /** Cancels a running download or deletes a finished one's file. */
    fun remove(context: Context, ids: LongArray) {
        if (ids.isNotEmpty()) manager(context).remove(*ids)
    }

    private fun manager(context: Context) =
        context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun statusName(status: Int) = when (status) {
        DownloadManager.STATUS_SUCCESSFUL -> "done"
        DownloadManager.STATUS_FAILED -> "failed"
        else -> "running" // pending, running and paused (waiting for network)
    }
}
