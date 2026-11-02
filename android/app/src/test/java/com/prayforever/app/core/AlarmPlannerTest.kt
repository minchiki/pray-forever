package com.prayforever.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlarmPlannerTest {
    private val now = 1_800_000_000_000L

    private fun instance(
        id: String,
        minutesFromNow: Long,
        delay: Long = 5,
        enabled: Boolean = true,
    ): AlarmInstance {
        val time = now + minutesFromNow * 60_000
        return AlarmInstance(id, Prayer.DHUHR, time, time + delay * 60_000, enabled)
    }

    @Test
    fun prayerTimeAndAlarmEventsAreSortedAndUnique() {
        val list = (0 until 20).map { instance("i$it", 60L + it * 180) }

        val plan = AlarmPlanner.plan(list, emptySet(), notifyAtPrayerTime = true, pauseEnd = null, now = now)

        assertTrue(plan.size <= AlarmPlanner.MAX_EVENTS)
        assertEquals(plan.map { it.at }.sorted(), plan.map { it.at })
        assertEquals(plan.size, plan.map { it.requestCode }.toSet().size)
    }

    @Test
    fun dismissedAndDisabledInstancesGetNoAlarm() {
        val plan =
            AlarmPlanner.plan(
                listOf(instance("d", 10), instance("x", 200, enabled = false)),
                dismissed = setOf("d"),
                notifyAtPrayerTime = true,
                pauseEnd = null,
                now = now,
            )

        assertTrue(plan.all { it.kind == AlarmPlanner.Kind.PRAYER_TIME })
        assertEquals(2, plan.size)
    }

    @Test
    fun noPrayerTimeNotificationWhenDisabledExceptWakeCheck() {
        val check = AlarmPolicy.wakeCheck(instance("a", -10), now)!!

        val plan = AlarmPlanner.plan(listOf(instance("b", 10), check), emptySet(), false, null, now)

        assertEquals(listOf(check.id), plan.filter { it.kind == AlarmPlanner.Kind.PRAYER_TIME }.map { it.instanceId })
        assertEquals(2, plan.count { it.kind == AlarmPlanner.Kind.ALARM })
    }

    @Test
    fun nothingIsPlannedDuringPauseExceptItsEnd() {
        val pauseEnd = now + 120 * 60_000
        val plan =
            AlarmPlanner.plan(listOf(instance("a", 30), instance("b", 300)), emptySet(), true, pauseEnd, now)

        assertEquals(AlarmPlanner.Kind.PAUSE_END, plan.first().kind)
        assertTrue(plan.drop(1).all { it.instanceId == "b" })
    }

    @Test
    fun dueInstanceWithinRingWindow() {
        val ringing = instance("r", -10)
        val future = instance("f", 30)
        val expired = instance("e", -200)

        assertEquals("r", AlarmPlanner.dueInstance(listOf(expired, ringing, future), emptySet(), now)?.id)
        assertNull(AlarmPlanner.dueInstance(listOf(ringing), setOf("r"), now))
        assertNull(AlarmPlanner.dueInstance(listOf(future, expired), emptySet(), now))
    }
}
