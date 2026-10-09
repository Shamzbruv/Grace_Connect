package love.graceconnect

import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class DailyGraceDateTest {
    @Test fun calendarSelectionDoesNotSkipOnLeapOrDaylightSavingDays() {
        for (day in listOf("2024-02-28", "2024-02-29", "2026-03-08", "2026-11-01")) {
            val date = LocalDate.parse(day)
            assertEquals((DailyGraceDate.index(date, 31) + 1) % 31, DailyGraceDate.index(date.plusDays(1), 31))
        }
        assertEquals(0, DailyGraceDate.index(LocalDate.of(1970, 1, 1), 31))
        assertEquals(30, DailyGraceDate.index(LocalDate.of(1969, 12, 31), 31))
    }

    @Test fun usesThePhonesCalendarDayInEveryTimeZone() {
        val moment = ZonedDateTime.parse("2026-10-09T02:00:00Z")
        assertEquals(DailyGraceDate.index(LocalDate.of(2026, 10, 8), 31),
            DailyGraceDate.index(moment.withZoneSameInstant(ZoneId.of("America/Jamaica")).toLocalDate(), 31))
        assertEquals(DailyGraceDate.index(LocalDate.of(2026, 10, 9), 31),
            DailyGraceDate.index(moment.withZoneSameInstant(ZoneId.of("Asia/Tokyo")).toLocalDate(), 31))
    }
}
