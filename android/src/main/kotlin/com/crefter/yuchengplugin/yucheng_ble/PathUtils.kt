package com.crefter.yuchengplugin.yucheng_ble

import android.content.Context
import android.os.Environment
import java.io.File


object PathUtils {
    /**
     * Return the path of /storage/emulated/0/Android/data/package/cache.
     *
     * @return the path of /storage/emulated/0/Android/data/package/cache
     */
    fun getExternalAppCachePath(context: Context): String? {
        if (isExternalStorageDisable()) return ""
        return getAbsolutePath(context.applicationContext.externalCacheDir)
    }

    private fun isExternalStorageDisable(): Boolean {
        return Environment.MEDIA_MOUNTED != Environment.getExternalStorageState()
    }

    private fun getAbsolutePath(file: File?): String? {
        if (file == null) return ""
        return file.absolutePath
    }
}