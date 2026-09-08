package love.graceconnect.attendance

import java.util.concurrent.TimeUnit

/** Absolute weekly slots: recomputing a relative initial delay must not move existing work. */
internal object AttendanceRefreshSchedule {
    val weekMillis: Long = TimeUnit.DAYS.toMillis(7)

    fun slot(epochMillis: Long): Long = Math.floorMod(epochMillis, weekMillis)

    fun normalize(epochsMillis: List<Long>, now: Long): List<Long> = epochsMillis
        .asSequence()
        .filter { it > now + 10_000 }
        .distinct()
        .sorted()
        .distinctBy(::slot)
        .take(64)
        .toList()

    fun nextOccurrence(slot: Long, now: Long): Long {
        val thisWeek = now - Math.floorMod(now, weekMillis) + slot
        return if (thisWeek > now + 10_000) thisWeek else thisWeek + weekMillis
    }
}
