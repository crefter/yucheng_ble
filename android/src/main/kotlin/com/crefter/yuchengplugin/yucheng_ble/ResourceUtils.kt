package com.crefter.yuchengplugin.yucheng_ble

import android.content.Context
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream


object ResourceUtils {
    const val BUFFER_SIZE: Int = 8192

    /**
     * Copy the file from assets.
     *
     * @param assetsFilePath The path of file in assets.
     * @param destFilePath   The path of destination file.
     * @param context        The context
     * @return `true`: success<br></br>`false`: fail
     */
    fun copyFileFromAssets(
        assetsFilePath: String,
        destFilePath: String,
        context: Context
    ): Boolean {
        var res = true
        try {
            val assets = context.applicationContext.assets.list(assetsFilePath)
            if (assets != null && assets.size > 0) {
                for (asset in assets) {
                    res = res and copyFileFromAssets(
                        "$assetsFilePath/$asset",
                        "$destFilePath/$asset",
                        context
                    )
                }
            } else {
                res = writeFileFromIS(
                    destFilePath,
                    context.applicationContext.assets.open(assetsFilePath),
                    false
                )
            }
        } catch (e: IOException) {
            e.printStackTrace()
            res = false
        }
        return res
    }

    private fun writeFileFromIS(
        filePath: String,
        inputStream: InputStream?,
        append: Boolean
    ): Boolean {
        return writeFileFromIS(getFileByPath(filePath), inputStream, append)
    }

    private fun writeFileFromIS(
        file: File?,
        inputStream: InputStream?,
        append: Boolean
    ): Boolean {
        if (!createOrExistsFile(file) || inputStream == null) return false
        var os: OutputStream? = null
        try {
            os = BufferedOutputStream(FileOutputStream(file, append))
            val data: ByteArray? = ByteArray(BUFFER_SIZE)
            var len: Int
            while ((inputStream.read(data, 0, BUFFER_SIZE).also { len = it }) != -1) {
                os.write(data, 0, len)
            }
            return true
        } catch (e: IOException) {
            e.printStackTrace()
            return false
        } finally {
            try {
                inputStream.close()
            } catch (e: IOException) {
                e.printStackTrace()
            }
            try {
                os?.close()
            } catch (e: IOException) {
                e.printStackTrace()
            }
        }
    }

    private fun getFileByPath(filePath: String): File? {
        return if (isSpace(filePath)) null else File(filePath)
    }

    private fun createOrExistsFile(file: File?): Boolean {
        if (file == null) return false
        if (file.exists()) return file.isFile
        if (!createOrExistsDir(file.parentFile)) return false
        try {
            return file.createNewFile()
        } catch (e: IOException) {
            e.printStackTrace()
            return false
        }
    }

    private fun isSpace(s: String?): Boolean {
        if (s == null) return true
        var i = 0
        val len = s.length
        while (i < len) {
            if (!Character.isWhitespace(s.get(i))) {
                return false
            }
            ++i
        }
        return true
    }

    private fun createOrExistsDir(file: File?): Boolean {
        return file != null && (if (file.exists()) file.isDirectory else file.mkdirs())
    }
}