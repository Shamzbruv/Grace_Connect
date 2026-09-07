package love.graceconnect.attendance

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AttendanceRefreshScheduleTest {
    @Test
    fun `refreshing the app does not postpone the nearest weekly service`() {
        val now = 1_783_257_000_000L
        val service = now + 1_800_000
        assertEquals(listOf(service), AttendanceRefreshSchedule.normalize(
            listOf(service + AttendanceRefreshSchedule.weekMillis, service), now))
        assertEquals(listOf(service), AttendanceRefreshSchedule.normalize(
            listOf(service, service + AttendanceRefreshSchedule.weekMillis), now + 600_000))
    }

    @Test
    fun `delayed background execution skips missed weeks and retains wall clock time`() {
        val service = 1_783_258_800_000L
        val week = AttendanceRefreshSchedule.weekMillis
        val next = AttendanceRefreshSchedule.nextOccurrence(
            AttendanceRefreshSchedule.slot(service), service + week * 3 + 300_000)
        assertEquals(service + week * 4, next)
        assertEquals(AttendanceRefreshSchedule.slot(service), AttendanceRefreshSchedule.slot(next))
    }

    @Test
    fun `distinct service windows survive deduplication and old dates are rejected`() {
        val now = 1_783_257_000_000L
        val first = now + 1_800_000
        val second = first + 600_000
        assertEquals(listOf(first, second), AttendanceRefreshSchedule.normalize(
            listOf(second, now - 1, first, first), now))
        assertTrue(AttendanceRefreshSchedule.normalize(emptyList(), now).isEmpty())
    }
}
