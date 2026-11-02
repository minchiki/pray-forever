package com.prayforever.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlarmPolicyTest {
    private val now = 1_800_000_000_000L
    private val day = 24 * 3600_000L

    private fun instance(
        id: String,
        alarmInMinutes: Double,
        enabled: Boolean = true,
    ): AlarmInstance {
        val alarm = now + (alarmInMinutes * 60_000).toLong()
        return AlarmInstance(id, Prayer.ASR, alarm - 300_000, alarm, enabled)
    }

    @Test
    fun wakeCheckIsScheduledFiveMinutesLaterWithOneMinuteWindow() {
        val check = AlarmPolicy.wakeCheck(instance("2026-10-16-asr", 0.0), completedAt = now)!!

        assertTrue(check.isWakeCheck)
        assertEquals(AlarmPolicy.WAKE_CHECK_DELAY, check.prayerTime - now)
        assertEquals(AlarmPolicy.WAKE_CHECK_WINDOW, check.alarmTime - check.prayerTime)
        assertTrue(check.alarmEnabled)
    }

    @Test
    fun noWakeCheckAfterWakeCheck() {
        val check = AlarmPolicy.wakeCheck(instance("a", 0.0), now)!!
        assertNull(AlarmPolicy.wakeCheck(check, now))
    }

    @Test
    fun pendingWakeCheckOnlyInsideWindow() {
        val check = AlarmPolicy.wakeCheck(instance("a", 0.0), now)!!
        val inside = check.prayerTime + 10_000

        assertNull(AlarmPolicy.pendingWakeCheck(listOf(check), emptySet(), now))
        assertEquals(check.id, AlarmPolicy.pendingWakeCheck(listOf(check), emptySet(), inside)?.id)
        assertNull(AlarmPolicy.pendingWakeCheck(listOf(check), setOf(check.id), inside))
        assertNull(AlarmPolicy.pendingWakeCheck(listOf(check), emptySet(), check.alarmTime))
    }

    @Test
    fun missedWakeCheckBecomesDueAlarm() {
        val check = AlarmPolicy.wakeCheck(instance("a", 0.0), now)!!
        assertEquals(check.id, AlarmPlanner.dueInstance(listOf(check), emptySet(), check.alarmTime + 1000)?.id)
    }

    @Test
    fun emergencyLimitIsTwoPerWeek() {
        val uses = listOf(now - 2 * day, now - day)

        assertEquals(2, AlarmPolicy.emergencyRemaining(emptyList(), now))
        assertEquals(0, AlarmPolicy.emergencyRemaining(uses, now))
        assertEquals(uses[0] + 7 * day, AlarmPolicy.nextEmergencyDate(uses, now))
        assertEquals(1, AlarmPolicy.emergencyRemaining(uses, now + (5.5 * day).toLong()))
    }

    @Test
    fun firstPrayerCanBeDisabledWithoutChallenge() {
        assertFalse(AlarmPolicy.disablingNeedsChallenge(Prayer.ISHA, AppSettings()))
    }

    @Test
    fun secondDisabledPrayerNeedsChallenge() {
        val settings = AppSettings(alarmEnabled = AppSettings().alarmEnabled + ("fajr" to false))
        assertTrue(AlarmPolicy.disablingNeedsChallenge(Prayer.ISHA, settings))
        assertFalse(AlarmPolicy.disablingNeedsChallenge(Prayer.FAJR, settings))
    }

    @Test
    fun shiftingPrayerTimesWeakensAlarm() {
        val base = AppSettings(location = SavedLocation(55.79, 49.11, "Kazan"))

        assertTrue(AlarmPolicy.weakens(base.copy(madhab = MadhabOption.SHAFI), base))
        assertTrue(AlarmPolicy.weakens(base.copy(method = CalculationMethodOption.TURKEY), base))
        assertTrue(AlarmPolicy.weakens(base.copy(offsetMinutes = mapOf("fajr" to -5)), base))
        assertTrue(AlarmPolicy.weakens(base.copy(location = SavedLocation(43.1, 131.9)), base))
        assertFalse(AlarmPolicy.weakens(base.copy(location = SavedLocation(55.79, 49.11)), AppSettings()))
    }

    @Test
    fun onlyLooseningChangesWeakenAlarm() {
        val base = AppSettings()

        assertTrue(AlarmPolicy.weakens(base.copy(delayMinutes = 6), base))
        assertFalse(AlarmPolicy.weakens(base.copy(delayMinutes = 4), base))
        assertTrue(AlarmPolicy.weakens(base.copy(alarmEnabled = base.alarmEnabled + ("isha" to false)), base))
        assertTrue(AlarmPolicy.weakens(base.copy(recitation = RecitationChoice.OFF), base))
        assertFalse(AlarmPolicy.weakens(base.copy(recitation = RecitationChoice.RANDOM), base))
        assertTrue(AlarmPolicy.weakens(base.copy(keepAlive = false), base))
        assertTrue(AlarmPolicy.weakens(base.copy(wakeCheck = false), base))
        assertFalse(AlarmPolicy.weakens(base.copy(sound = AlarmSound.SIREN), base))
        assertFalse(AlarmPolicy.weakens(base.copy(task = TaskKind.RUG), base))
    }

    @Test
    fun changesLockedWithinHourBeforeAlarm() {
        assertTrue(AlarmPolicy.changesLocked(listOf(instance("a", 30.0)), emptySet(), false, now))
        assertFalse(AlarmPolicy.changesLocked(listOf(instance("a", 90.0)), emptySet(), false, now))
        assertFalse(AlarmPolicy.changesLocked(listOf(instance("a", 30.0, enabled = false)), emptySet(), false, now))
        assertFalse(AlarmPolicy.changesLocked(listOf(instance("a", 30.0)), setOf("a"), false, now))
        assertTrue(AlarmPolicy.changesLocked(emptyList(), emptySet(), true, now))
    }

    @Test
    fun activePauseExpires() {
        val settings = AppSettings(pausedUntil = now + 60_000)
        assertNotNull(settings.activePause(now))
        assertNull(settings.activePause(now + 61_000))
    }
}
