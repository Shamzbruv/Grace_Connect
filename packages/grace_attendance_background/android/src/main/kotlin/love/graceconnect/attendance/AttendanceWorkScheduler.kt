package love.graceconnect.attendance

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

object AttendanceWorkScheduler {
    private val schedulingScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val schedulingLock = Mutex()
    private const val PREFS = "grace_attendance_background_v1"
    private const val ENABLED = "enabled"
    private const val REMINDERS_ENABLED = "reminders_enabled"
    private const val REMINDER_REFRESH = "grace_attendance_reminder_refresh"
    private const val WINDOW_SLOTS = "window_slots"
    private const val ALL_TAG = "grace_attendance_background"
    private const val WINDOW_TAG_PREFIX = "grace_attendance_window_"
    private const val CHECK_TAG_PREFIX = "grace_attendance_check_"
    private const val DUE_TAG_PREFIX = "grace_attendance_due_"
    const val WINDOW_SLOT_INPUT = "window_slot"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(ENABLED, false)

    fun remindersEnabled(context: Context): Boolean = prefs(context).getBoolean(REMINDERS_ENABLED, false)

    fun configureReminders(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(REMINDERS_ENABLED, enabled).apply()
        val manager = WorkManager.getInstance(context)
        if (enabled) {
            // No location permission is needed to keep manual sign-in reminders
            // current. KEEP preserves cadence when screens initialize again.
            manager.enqueueUniquePeriodicWork(REMINDER_REFRESH,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<AttendanceCheckWorker>(1, TimeUnit.DAYS)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .addTag(REMINDER_REFRESH).build())
        } else {
            manager.cancelUniqueWork(REMINDER_REFRESH)
        }
    }

    @Synchronized
    fun configureWindows(context: Context, epochsMillis: List<Long>) {
        val now = System.currentTimeMillis()
        val epochs = AttendanceRefreshSchedule.normalize(epochsMillis, now)
        if (epochs.isEmpty()) {
            cancelAll(context)
            return
        }
        val manager = WorkManager.getInstance(context)
        val preferences = prefs(context)
        val oldSlots = preferences.getStringSet(WINDOW_SLOTS, emptySet()).orEmpty().toSet()
        val newSlots = epochs.map { AttendanceRefreshSchedule.slot(it).toString() }.toSet()
        preferences.edit().putBoolean(ENABLED, true).putStringSet(WINDOW_SLOTS, newSlots).apply()
        // Cancel the old periodic implementation. Its UPDATE policy combined
        // a new relative delay with the old enqueue time, moving the wake time.
        manager.cancelAllWorkByTag("attendance_geofence_refresh_")
        for (obsolete in oldSlots - newSlots) manager.cancelAllWorkByTag("$WINDOW_TAG_PREFIX$obsolete")
        for (epoch in epochs) enqueueWindow(context, epoch)
        AttendanceCallbackRecoveryWorker.enqueue(context)
    }

