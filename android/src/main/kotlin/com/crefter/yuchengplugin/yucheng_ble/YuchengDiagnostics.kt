package com.crefter.yuchengplugin.yucheng_ble

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.util.PathUtils
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

internal object YuchengDiagnostics {
    private const val PREF_KEY = "enabled"
    private const val DETAILED_FILE = "yucheng-history.log"
    private const val PREVIOUS_DETAILED_FILE = "yucheng-history.previous.log"
    private val detailedLock = Any()
    private var detailedGeneration = 0L
    private var detailedEnabled = false
    private val writer = Executors.newSingleThreadExecutor { Thread(it, "yucheng-diagnostics").apply { isDaemon = true } }
    private val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }
    @Volatile
    private var context: Context? = null
    private var writeFailed = false

    @Synchronized
    fun initialize(applicationContext: Context) {
        if (context != null) return
        context = applicationContext.applicationContext
        synchronized(detailedLock) {
            detailedEnabled = preferences()?.getBoolean(PREF_KEY, false) == true
        }
    }

    private fun preferences() = context?.getSharedPreferences("yucheng.diagnostics.detailed", Context.MODE_PRIVATE)

    fun setDetailedEnabled(enabled: Boolean, complete: (Boolean) -> Unit) {
        writer.execute {
            if (!enabled) synchronized(detailedLock) {
                detailedGeneration++
                detailedEnabled = false
            }
            val saved = preferences()?.edit()?.putBoolean(PREF_KEY, enabled)?.commit() == true
            if (enabled && saved) synchronized(detailedLock) {
                detailedEnabled = true
            }
            val cleared = enabled || clearDetailedFiles()
            Handler(Looper.getMainLooper()).post { complete(saved && cleared) }
        }
    }

    fun flush(complete: (Boolean) -> Unit) {
        writer.execute {
            val success = !writeFailed
            writeFailed = false
            Handler(Looper.getMainLooper()).post { complete(success) }
        }
    }

    fun summary(event: String, fields: String = "") {
        val now = Date()
        writer.execute {
            val suffix = if (fields.isEmpty()) "" else " $fields"
            append("${formatter.format(now)} $event$suffix\n", detailed = false)
        }
    }

    fun detailedSession(): Long? = synchronized(detailedLock) {
        if (detailedEnabled) detailedGeneration else null
    }

    fun detailed(event: String, session: Long?, chunkSize: Int = 64, rows: () -> List<Map<String, Any>>) {
        if (session == null || session != detailedSession()) return
        val snapshot = rows()
        val now = Date()
        writer.execute {
            if (session != detailedGeneration) return@execute
            val timestamp = formatter.format(now)
            for (batch in snapshot.chunked(chunkSize)) {
                try {
                    val line = JSONObject()
                        .put("timestamp", timestamp)
                        .put("event", event)
                        .put("rows", JSONArray(batch.map { JSONObject(it) }))
                    append("$line\n", detailed = true)
                } catch (_: JSONException) {
                    writeFailed = true
                }
            }
        }
    }

    private fun nativeDirectory(): File? = context?.let {
        File(PathUtils.getDataDirectory(it), "diagnostics/native")
    }

    private fun clearDetailedFiles(): Boolean {
        val native = nativeDirectory() ?: return false
        val folder = File(native, "detailed")
        return listOf(DETAILED_FILE, PREVIOUS_DETAILED_FILE).map { name ->
            val file = File(folder, name)
            !file.exists() || file.delete()
        }.all { it }
    }

    private fun append(line: String, detailed: Boolean) {
        val native = nativeDirectory() ?: return
        val folder = if (detailed) File(native, "detailed") else native
        val file = File(folder, if (detailed) DETAILED_FILE else "yucheng-native.log")
        val previous = File(folder, if (detailed) PREVIOUS_DETAILED_FILE else "yucheng-native.previous.log")
        val limit = (if (detailed) 384 else 128) * 1024
        val bytes = line.toByteArray(Charsets.UTF_8)
        try {
            if (bytes.size > limit) throw IOException("Diagnostics entry too large")
            if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Diagnostics directory unavailable")
            if (file.length() + bytes.size > limit) {
                if (previous.exists() && !previous.delete()) throw IOException("Diagnostics rotation failed")
                if (!file.renameTo(previous)) throw IOException("Diagnostics rotation failed")
            }
            file.appendBytes(bytes)
        } catch (_: IOException) {
            writeFailed = true
        }
    }
}
