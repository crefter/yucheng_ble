package com.crefter.yuchengplugin.yucheng_ble.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.crefter.yuchengplugin.yucheng_ble.YuchengCore
import com.crefter.yuchengplugin.yucheng_ble.YuchengHealthDataConverter
import com.crefter.yuchengplugin.yucheng_ble.YuchengHealthSportData
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepData
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepDataConverter
import com.crefter.yuchengplugin.yucheng_ble.YuchengSportDataConverter
import com.crefter.yuchengplugin.yucheng_ble.data.local.DataStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengBleStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.yuchengBleStore
import com.crefter.yuchengplugin.yucheng_ble.data.remote.ApiClient
import com.crefter.yuchengplugin.yucheng_ble.data.remote.YuchengApiConfig
import com.crefter.yuchengplugin.yucheng_ble.data.remote.YuchengAuthInterceptor
import com.crefter.yuchengplugin.yucheng_ble.data.remote.YuchengRepository
import com.crefter.yuchengplugin.yucheng_ble.data.remote.YuchengTokenAuthenticator
import com.crefter.yuchengplugin.yucheng_ble.entity.StartEndTimestamp
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.collections.isNotEmpty
import kotlin.time.Duration.Companion.minutes


private const val YUCH_TAG = "YUCH_API SERVICE"

// 2. В самом сервисе
class YuchengBleService : Service() {
    private val defaultDelay = 1
    private val NOTIFICATION_ID = 3040
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var gson: Gson? = null
    private var job: Job? = null
    private var delayInMinutes: Int = defaultDelay
    private var yuchengStorage: YuchengBleStorage? = null

    override fun onCreate() {
        super.onCreate()
        isRunning.value = true
        Log.e(YUCH_TAG, "Service: onCreate: begin!")
        yuchengStorage = YuchengBleStorage(DataStorage(applicationContext.yuchengBleStore))
        gson = GsonBuilder().create()
        YuchengCore.init(applicationContext)
    }

    @OptIn(FlowPreview::class)
    @RequiresApi(Build.VERSION_CODES.O)
    private suspend fun readData() {
        Log.i(YUCH_TAG, "Service: Try read data from service!")
        val isConnected = YuchengCore.isConnected()
        if (!isConnected) {
            Log.i(YUCH_TAG, "Service: Not connected, try reconnect!")
            try {
                YuchengCore.reconnect(null, 30)
            } catch (e: Exception) {
                Log.e(YUCH_TAG, "Service: RECONNECT EXCEPTION: $e")
                return
            }
        }
        Log.i(YUCH_TAG, "Service: After reconnect:")
        val startEnd = StartEndTimestamp.default()
        val sleepData = YuchengCore.getSleepData(
            true, startTimestamp = startEnd.start, startEnd.end,
            YuchengSleepDataConverter(gson!!)
        )
        val healthData = YuchengCore.getHealthSportData(
            true, startEnd.start, startEnd.end,
            YuchengSportDataConverter(gson!!), YuchengHealthDataConverter(gson!!)
        )
        sendDataToServer(sleepData, healthData)
        Log.i(YUCH_TAG, "READ DATA FROM SERVICE!!!")
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private suspend fun sendDataToServer(
        sleepData: List<YuchengSleepData>,
        healthData: YuchengHealthSportData
    ) {
        val flavorString = YuchengCore.storage?.readFlavor() ?: return
        val flavor = YuchengFlavor.fromString(flavorString)
        val tokenStorage = YuchengCore.tokenStorage ?: return
        val apiConfig = YuchengApiConfig.fromFlavor(flavor)
        val repo = YuchengRepository(
            ApiClient(
                YuchengAuthInterceptor(tokenStorage),
                YuchengTokenAuthenticator(tokenStorage, apiConfig)
            ).getClient(), apiConfig
        )
        withContext(Dispatchers.IO) {
            val id = Build.ID

            if (sleepData.isNotEmpty()) {
                repo.saveSleep(sleepData, id)
            }
            if (healthData.healthData.isNotEmpty() || healthData.sportData.isNotEmpty()) {
                repo.saveHealth(healthData, id)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_SERVICE") {
            Log.e(YUCH_TAG, "SERVICE STOP!")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            Log.e(YUCH_TAG, "Service: onStartCommand: Try start notification")
            startForegroundService()
            Log.e(YUCH_TAG, "Service: onStartCommand: Success!")
        } catch (e: Exception) {
            Log.e(YUCH_TAG, "Service: onStartCommand: Error: $e")
        }
        if (job?.isActive != true) {
            job = scope.launch {
                while (isActive) {
                    delayInMinutes = yuchengStorage?.readDelay() ?: defaultDelay
                    Log.e(
                        YUCH_TAG,
                        "Service: onStartCommand: Service delay in minutes = $delayInMinutes"
                    )
                    delay(delayInMinutes.minutes)
                    readData()
                }
            }
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
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Log.e(YUCH_TAG, "Service: ServiceCompat.startForeground")
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            Log.e(YUCH_TAG, "Service: startForeground")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onBind(p0: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        isRunning.value = false
        Log.e(YUCH_TAG, "onDestroy")
        job?.cancel()
        super.onDestroy()
    }

    companion object {
        fun stopService(context: Context) {
            Log.e(YUCH_TAG, "Service stop!!!")
            val intent = Intent(context, YuchengBleService::class.java)
            intent.action = "STOP_SERVICE"
            context.startService(intent)
        }

        fun startService(context: Context) {
            Log.e(YUCH_TAG, "Start service!!! Context = $context")
            val intent = Intent(context, YuchengBleService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        suspend fun restartService(context: Context) {
            if (!isRunning.value) {
                startService(context)
            } else {
                Log.e(YUCH_TAG, "startService: Service has ran yet, restart!!!")
                stopService(context)
                isRunning.first {
                    !it
                }
                startService(context)
            }
        }

        var isRunning = MutableStateFlow(false)
    }
}