package love.graceconnect

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import love.graceconnect.attendance.AttendanceWorkScheduler

/** Compatibility for work persisted by releases up to build 35. */
class AttendanceGeofenceRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        // New releases migrate to absolute service-window checks. In particular,
        // do not restart every native geofence's dwell timer here.
        AttendanceWorkScheduler.recover(applicationContext)
        return Result.success()
    }
}
