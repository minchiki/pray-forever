package com.prayforever.app.core

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class PrayerTimeTest {
    private val moscow = ZoneId.of("Europe/Moscow")
    private val calc = PrayerTimeCalculator(moscow)
    private val kazan = AppSettings(location = SavedLocation(55.79, 49.12, "Kazan"))

    @Test
    fun fivePrayersInOrder() {
        val times = calc.times(LocalDate.of(2026, 3, 15), kazan)!!
        val ordered = Prayer.entries.map { times.getValue(it) }
        assertEquals(ordered.sorted(), ordered)
    }

    @Test
    fun summerHighLatitudeStillProducesTimes() {
        assertEquals(5, calc.times(LocalDate.of(2026, 6, 21), kazan)?.size)
    }

    @Test
    fun everyMethodProducesOrderedTimes() {
        for (method in CalculationMethodOption.entries) {
            for (madhab in MadhabOption.entries) {
                val times = calc.times(LocalDate.of(2026, 3, 15), kazan.copy(method = method, madhab = madhab))
                assertNotNull("$method $madhab", times)
                val ordered = Prayer.entries.map { times!!.getValue(it) }
                assertEquals("$method $madhab", ordered.sorted(), ordered)
            }
        }
    }

    @Test
    fun tehranMaghribIsAfterSunsetByTwilightAngle() {
        val tehranZone = PrayerTimeCalculator(ZoneId.of("Asia/Tehran"))
        val tehran = AppSettings(location = SavedLocation(35.69, 51.39))
        val day = LocalDate.of(2026, 3, 21)

        val standard = tehranZone.times(day, tehran.copy(method = CalculationMethodOption.KARACHI))!!
        val tehranTimes = tehranZone.times(day, tehran.copy(method = CalculationMethodOption.TEHRAN))!!
        val minutesAfterSunset = (tehranTimes.getValue(Prayer.MAGHRIB) - standard.getValue(Prayer.MAGHRIB)) / 60_000.0

        assertTrue("got $minutesAfterSunset", minutesAfterSunset in 12.0..25.0)
    }

    @Test
    fun manualOffsetIsApplied() {
        val day = LocalDate.of(2026, 3, 15)
        val base = calc.times(day, kazan)!!
        val shifted = calc.times(day, kazan.copy(offsetMinutes = mapOf("asr" to 7)))!!

        assertEquals(7 * 60_000L, shifted.getValue(Prayer.ASR) - base.getValue(Prayer.ASR))
        assertEquals(base[Prayer.FAJR], shifted[Prayer.FAJR])
    }

    @Test
    fun instancesUseDelayAndAreSorted() {
        val settings = kazan.copy(delayMinutes = 9, alarmEnabled = kazan.alarmEnabled + ("isha" to false))
        val now =
            LocalDate
                .of(2026, 3, 15)
                .atTime(12, 0)
                .atZone(moscow)
                .toInstant()
                .toEpochMilli()

        val list = calc.instances(now, days = 2, settings = settings)

        assertTrue(list.isNotEmpty())
        assertEquals(list.map { it.prayerTime }.sorted(), list.map { it.prayerTime })
        assertTrue(list.all { it.alarmTime - it.prayerTime == 9 * 60_000L })
        assertTrue(list.filter { it.prayer == Prayer.ISHA }.none { it.alarmEnabled })
    }

    @Test
    fun noLocationGivesNoTimes() {
        assertNull(calc.times(LocalDate.of(2026, 3, 15), AppSettings()))
    }

    @Test
    fun instanceIdFormat() {
        assertEquals("2026-01-05-asr", AlarmInstance.makeId(Prayer.ASR, LocalDate.of(2026, 1, 5)))
    }
}

class AppSettingsTest {
    private val json =
        Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
        }

    @Test
    fun decodingOldDataFallsBackToDefaults() {
        val settings = json.decodeFromString(AppSettings.serializer(), """{"delayMinutes": 12, "method": "unknownMethod"}""")

        assertEquals(12, settings.delayMinutes)
        assertEquals(AppSettings().method, settings.method)
        assertTrue(settings.keepAlive)
        assertTrue(settings.isAlarmEnabled(Prayer.FAJR))
        assertEquals(RecitationChoice.FATIHA, settings.recitation)
    }

    @Test
    fun roundTrip() {
        val original = AppSettings(task = TaskKind.SINK, sound = AlarmSound.SIREN, offsetMinutes = mapOf("fajr" to -3))
        assertEquals(original, json.decodeFromString(AppSettings.serializer(), json.encodeToString(AppSettings.serializer(), original)))
    }

    @Test
    fun sanitizedClampsRanges() {
        val settings = AppSettings(delayMinutes = 500, offsetMinutes = mapOf("asr" to -99)).sanitized()
        assertEquals(60, settings.delayMinutes)
        assertEquals(-30, settings.offset(Prayer.ASR))
    }
}

class CoordinateParserTest {
    @Test
    fun parsesDotAndCommaDecimals() {
        val parsed = CoordinateParser.parse("55,7961", " 49.1064 ")!!
        assertEquals(55.7961, parsed.first, 0.00001)
        assertEquals(49.1064, parsed.second, 0.00001)
    }

    @Test
    fun rejectsOutOfRangeAndGarbage() {
        assertNull(CoordinateParser.parse("91", "10"))
        assertNull(CoordinateParser.parse("10", "-181"))
        assertNull(CoordinateParser.parse("abc", "10"))
        assertNull(CoordinateParser.parse("NaN", "10"))
    }
}
