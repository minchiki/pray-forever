package com.prayforever.app.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.prayforever.app.core.AlarmPlanner
import com.prayforever.app.data.SettingsStore
import com.prayforever.app.ui.MainActivity

/** Ставит события плана в AlarmManager. Будильники — через setAlarmClock (точно, даже в Doze). */
object AlarmScheduler {
    private const val TAG = "AlarmScheduler"
    const val ACTION_EVENT = "com.prayforever.app.EVENT"
    const val EXTRA_KIND = "kind"
    const val EXTRA_INSTANCE = "instance"

    fun canScheduleExact(context: Context): Boolean {
        val manager = context.getSystemService(AlarmManager::class.java)
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
    }

    fun apply(
        context: Context,
        store: SettingsStore,
        events: List<AlarmPlanner.Event>,
    ) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val codes = events.map { it.requestCode }.toSet()
        for (stale in store.scheduledCodes - codes) {
            manager.cancel(pendingIntent(context, stale, null))
        }
        val exact = canScheduleExact(context)
        for (event in events) {
            val operation = pendingIntent(context, event.requestCode, event)
            try {
                when {
                    event.kind == AlarmPlanner.Kind.ALARM && exact -> {
                        val show =
                            PendingIntent.getActivity(
                                context,
                                0,
                                Intent(context, MainActivity::class.java),
                                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                            )
                        manager.setAlarmClock(AlarmManager.AlarmClockInfo(event.at, show), operation)
                    }
                    exact -> manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.at, operation)
                    // Без разрешения на точные будильники система может сдвинуть событие — предупреждение показывает главный экран.
                    else -> manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.at, operation)
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "Exact alarm denied, falling back to inexact", e)
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.at, operation)
            }
        }
        store.scheduledCodes = codes
    }

    private fun pendingIntent(
        context: Context,
        code: Int,
        event: AlarmPlanner.Event?,
    ): PendingIntent {
        val intent =
            Intent(context, AlarmReceiver::class.java).setAction(ACTION_EVENT).apply {
                if (event != null) {
                    putExtra(EXTRA_KIND, event.kind.name)
                    putExtra(EXTRA_INSTANCE, event.instanceId)
                }
            }
        return PendingIntent.getBroadcast(
            context,
            code,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}

/** Событие расписания: время намаза, будильник или конец паузы. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != AlarmScheduler.ACTION_EVENT) return
        AlarmController.init(context)
        val kind =
            intent
                .getStringExtra(AlarmScheduler.EXTRA_KIND)
                ?.let { name -> AlarmPlanner.Kind.entries.firstOrNull { it.name == name } }
                ?: return AlarmController.refresh()
        AlarmController.handleEvent(kind, intent.getStringExtra(AlarmScheduler.EXTRA_INSTANCE))
    }
}

/** После перезагрузки, обновления приложения или смены времени расписание пересобирается. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action !in ACTIONS) return
        AlarmController.init(context)
        AlarmController.refresh()
    }

    private companion object {
        val ACTIONS =
            setOf(
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED,
                "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            )
    }
}
