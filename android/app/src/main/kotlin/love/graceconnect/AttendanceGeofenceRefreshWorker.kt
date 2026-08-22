package love.graceconnect

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.chunkytofustudios.native_geofence.api.NativeGeofenceApiImpl
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.delay

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
            NativeGeofenceApiImpl(applicationContext).reCreateAfterReboot()
            // Google Play services completes registration asynchronously. Keep
            // this worker alive briefly so the initial ENTER can be delivered.
            delay(3_000)
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    companion object {
        private const val PREFS = "grace_attendance_geofence_refresh"
        private const val KEY_NAMES = "scheduled_names"
        private const val NAME_PREFIX = "attendance_geofence_refresh_"

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
                .take(16)
                .toList()
            val newNames = epochs.map { "$NAME_PREFIX$it" }.toSet()

            for (obsoleteName in oldNames - newNames) {
                manager.cancelUniqueWork(obsoleteName)
            }
            for (epoch in epochs) {
                val name = "$NAME_PREFIX$epoch"
                val request = OneTimeWorkRequestBuilder<AttendanceGeofenceRefreshWorker>()
                    .setInitialDelay(epoch - now, TimeUnit.MILLISECONDS)
                    .addTag(NAME_PREFIX)
                    .build()
                manager.enqueueUniqueWork(name, ExistingWorkPolicy.KEEP, request)
            }
            prefs.edit().putStringSet(KEY_NAMES, newNames).apply()
        }
    }
}
