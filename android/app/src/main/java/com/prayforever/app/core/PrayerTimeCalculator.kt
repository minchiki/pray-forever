package com.prayforever.app.core

import com.batoulapps.adhan.CalculationMethod
import com.batoulapps.adhan.CalculationParameters
import com.batoulapps.adhan.Coordinates
import com.batoulapps.adhan.HighLatitudeRule
import com.batoulapps.adhan.Madhab
import com.batoulapps.adhan.PrayerAdjustments
import com.batoulapps.adhan.PrayerTimes
import com.batoulapps.adhan.data.DateComponents
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.sin

/** Расчёт времени намаза (библиотека Adhan) + ручные поправки пользователя. */
class PrayerTimeCalculator(
    private val zone: ZoneId = ZoneId.systemDefault(),
) {
    fun times(
        day: LocalDate,
        settings: AppSettings,
    ): Map<Prayer, Long>? {
        val location = settings.location ?: return null
        val coordinates = Coordinates(location.latitude, location.longitude)
        val params = parameters(settings, location.latitude)
        val pt =
            runCatching {
                PrayerTimes(coordinates, DateComponents(day.year, day.monthValue, day.dayOfMonth), params)
            }.getOrNull() ?: return null
        val maghrib =
            if (settings.method == CalculationMethodOption.TEHRAN) {
                SolarAngle
                    .timeBelowHorizon(day, location.latitude, location.longitude, TEHRAN_MAGHRIB_ANGLE)
                    ?.takeIf { it > pt.maghrib.time } ?: pt.maghrib.time
            } else {
                pt.maghrib.time
            }
        val raw =
            mapOf(
                Prayer.FAJR to pt.fajr.time,
                Prayer.DHUHR to pt.dhuhr.time,
                Prayer.ASR to pt.asr.time,
                Prayer.MAGHRIB to maghrib,
                Prayer.ISHA to pt.isha.time,
            )
        // Adhan-Java оставляет миллисекундный шум; как и Adhan для Swift, время округляется до минуты.
        return raw.mapValues { (prayer, time) -> roundToMinute(time) + settings.offset(prayer) * 60_000L }
    }

    /** Все срабатывания начиная с [now] (включая ещё звонящее окно) на [days] дней вперёд. */
    fun instances(
        now: Long,
        days: Int,
        settings: AppSettings,
        lookBack: Long = 0,
    ): List<AlarmInstance> {
        val today =
            java.time.Instant
                .ofEpochMilli(now)
                .atZone(zone)
                .toLocalDate()
        val delay = settings.delayMinutes * 60_000L
        val all =
            (-1 until days).flatMap { offset ->
                val day = today.plusDays(offset.toLong())
                val times = times(day, settings) ?: return@flatMap emptyList()
                Prayer.entries.mapNotNull { prayer ->
                    val time = times[prayer] ?: return@mapNotNull null
                    AlarmInstance(
                        id = AlarmInstance.makeId(prayer, day),
                        prayer = prayer,
                        prayerTime = time,
                        alarmTime = time + delay,
                        alarmEnabled = settings.isAlarmEnabled(prayer),
                    )
                }
            }
        val cutoff = now - lookBack
        return all.filter { it.alarmTime >= cutoff || it.prayerTime >= cutoff }.sortedBy { it.prayerTime }
    }

    private fun roundToMinute(time: Long): Long = Math.round(time / 60_000.0) * 60_000L

    companion object {
        /** Выше этой широты используется правило «седьмой части ночи» — иначе летом в России Иша/Фаджр не вычисляются. */
        const val HIGH_LATITUDE_THRESHOLD = 48.0

        /** Метод Тегерана считает Магриб по углу 4.5° под горизонтом (в Adhan-Java такого параметра нет). */
        const val TEHRAN_MAGHRIB_ANGLE = 4.5

        fun parameters(
            settings: AppSettings,
            latitude: Double,
        ): CalculationParameters {
            val params =
                when (settings.method) {
                    // ДУМ РФ: Фаджр 16°, Иша 15°
                    CalculationMethodOption.RUSSIA -> CalculationParameters(16.0, 15.0, CalculationMethod.OTHER)
                    CalculationMethodOption.MUSLIM_WORLD_LEAGUE -> CalculationMethod.MUSLIM_WORLD_LEAGUE.parameters
                    CalculationMethodOption.EGYPTIAN -> CalculationMethod.EGYPTIAN.parameters
                    CalculationMethodOption.KARACHI -> CalculationMethod.KARACHI.parameters
                    CalculationMethodOption.UMM_AL_QURA -> CalculationMethod.UMM_AL_QURA.parameters
                    CalculationMethodOption.DUBAI -> CalculationMethod.DUBAI.parameters
                    CalculationMethodOption.MOONSIGHTING_COMMITTEE -> CalculationMethod.MOON_SIGHTING_COMMITTEE.parameters
                    CalculationMethodOption.NORTH_AMERICA -> CalculationMethod.NORTH_AMERICA.parameters
                    CalculationMethodOption.KUWAIT -> CalculationMethod.KUWAIT.parameters
                    CalculationMethodOption.QATAR -> CalculationMethod.QATAR.parameters
                    CalculationMethodOption.SINGAPORE -> CalculationMethod.SINGAPORE.parameters
                    // Диянет: 18° / 17° и поправки метода, как в Adhan для Swift.
                    CalculationMethodOption.TURKEY ->
                        CalculationParameters(18.0, 17.0, CalculationMethod.OTHER)
                            .withMethodAdjustments(PrayerAdjustments(0, -7, 5, 4, 7, 0))
                    CalculationMethodOption.TEHRAN -> CalculationParameters(17.7, 14.0, CalculationMethod.OTHER)
                }
            params.madhab = if (settings.madhab == MadhabOption.HANAFI) Madhab.HANAFI else Madhab.SHAFI
            params.highLatitudeRule =
                if (abs(latitude) > HIGH_LATITUDE_THRESHOLD) {
                    HighLatitudeRule.SEVENTH_OF_THE_NIGHT
                } else {
                    HighLatitudeRule.MIDDLE_OF_THE_NIGHT
                }
            return params
        }
    }
}

/** Момент вечером, когда центр солнца опускается на [angle] градусов под горизонт (формулы NOAA). */
internal object SolarAngle {
    fun timeBelowHorizon(
        day: LocalDate,
        latitude: Double,
        longitude: Double,
        angle: Double,
    ): Long? {
        val n = day.dayOfYear
        val gamma = 2 * Math.PI / 365 * (n - 1)
        val equationOfTime =
            229.18 * (
                0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) -
                    0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma)
            )
        val declination =
            0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) +
                0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        val lat = Math.toRadians(latitude)
        val cosHourAngle =
            (sin(Math.toRadians(-angle)) - sin(lat) * sin(declination)) / (cos(lat) * cos(declination))
        if (cosHourAngle !in -1.0..1.0) return null
        val hourAngle = Math.toDegrees(acos(cosHourAngle))
        val minutesUtc = 720 - 4 * longitude - equationOfTime + 4 * hourAngle
        val midnightUtc = day.atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli()
        return midnightUtc + (minutesUtc * 60_000).toLong()
    }
}
