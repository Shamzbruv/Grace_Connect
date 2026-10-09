package love.graceconnect

import org.junit.Assert.assertEquals
import org.junit.Test

class DailyWordWidgetTest {
    @Test fun countsDoNotRoundIntoTheNextMilestoneEarly() {
        val cases = mapOf(-1L to "0", 999L to "999", 1000L to "1K", 1200L to "1.2K",
            999999L to "999.9K", 1000000L to "1M", 1250000L to "1.2M", 1000000000L to "1B")
        cases.forEach { (value, expected) -> assertEquals(expected, CompactLikeCount.format(value)) }
    }

    @Test fun everyWidgetAndShortcutHasAnIndependentPendingIntent() {
        val ids = (1..1000).flatMap { id -> (0..3).map { action -> DailyWidgetIntent.requestCode(id, action) } }
        assertEquals(4000, ids.toSet().size)
    }
}
