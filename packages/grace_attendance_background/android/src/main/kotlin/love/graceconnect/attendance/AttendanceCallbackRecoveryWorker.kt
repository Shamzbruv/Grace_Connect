package love.graceconnect.attendance

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.chunkytofustudios.native_geofence.Constants

/** Recover the upstream plugin's APPEND chain after a failed/cancelled callback. */
class AttendanceCallbackRecoveryWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = Result.success()

    companion object {
        fun enqueue(context: Context) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                Constants.GEOFENCE_CALLBACK_WORK_GROUP,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                OneTimeWorkRequestBuilder<AttendanceCallbackRecoveryWorker>().build()
            )
        }
    }
}
