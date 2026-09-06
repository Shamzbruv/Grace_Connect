package love.graceconnect

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.chunkytofustudios.native_geofence.api.NativeGeofenceApiImpl
import com.chunkytofustudios.native_geofence.util.NativeGeofencePersistence
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Re-adds the persisted native geofences when a service check-in window opens.
 *
 * Android geofence callbacks are transition based. Without this refresh, a
 * member who arrived before the window and stayed inside would never generate
 * another ENTER event when service began. Re-adding with the plugin's persisted
 * initial ENTER trigger wakes its normal Dart attendance callback even when the
 * app process is closed.
 */
class AttendanceGeofenceRefreshWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        return try {
            val api = NativeGeofenceApiImpl(applicationContext)
            // Await registration; the reboot helper discards asynchronous errors.
            for (geofence in NativeGeofencePersistence.getAllGeofences(applicationContext)) {
                withTimeout(30_000) {
                    suspendCancellableCoroutine<Unit> { continuation ->
                        api.createGeofence(geofence) { outcome ->
                            if (continuation.isActive) outcome.fold(
                                { continuation.resume(Unit) },
                                { continuation.resumeWithException(it) }
                            )
                        }
                    }
                }
            }
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    companion object {
        private const val PREFS = "grace_attendance_geofence_refresh"
        private const val KEY_NAMES = "scheduled_names"
        private const val NAME_PREFIX = "attendance_geofence_refresh_"
        private val WEEK_MILLIS = TimeUnit.DAYS.toMillis(7)

        fun schedule(context: Context, epochsMillis: List<Long>) {
            val manager = WorkManager.getInstance(context)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val oldNames = prefs.getStringSet(KEY_NAMES, emptySet()).orEmpty()
            val now = System.currentTimeMillis()
            val epochs = epochsMillis
                .asSequence()
                .filter { it > now + 10_000 }
                .distinct()
                .sorted()
                // The input covers eight days. Keep the nearest occurrence of
                // each weekly slot so next week cannot postpone this week.
                .distinctBy { it % WEEK_MILLIS }
                .take(16)
                .toList()
            val newNames = epochs.map { "$NAME_PREFIX${it % WEEK_MILLIS}" }.toSet()

            for (obsoleteName in oldNames - newNames) {
                manager.cancelUniqueWork(obsoleteName)
            }
            for (epoch in epochs) {
                val name = "$NAME_PREFIX${epoch % WEEK_MILLIS}"
                val request = PeriodicWorkRequestBuilder<AttendanceGeofenceRefreshWorker>(7, TimeUnit.DAYS)
                    .setInitialDelay(epoch - now, TimeUnit.MILLISECONDS)
                    .addTag(NAME_PREFIX)
                    .build()
                manager.enqueueUniquePeriodicWork(name, ExistingPeriodicWorkPolicy.UPDATE, request)
            }
            prefs.edit().putStringSet(KEY_NAMES, newNames).apply()
        }
    }
}
