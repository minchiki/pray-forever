package com.prayforever.app.core

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.util.Locale

@Serializable
enum class Prayer(
    val key: String,
) {
    FAJR("fajr"),
    DHUHR("dhuhr"),
    ASR("asr"),
    MAGHRIB("maghrib"),
    ISHA("isha"),
    ;

    companion object {
        fun fromKey(key: String): Prayer? = entries.firstOrNull { it.key == key }
    }
}

/** Одно конкретное срабатывание: намаз в конкретный день. Время — миллисекунды Unix. */
@Serializable
data class AlarmInstance(
    /** Например "2026-10-16-dhuhr" или "test-1760600000". */
    val id: String,
    val prayer: Prayer,
    val prayerTime: Long,
    val alarmTime: Long,
    val alarmEnabled: Boolean,
) {
    val isTest: Boolean get() = id.startsWith("test-")
    val isWakeCheck: Boolean get() = id.endsWith(AlarmPolicy.WAKE_CHECK_SUFFIX)

    companion object {
        fun makeId(
            prayer: Prayer,
            day: LocalDate,
        ): String = String.format(Locale.ROOT, "%04d-%02d-%02d-%s", day.year, day.monthValue, day.dayOfMonth, prayer.key)

        fun test(now: Long): AlarmInstance =
            AlarmInstance(
                id = "test-${now / 1000}",
                prayer = Prayer.DHUHR,
                prayerTime = now,
                alarmTime = now,
                alarmEnabled = true,
            )
    }
}
