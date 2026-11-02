package com.prayforever.app.alarm

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.prayforever.app.R
import com.prayforever.app.core.AlarmInstance
import com.prayforever.app.core.AlarmSound
import com.prayforever.app.ui.AlarmActivity
import com.prayforever.app.ui.MainActivity
import com.prayforever.app.ui.prayerName

/** Каналы и уведомления. Звук будильника играет сервис, поэтому канал будильника беззвучный. */
object Notifications {
    const val ALARM_ID = 1
    private const val PRAYER_ID_BASE = 1000
    private const val PAUSE_ID = 2
    private const val CHANNEL_ALARM = "alarm"
    private const val CHANNEL_PRAYER = "prayer"
    private const val CHANNEL_STATUS = "status"

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(
                    CHANNEL_ALARM,
                    context.getString(R.string.notif_channel_alarm),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = context.getString(R.string.notif_channel_alarm_desc)
                    setSound(null, null)
                    enableVibration(false)
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                },
                NotificationChannel(
                    CHANNEL_PRAYER,
                    context.getString(R.string.notif_channel_prayer),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = context.getString(R.string.notif_channel_prayer_desc) },
                NotificationChannel(
                    CHANNEL_STATUS,
                    context.getString(R.string.notif_channel_status),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = context.getString(R.string.notif_channel_status_desc) },
            ),
        )
    }

    private fun alarmActivityIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun mainActivityIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** Уведомление звонящего будильника: полноэкранное задание поверх блокировки, смахнуть нельзя. */
    fun ringing(
        context: Context,
        instance: AlarmInstance?,
    ): Notification {
        val title =
            when {
                instance == null || instance.isTest -> context.getString(R.string.alarm_test)
                else -> context.getString(R.string.notif_alarm_title, context.prayerName(instance.prayer))
            }
        return alarmNotification(context, title, context.getString(R.string.notif_alarm_body))
    }

    fun wakeCheck(context: Context): Notification =
        alarmNotification(
            context,
            context.getString(R.string.wake_notif_title),
            context.getString(R.string.wake_notif_body),
        )

    private fun alarmNotification(
        context: Context,
        title: String,
        body: String,
    ): Notification {
        val task = alarmActivityIntent(context)
        return NotificationCompat
            .Builder(context, CHANNEL_ALARM)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(task, true)
            .setContentIntent(task)
            .addAction(0, context.getString(R.string.notif_ringing_open), task)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    /** Сервис не удалось запустить — хотя бы громкое уведомление с заданием. */
    fun postFallbackAlarm(
        context: Context,
        instance: AlarmInstance,
    ) = post(context, ALARM_ID, ringing(context, instance))

    fun postPrayerTime(
        context: Context,
        instance: AlarmInstance,
        delayMinutes: Int,
    ) {
        val body =
            if (instance.alarmEnabled) {
                context.getString(R.string.notif_prayer_body_alarm, delayMinutes)
            } else {
                context.getString(R.string.notif_prayer_body)
            }
        val notification =
            NotificationCompat
                .Builder(context, CHANNEL_PRAYER)
                .setSmallIcon(R.drawable.ic_stat_alarm)
                .setContentTitle(context.prayerName(instance.prayer))
                .setContentText(body)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(mainActivityIntent(context))
                .setAutoCancel(true)
                .build()
        post(context, PRAYER_ID_BASE + instance.prayer.ordinal, notification)
    }

    fun postPauseEnded(context: Context) {
        val notification =
            NotificationCompat
                .Builder(context, CHANNEL_STATUS)
                .setSmallIcon(R.drawable.ic_stat_alarm)
                .setContentTitle(context.getString(R.string.pause_ended_title))
                .setContentText(context.getString(R.string.pause_ended_body))
                .setContentIntent(mainActivityIntent(context))
                .setAutoCancel(true)
                .build()
        post(context, PAUSE_ID, notification)
    }

    fun permitted(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
            )

    fun canUseFullScreen(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    private fun post(
        context: Context,
        id: Int,
        notification: Notification,
    ) {
        if (!permitted(context)) return
        @Suppress("MissingPermission")
        NotificationManagerCompat.from(context).notify(id, notification)
    }
}

/** Короткое прослушивание звука в настройках (3 секунды на потоке будильника). */
object SoundPreview {
    private const val DURATION = 3000L
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())

    fun play(
        context: Context,
        sound: AlarmSound,
    ) {
        if (AlarmService.mode.value != AlarmService.Mode.IDLE) return
        stop()
        player =
            runCatching {
                MediaPlayer().apply {
                    context.assets.openFd(sound.fileName).use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                    setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                    prepare()
                    start()
                }
            }.getOrNull()
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed(::stop, DURATION)
    }

    fun stop() {
        player?.runCatching {
            stop()
            release()
        }
        player = null
    }
}
