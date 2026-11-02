package com.prayforever.app.ui

import android.content.Context
import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.text.format.DateFormat
import androidx.annotation.StringRes
import com.prayforever.app.R
import com.prayforever.app.core.AlarmSound
import com.prayforever.app.core.CalculationMethodOption
import com.prayforever.app.core.MadhabOption
import com.prayforever.app.core.Prayer
import com.prayforever.app.core.RecitationChoice
import com.prayforever.app.core.StroopColor
import com.prayforever.app.core.Surah
import com.prayforever.app.core.TaskKind
import java.util.Date
import java.util.Locale

fun Context.prayerName(prayer: Prayer): String = getString(prayer.title)

/** Время по настройке 12/24 ч устройства. */
fun Context.formatTime(millis: Long): String = DateFormat.getTimeFormat(this).format(Date(millis))

fun Context.formatDateTime(millis: Long): String = "${DateFormat.getMediumDateFormat(this).format(Date(millis))}, ${formatTime(millis)}"

/** «через 2 ч 5 мин» / «через 40 с». */
fun Context.countdown(
    from: Long,
    to: Long,
): String {
    val seconds = maxOf(0L, (to - from) / 1000)
    val format = MeasureFormat.getInstance(Locale.getDefault(), MeasureFormat.FormatWidth.SHORT)
    val value =
        if (seconds < 60) {
            format.format(Measure(seconds, MeasureUnit.SECOND))
        } else {
            val minutes = (seconds + 59) / 60
            val hours = minutes / 60
            val parts =
                buildList {
                    if (hours > 0) add(Measure(hours, MeasureUnit.HOUR))
                    if (minutes % 60 > 0 || hours == 0L) add(Measure(minutes % 60, MeasureUnit.MINUTE))
                }
            format.formatMeasures(*parts.toTypedArray())
        }
    return getString(R.string.common_in, value)
}

val Context.isRussian: Boolean get() = resources.configuration.locales[0].language == "ru"

@get:StringRes
val Prayer.title: Int
    get() =
        when (this) {
            Prayer.FAJR -> R.string.prayer_fajr
            Prayer.DHUHR -> R.string.prayer_dhuhr
            Prayer.ASR -> R.string.prayer_asr
            Prayer.MAGHRIB -> R.string.prayer_maghrib
            Prayer.ISHA -> R.string.prayer_isha
        }

@get:StringRes
val CalculationMethodOption.title: Int
    get() =
        when (this) {
            CalculationMethodOption.RUSSIA -> R.string.method_russia
            CalculationMethodOption.MUSLIM_WORLD_LEAGUE -> R.string.method_muslimWorldLeague
            CalculationMethodOption.EGYPTIAN -> R.string.method_egyptian
            CalculationMethodOption.KARACHI -> R.string.method_karachi
            CalculationMethodOption.UMM_AL_QURA -> R.string.method_ummAlQura
            CalculationMethodOption.DUBAI -> R.string.method_dubai
            CalculationMethodOption.MOONSIGHTING_COMMITTEE -> R.string.method_moonsightingCommittee
            CalculationMethodOption.NORTH_AMERICA -> R.string.method_northAmerica
            CalculationMethodOption.KUWAIT -> R.string.method_kuwait
            CalculationMethodOption.QATAR -> R.string.method_qatar
            CalculationMethodOption.SINGAPORE -> R.string.method_singapore
            CalculationMethodOption.TURKEY -> R.string.method_turkey
            CalculationMethodOption.TEHRAN -> R.string.method_tehran
        }

@get:StringRes
val MadhabOption.title: Int
    get() =
        when (this) {
            MadhabOption.SHAFI -> R.string.madhab_shafi
            MadhabOption.HANAFI -> R.string.madhab_hanafi
        }

@get:StringRes
val TaskKind.title: Int
    get() =
        when (this) {
            TaskKind.RUG -> R.string.task_rug
            TaskKind.SINK -> R.string.task_sink
            TaskKind.ANY -> R.string.task_any
        }

@get:StringRes
val TaskKind.instruction: Int
    get() =
        when (this) {
            TaskKind.RUG -> R.string.task_rug_instruction
            TaskKind.SINK -> R.string.task_sink_instruction
            TaskKind.ANY -> R.string.task_any_instruction
        }

@get:StringRes
val AlarmSound.title: Int
    get() =
        when (this) {
            AlarmSound.PULSE -> R.string.sound_pulse
            AlarmSound.BELL -> R.string.sound_bell
            AlarmSound.SIREN -> R.string.sound_siren
            AlarmSound.CLOCK -> R.string.sound_clock
            AlarmSound.SMOKE -> R.string.sound_smoke
            AlarmSound.KLAXON -> R.string.sound_klaxon
            AlarmSound.HILO -> R.string.sound_hilo
            AlarmSound.GLITCH -> R.string.sound_glitch
            AlarmSound.BUZZER -> R.string.sound_buzzer
        }

@get:StringRes
val Surah.title: Int
    get() =
        when (this) {
            Surah.FATIHA -> R.string.surah_fatiha
            Surah.IKHLAS -> R.string.surah_ikhlas
            Surah.FALAQ -> R.string.surah_falaq
            Surah.NAS -> R.string.surah_nas
            Surah.KAWTHAR -> R.string.surah_kawthar
            Surah.ASR -> R.string.surah_asr
            Surah.KAFIRUN -> R.string.surah_kafirun
        }

@get:StringRes
val RecitationChoice.title: Int
    get() =
        when (this) {
            RecitationChoice.OFF -> R.string.recitation_off
            RecitationChoice.RANDOM -> R.string.recitation_random
            else -> surah!!.title
        }

@get:StringRes
val StroopColor.title: Int
    get() =
        when (this) {
            StroopColor.RED -> R.string.color_red
            StroopColor.GREEN -> R.string.color_green
            StroopColor.BLUE -> R.string.color_blue
            StroopColor.YELLOW -> R.string.color_yellow
            StroopColor.PURPLE -> R.string.color_purple
            StroopColor.ORANGE -> R.string.color_orange
        }

/** Длительности паузы (часы) и их подписи. */
val PAUSE_DURATIONS: List<Pair<Int, Int>> =
    listOf(
        1 to R.string.pause_duration_1,
        3 to R.string.pause_duration_3,
        12 to R.string.pause_duration_12,
        24 to R.string.pause_duration_24,
        72 to R.string.pause_duration_72,
        168 to R.string.pause_duration_168,
    )
