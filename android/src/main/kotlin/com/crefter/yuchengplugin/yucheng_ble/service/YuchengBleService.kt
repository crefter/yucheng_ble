package com.crefter.yuchengplugin.yucheng_ble.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.crefter.yuchengplugin.yucheng_ble.YuchengCore
import com.crefter.yuchengplugin.yucheng_ble.YuchengHealthDataConverter
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepDataConverter
import com.crefter.yuchengplugin.yucheng_ble.YuchengSportDataConverter
import com.crefter.yuchengplugin.yucheng_ble.entity.StartEndTimestamp
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.minutes


private const val YUCH_TAG = "YUCH_API"

// 2. В самом сервисе
class YuchengBleService : Service() {
    private val NOTIFICATION_ID = 3040
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var gson: Gson? = null
    private var job: Job? = null

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate() {
        super.onCreate()
        Log.e(YUCH_TAG, "Service started!")
        gson = GsonBuilder().create()
        YuchengCore.init(applicationContext)
        try {
            Log.e(YUCH_TAG, "Try start notification")
            startForegroundService()
            Log.e(YUCH_TAG, "Success!")
        } catch (e: Exception) {
            Log.e(YUCH_TAG, "Error: $e")
        }
        job = scope.launch {
            while (isActive) {
                delay(1.minutes)
                readData()
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private suspend fun readData() {
        Log.i(YUCH_TAG, "Service: Try read data from service!")
        val isConnected = YuchengCore.isConnected()
        if (!isConnected) {
            Log.i(YUCH_TAG, "Service: Not connected, try reconnect!")
            YuchengCore.reconnect(null, 30)
        }
        Log.i(YUCH_TAG, "Service: After reconnect:")
        val startEnd = StartEndTimestamp.default()
        val sleepData = YuchengCore.getSleepData(true, startTimestamp = startEnd.start, startEnd.end,
            YuchengSleepDataConverter(gson!!)
        )
        val healthData = YuchengCore.getHealthSportData(true, startEnd.start, startEnd.end,
            YuchengSportDataConverter(gson!!), YuchengHealthDataConverter(gson!!))
        Log.i(YUCH_TAG, "READ DATA FROM SERVICE!!!")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_SERVICE") {
            Log.e(YUCH_TAG, "SERVICE STOP!")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun startForegroundService() {
        val channelId = "sleepring_ble_service"

        val manager = this.getSystemService(NotificationManager::class.java)

        val channel = NotificationChannel(
            channelId,
            "Sleepring BLE",
            NotificationManager.IMPORTANCE_LOW
        )

        manager.createNotificationChannel(channel)

        val intent = packageManager.getLaunchIntentForPackage(packageName)

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Sleeptery")
            .setContentText("Следим за твоим сном...")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onBind(p0: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        YuchengCore.dispose()
        job?.cancel()
        super.onDestroy()
    }
}