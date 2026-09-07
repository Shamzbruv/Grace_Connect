package love.graceconnect.attendance

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.chunkytofustudios.native_geofence.api.NativeGeofenceApiImpl
import com.chunkytofustudios.native_geofence.util.NativeGeofencePersistence
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Re-register only after boot/update; routine checks must not restart OS dwell. */
class AttendanceGeofenceRecoveryWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (!AttendanceWorkScheduler.isEnabled(applicationContext)) return Result.success()
        return try {
            AttendanceCallbackRecoveryWorker.enqueue(applicationContext)
            val api = NativeGeofenceApiImpl(applicationContext)
            withTimeout(90_000) {
                for (geofence in NativeGeofencePersistence.getAllGeofences(applicationContext)) {
                    if (!AttendanceWorkScheduler.isEnabled(applicationContext)) return@withTimeout
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
            AttendanceWorkScheduler.recordRegistration(applicationContext, "registered")
            Result.success()
        } catch (error: CancellationException) {
            if (isStopped) throw error
            retryOrFinish()
        } catch (_: Exception) {
            retryOrFinish()
        }
    }

    private fun retryOrFinish(): Result {
        val retry = runAttemptCount < 3
        AttendanceWorkScheduler.recordRegistration(applicationContext, if (retry) "retrying" else "failed")
        return if (retry) Result.retry() else Result.success()
    }

    companion object {
        fun enqueue(context: Context) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                "grace_attendance_geofence_recovery", ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<AttendanceGeofenceRecoveryWorker>()
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .build()
            )
        }
    }
}
