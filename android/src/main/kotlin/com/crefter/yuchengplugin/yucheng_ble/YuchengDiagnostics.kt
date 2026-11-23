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
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal object YuchengDiagnostics {
    private const val DETAILED_SEGMENT_BYTES = 384 * 1024
    private val detailedSegmentMillis = TimeUnit.DAYS.toMillis(1)
    private val detailedRetentionMillis = TimeUnit.DAYS.toMillis(7)
    private val segmentName = Regex("""yucheng-history\.([0-9]+)\.[A-Fa-f0-9-]+\.log""")
    private val legacyNames = setOf("yucheng-history.log", "yucheng-history.previous.log")
    private var activeSegment: File? = null
    private var activeSegmentStarted = 0L
    private val detailedLock = Any()
    private var detailedGeneration = 0L
    private var detailedEnabled = false
    private val pendingWrites = Semaphore(64)
    private val writesDropped = AtomicBoolean()
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
        writer.execute { pruneDetailedFiles() }
    }

    fun setDetailedEnabled(enabled: Boolean, complete: (Boolean) -> Unit) {
        synchronized(detailedLock) {
            if (!enabled) {
                detailedGeneration++
                detailedEnabled = false
            }
            val generation = detailedGeneration
            writer.execute {
                val ready = if (enabled) pruneDetailedFiles() else clearDetailedFiles()
                if (enabled) synchronized(detailedLock) {
                    if (generation == detailedGeneration) detailedEnabled = ready
                }
                Handler(Looper.getMainLooper()).post { complete(ready) }
            }
        }
    }

    fun flush(complete: (Boolean) -> Unit) {
        writer.execute {
            val pruned = pruneDetailedFiles()
            val dropped = writesDropped.getAndSet(false)
            val success = pruned && !writeFailed && !dropped
            writeFailed = false
            Handler(Looper.getMainLooper()).post { complete(success) }
        }
    }

    fun summary(event: String, fields: String = "") {
        val now = Date()
        if (!reserveWrite()) return
        writer.execute {
            try {
                val suffix = if (fields.isEmpty()) "" else " $fields"
                append("${formatter.format(now)} $event$suffix\n", detailed = false)
            } finally {
                pendingWrites.release()
            }
        }
    }

    fun detailedSession(): Long? = synchronized(detailedLock) {
        if (detailedEnabled) detailedGeneration else null
    }

    fun detailed(event: String, session: Long?, chunkSize: Int = 64, rows: () -> List<Map<String, Any>>) {
        if (session == null || session != detailedSession() || !reserveWrite()) return
        val snapshot = try {
            rows()
        } catch (exception: Exception) {
            pendingWrites.release()
            throw exception
        }
        val now = Date()
        synchronized(detailedLock) {
            if (session != detailedSession()) {
                pendingWrites.release()
                return
            }
            writer.execute {
                try {
                    val timestamp = formatter.format(now)
                    for (batch in snapshot.chunked(chunkSize)) {
                        if (session != detailedSession()) break
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
                } finally {
                    pendingWrites.release()
                }
            }
        }
    }

    private fun reserveWrite(): Boolean {
        if (pendingWrites.tryAcquire()) return true
        writesDropped.set(true)
        return false
    }

    private fun nativeDirectory(): File? = context?.let {
        File(PathUtils.getDataDirectory(it), "diagnostics/native")
    }

    private fun detailedFiles(): List<File> {
        val folder = File(nativeDirectory() ?: throw IOException("Diagnostics directory unavailable"), "detailed")
        return if (folder.exists()) {
            (folder.listFiles() ?: throw IOException("Diagnostics directory unavailable")).filter {
                it.name in legacyNames || segmentName.matches(it.name)
            }
        } else emptyList()
    }

    private fun remove(file: File) {
        if (!file.delete()) throw IOException("Diagnostics cleanup failed")
        if (activeSegment == file) activeSegment = null
    }

    private fun clearDetailedFiles(): Boolean = try {
        detailedFiles().forEach(::remove)
        true
    } catch (_: IOException) {
        false
    }

    private fun pruneDetailedFiles(now: Long = System.currentTimeMillis()): Boolean = try {
        val retained = detailedFiles().mapNotNull { file ->
            val started = segmentName.matchEntire(file.name)?.groupValues?.get(1)?.toLongOrNull()
            if (started == null || started <= now - detailedRetentionMillis) {
                remove(file)
                null
            } else started to file
        }.sortedBy { it.first }
        var bytes = retained.sumOf { it.second.length() }
        for ((_, file) in retained) {
            if (bytes <= 2L * DETAILED_SEGMENT_BYTES) break
            bytes -= file.length()
            remove(file)
        }
        true
    } catch (_: IOException) {
        writeFailed = true
        false
    }

    private fun append(line: String, detailed: Boolean) {
        val native = nativeDirectory() ?: return
        val bytes = line.toByteArray(Charsets.UTF_8)
        val limit = if (detailed) DETAILED_SEGMENT_BYTES else 128 * 1024
        val folder = if (detailed) File(native, "detailed") else native
        try {
            if (bytes.size > limit) throw IOException("Diagnostics entry too large")
            if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Diagnostics directory unavailable")
            if (detailed) {
                val now = System.currentTimeMillis()
                val active = activeSegment
                val file = if (active == null || !active.exists() || active.length() + bytes.size > limit ||
                    now - activeSegmentStarted >= detailedSegmentMillis
                ) {
                    File(folder, "yucheng-history.$now.${UUID.randomUUID()}.log").also {
                        activeSegment = it
                        activeSegmentStarted = now
                    }
                } else active
                file.appendBytes(bytes)
                pruneDetailedFiles(now)
            } else {
                val file = File(folder, "yucheng-native.log")
                val previous = File(folder, "yucheng-native.previous.log")
                if (file.length() + bytes.size > limit) {
                    if (previous.exists()) remove(previous)
                    if (!file.renameTo(previous)) throw IOException("Diagnostics rotation failed")
                }
                file.appendBytes(bytes)
            }
        } catch (_: IOException) {
            writeFailed = true
        }
    }
}