    private fun enqueueWindow(context: Context, epoch: Long) {
        val slot = AttendanceRefreshSchedule.slot(epoch)
        val request = OneTimeWorkRequestBuilder<AttendanceCheckWorker>()
            .setInputData(Data.Builder().putLong(WINDOW_SLOT_INPUT, slot).build())
            .setInitialDelay((epoch - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(ALL_TAG)
            .addTag("$WINDOW_TAG_PREFIX$slot")
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork("${WINDOW_TAG_PREFIX}${epoch}", ExistingWorkPolicy.KEEP, request)
    }

    fun advanceWindow(context: Context, slot: Long): Boolean {
        if (!isEnabled(context) || !prefs(context).getStringSet(WINDOW_SLOTS, emptySet()).orEmpty().contains(slot.toString())) return false
        enqueueWindow(context, AttendanceRefreshSchedule.nextOccurrence(slot, System.currentTimeMillis()))
        return true
    }

    fun scheduleCheck(context: Context, epoch: Long, key: String, completed: (Boolean) -> Unit = {}) {
        schedulingScope.launch {
            val success = try {
                schedulingLock.withLock {
                    val now = System.currentTimeMillis()
                    if (!isEnabled(context) || epoch > now + TimeUnit.HOURS.toMillis(8)) return@withLock false
                    val manager = WorkManager.getInstance(context)
                    val tag = keyTag(key)
                    val pending = manager.getWorkInfosByTag(tag).get()
                        .filter { !it.state.isFinished && it.state != WorkInfo.State.RUNNING }
                    // Window checks and a dwell callback may both request the
                    // next observation. Keep only the earliest pending wake,
                    // while allowing the current worker to finish normally.
                    val earliestDue = pending.mapNotNull { work ->
                        work.tags.firstOrNull { it.startsWith(DUE_TAG_PREFIX) }
                            ?.removePrefix(DUE_TAG_PREFIX)?.toLongOrNull()
                    }.minOrNull()
                    if (earliestDue != null && earliestDue <= epoch) return@withLock true
                    val request = OneTimeWorkRequestBuilder<AttendanceCheckWorker>()
                        .setInitialDelay((epoch - now).coerceAtLeast(0), TimeUnit.MILLISECONDS)
                        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                        .addTag(ALL_TAG).addTag(tag).addTag("$DUE_TAG_PREFIX$epoch")
                        .build()
                    manager.enqueueUniqueWork("${tag}_${epoch}", ExistingWorkPolicy.KEEP, request).result.get()
                    for (previous in pending) {
                        val current = manager.getWorkInfoById(previous.id).get()
                        if (current != null && !current.state.isFinished && current.state != WorkInfo.State.RUNNING) {
                            manager.cancelWorkById(previous.id).result.get()
                        }
                    }
                    true
                }
            } catch (_: Exception) {
                false
            }
            withContext(Dispatchers.Main) { completed(success) }
        }
    }

    fun cancelCheck(context: Context, key: String, completed: () -> Unit = {}) {
        schedulingScope.launch {
            schedulingLock.withLock {
                val manager = WorkManager.getInstance(context)
                // Never destroy the engine that has just saved attendance and
                // is acknowledging completion of its current observation.
                try {
                    for (work in manager.getWorkInfosByTag(keyTag(key)).get()) {
                        if (!work.state.isFinished && work.state != WorkInfo.State.RUNNING) {
                            manager.cancelWorkById(work.id).result.get()
                        }
                    }
                } catch (_: Exception) {
                    // A remaining check re-reads attendance and exits idempotently.
                }
            }
            withContext(Dispatchers.Main) { completed() }
        }
    }

    @Synchronized
    fun cancelAll(context: Context) {
        prefs(context).edit().putBoolean(ENABLED, false).remove(WINDOW_SLOTS).apply()
        WorkManager.getInstance(context).cancelAllWorkByTag(ALL_TAG)
        WorkManager.getInstance(context).cancelAllWorkByTag("attendance_geofence_refresh_")
    }

    fun recover(context: Context) {
        migrateLegacyPlan(context)
        if (!isEnabled(context)) return
        val now = System.currentTimeMillis()
        prefs(context).getStringSet(WINDOW_SLOTS, emptySet()).orEmpty()
            .mapNotNull { it.toLongOrNull() }
            .forEach { enqueueWindow(context, AttendanceRefreshSchedule.nextOccurrence(it, now)) }
        AttendanceGeofenceRecoveryWorker.enqueue(context)
        scheduleCheck(context, now, "device_recovery")
    }

    @Synchronized
    private fun migrateLegacyPlan(context: Context) {
        val preferences = prefs(context)
        if (preferences.contains(ENABLED)) return
        // An automatic Play update can occur without opening the app. Preserve
        // a member's existing opt-in and weekly plan from release 35 so the
        // new receiver can recover immediately; never re-enable an opt-out.
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!flutterPrefs.getBoolean("flutter.auto_check_in", false)) return
        val legacy = context.getSharedPreferences("grace_attendance_geofence_refresh", Context.MODE_PRIVATE)
        val slots = legacy.getStringSet("scheduled_names", emptySet()).orEmpty()
            .mapNotNull { it.removePrefix("attendance_geofence_refresh_").toLongOrNull() }
            .filter { it in 0 until AttendanceRefreshSchedule.weekMillis }
            .map { it.toString() }.toSet()
        if (slots.isNotEmpty()) preferences.edit().putBoolean(ENABLED, true).putStringSet(WINDOW_SLOTS, slots).apply()
    }

    fun recordCheck(context: Context, status: String, error: String? = null) {
        prefs(context).edit().putLong("last_check_at", System.currentTimeMillis())
            .putString("last_check_status", status).putString("last_check_error", error).apply()
    }

    fun recordRegistration(context: Context, status: String) {
        prefs(context).edit().putLong("last_registration_at", System.currentTimeMillis())
            .putString("last_registration_status", status).apply()
    }

    fun diagnostics(context: Context): Map<String, Any?> {
        val preferences = prefs(context)
        return mapOf(
            "enabled" to isEnabled(context),
            "remindersEnabled" to remindersEnabled(context),
            "scheduledWindowCount" to preferences.getStringSet(WINDOW_SLOTS, emptySet()).orEmpty().size,
            "lastCheckAt" to preferences.getLong("last_check_at", 0L).takeIf { it > 0 },
            "lastCheckStatus" to preferences.getString("last_check_status", null),
            "lastCheckError" to preferences.getString("last_check_error", null),
            "lastRegistrationAt" to preferences.getLong("last_registration_at", 0L).takeIf { it > 0 },
            "lastRegistrationStatus" to preferences.getString("last_registration_status", null)
        )
    }

    private fun keyTag(key: String): String = CHECK_TAG_PREFIX + MessageDigest.getInstance("SHA-256")
        .digest(key.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
}
