package love.graceconnect.attendance

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** One location observation, never a permanently running location service. */
class AttendanceCheckWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    private data class Completion(val success: Boolean, val retry: Boolean)

    override suspend fun doWork(): Result = executionLock.withLock {
        if (!AttendanceWorkScheduler.isEnabled(applicationContext) &&
            !AttendanceWorkScheduler.remindersEnabled(applicationContext)) return@withLock Result.success()
        val slot = inputData.getLong(AttendanceWorkScheduler.WINDOW_SLOT_INPUT, -1)
        if (slot >= 0 && !AttendanceWorkScheduler.advanceWindow(applicationContext, slot)) return@withLock Result.success()
        AttendanceCallbackRecoveryWorker.enqueue(applicationContext)
        AttendanceWorkScheduler.recordCheck(applicationContext, "running")
        var engine: FlutterEngine? = null
        var channel: MethodChannel? = null
        try {
            val outcome = withTimeout(90_000) {
                val completed = CompletableDeferred<Completion>()
                withContext(Dispatchers.Main) {
                    val loader = FlutterInjector.instance().flutterLoader()
                    if (!loader.initialized()) loader.startInitialization(applicationContext)
                    loader.ensureInitializationComplete(applicationContext, null)
                    engine = FlutterEngine(applicationContext)
                    channel = MethodChannel(engine!!.dartExecutor.binaryMessenger, "love.graceconnect/attendance_background").also {
                        it.setMethodCallHandler { call, result ->
                            if (call.method != "complete") {
                                result.notImplemented()
                            } else {
                                val outcome = Completion(call.argument<Boolean>("success") == true, call.argument<Boolean>("retry") == true)
                                result.success(null)
                                completed.complete(outcome)
                            }
                        }
                    }
                    engine!!.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "package:grace_connect/services/attendance_service.dart",
                        "attendanceBackgroundCheck"
                    ))
                }
                completed.await()
            }
            when {
                outcome.success -> {
                    AttendanceWorkScheduler.recordCheck(applicationContext, "complete")
                    Result.success()
                }
                outcome.retry && runAttemptCount < 3 -> {
                    AttendanceWorkScheduler.recordCheck(applicationContext, "retrying", "check_incomplete")
                    Result.retry()
                }
                else -> {
                    // A failed observation must not poison other checks or the
                    // independent native-geofence callback chain.
                    AttendanceWorkScheduler.recordCheck(applicationContext, "failed", "check_incomplete")
                    Result.success()
                }
            }
        } catch (error: CancellationException) {
            if (isStopped) throw error
            retryOrFinish("background_timeout")
        } catch (error: Exception) {
            retryOrFinish(error.javaClass.simpleName)
        } finally {
            withContext(NonCancellable + Dispatchers.Main) {
                channel?.setMethodCallHandler(null)
                engine?.destroy()
            }
        }
    }

    private fun retryOrFinish(error: String): Result {
        val retry = runAttemptCount < 3
        AttendanceWorkScheduler.recordCheck(applicationContext, if (retry) "retrying" else "failed", error)
        return if (retry) Result.retry() else Result.success()
    }

    companion object {
        // Avoid parallel headless session refreshes when two service wakeups
        // and a dwell completion become eligible together.
        private val executionLock = Mutex()
    }
}
