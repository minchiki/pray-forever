package com.prayforever.app.core

/**
 * Чистая логика: какие точные события поставить в AlarmManager.
 * На iOS вместо этого строится цепочка уведомлений; на Android звонок держит foreground-сервис,
 * поэтому достаточно одного события на каждое время намаза и каждый будильник.
 */
object AlarmPlanner {
    enum class Kind { PRAYER_TIME, ALARM, PAUSE_END }

    data class Event(
        val kind: Kind,
        val at: Long,
        val instanceId: String?,
    ) {
        /** Стабильный код для PendingIntent: одно и то же событие перезаписывается, а не дублируется. */
        val requestCode: Int get() = "${kind.name}:${instanceId.orEmpty()}".hashCode()
    }

    /** Сколько максимум звонит будильник, если приложение никто не открыл. */
    const val MAX_RING_DURATION = 60 * 60_000L

    /** Ограничение на число событий (у AlarmManager есть лимит на приложение). */
    const val MAX_EVENTS = 40

    /**
     * @param instances срабатывания, отсортированные по времени.
     * @param pauseEnd конец паузы: до него ничего не планируется, кроме напоминания об окончании.
     */
    fun plan(
        instances: List<AlarmInstance>,
        dismissed: Set<String>,
        notifyAtPrayerTime: Boolean,
        pauseEnd: Long?,
        now: Long,
    ): List<Event> {
        val events = mutableListOf<Event>()
        if (pauseEnd != null && pauseEnd > now) events += Event(Kind.PAUSE_END, pauseEnd, null)
        val start = maxOf(now, pauseEnd ?: now)
        for (instance in instances) {
            if ((notifyAtPrayerTime || instance.isWakeCheck) && instance.prayerTime > start) {
                events += Event(Kind.PRAYER_TIME, instance.prayerTime, instance.id)
            }
            if (instance.alarmEnabled && instance.id !in dismissed && instance.alarmTime > start) {
                events += Event(Kind.ALARM, instance.alarmTime, instance.id)
            }
        }
        return events.sortedBy { it.at }.take(MAX_EVENTS)
    }

    /** Срабатывание, которое должно звонить прямо сейчас. */
    fun dueInstance(
        instances: List<AlarmInstance>,
        dismissed: Set<String>,
        now: Long,
    ): AlarmInstance? =
        instances
            .filter { it.alarmEnabled && it.id !in dismissed }
            .filter { it.alarmTime <= now && now < it.alarmTime + MAX_RING_DURATION }
            .maxByOrNull { it.alarmTime }
}
