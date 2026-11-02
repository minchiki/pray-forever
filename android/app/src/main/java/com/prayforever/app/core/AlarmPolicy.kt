package com.prayforever.app.core

import kotlin.math.max

/** Правила, которые не дают просто так обойти будильник. Порт `AlarmPolicy.swift`. */
object AlarmPolicy {
    /** Через сколько после выполненного задания приходит проверка «не уснул». */
    const val WAKE_CHECK_DELAY = 5 * 60_000L

    /** Сколько есть времени, чтобы подтвердить, что не спишь. */
    const val WAKE_CHECK_WINDOW = 60_000L
    const val WAKE_CHECK_SUFFIX = ".check"

    const val EMERGENCY_HOLD_SECONDS = 30
    const val EMERGENCY_LIMIT = 2
    const val EMERGENCY_PERIOD = 7 * 24 * 3600_000L

    /** За сколько до будильника ослабить настройки можно только через испытание. */
    const val LOCK_LEAD_TIME = 60 * 60_000L

    /** Сколько намазов можно выключить тумблером без испытания. */
    const val FREE_DISABLED_PRAYERS_LIMIT = 1

    // Проверка «не уснул»

    /** Проверка после выполненного задания. Для самой проверки повторная не создаётся — без бесконечного цикла. */
    fun wakeCheck(
        after: AlarmInstance,
        completedAt: Long,
    ): AlarmInstance? {
        if (after.isWakeCheck) return null
        val checkAt = completedAt + WAKE_CHECK_DELAY
        return AlarmInstance(
            id = after.id + WAKE_CHECK_SUFFIX,
            prayer = after.prayer,
            prayerTime = checkAt,
            alarmTime = checkAt + WAKE_CHECK_WINDOW,
            alarmEnabled = true,
        )
    }

    /** Проверка, которая ждёт ответа прямо сейчас. */
    fun pendingWakeCheck(
        checks: List<AlarmInstance>,
        dismissed: Set<String>,
        now: Long,
    ): AlarmInstance? = checks.firstOrNull { it.prayerTime <= now && now < it.alarmTime && it.id !in dismissed }

    /** Проверки, которые ещё могут сработать (не подтверждены и не истекли). */
    fun liveWakeChecks(
        checks: List<AlarmInstance>,
        dismissed: Set<String>,
        now: Long,
    ): List<AlarmInstance> = checks.filter { it.id !in dismissed && now < it.alarmTime + AlarmPlanner.MAX_RING_DURATION }

    // Аварийное отключение

    fun recentEmergencyUses(
        uses: List<Long>,
        now: Long,
    ): List<Long> = uses.filter { now - it < EMERGENCY_PERIOD }

    fun emergencyRemaining(
        uses: List<Long>,
        now: Long,
    ): Int = max(0, EMERGENCY_LIMIT - recentEmergencyUses(uses, now).size)

    /** Когда снова станет доступно аварийное отключение (если лимит исчерпан). */
    fun nextEmergencyDate(
        uses: List<Long>,
        now: Long,
    ): Long? {
        if (emergencyRemaining(uses, now) != 0) return null
        return recentEmergencyUses(uses, now).minOrNull()?.plus(EMERGENCY_PERIOD)
    }

    // Выключение будильника отдельных намазов

    /** true, если выключение будильника этого намаза превысит лимит и требует испытания. */
    fun disablingNeedsChallenge(
        prayer: Prayer,
        settings: AppSettings,
    ): Boolean {
        val othersOff = Prayer.entries.count { it != prayer && !settings.isAlarmEnabled(it) }
        return othersOff >= FREE_DISABLED_PRAYERS_LIMIT
    }

    // Блокировка ослабления настроек

    /**
     * true, если новые настройки позволяют будильнику зазвонить позже или выключиться проще.
     * Метод расчёта, мазхаб, место и поправки сдвигают время намаза — их смена всегда считается ослаблением.
     */
    fun weakens(
        new: AppSettings,
        old: AppSettings,
    ): Boolean {
        if (new.method != old.method || new.madhab != old.madhab || new.offsetMinutes != old.offsetMinutes) return true
        if (old.location != null && new.location != old.location) return true
        if (new.delayMinutes > old.delayMinutes) return true
        if (Prayer.entries.any { old.isAlarmEnabled(it) && !new.isAlarmEnabled(it) }) return true
        if (new.recitation == RecitationChoice.OFF && old.recitation != RecitationChoice.OFF) return true
        if (old.keepAlive && !new.keepAlive) return true
        if (old.wakeCheck && !new.wakeCheck) return true
        return false
    }

    /** true, если звонит будильник или до ближайшего меньше часа. */
    fun changesLocked(
        instances: List<AlarmInstance>,
        dismissed: Set<String>,
        isRinging: Boolean,
        now: Long,
    ): Boolean {
        if (isRinging) return true
        return instances.any {
            it.alarmEnabled && it.id !in dismissed && it.alarmTime > now && it.alarmTime - now <= LOCK_LEAD_TIME
        }
    }
}
