package love.graceconnect.attendance

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Registered automatically in UI, geofence and attendance worker engines. */
class GraceAttendanceBackgroundPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var context: Context? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "love.graceconnect/attendance").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val appContext = context ?: return result.error("ATTENDANCE_NOT_READY", "Background attendance is unavailable.", null)
        try {
            when (call.method) {
                "configureAttendanceReminders" -> {
                    AttendanceWorkScheduler.configureReminders(appContext, call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "scheduleGeofenceRefreshes" -> {
                    val epochs = call.argument<List<Number>>("epochMillis")?.map { it.toLong() }.orEmpty()
                    AttendanceWorkScheduler.configureWindows(appContext, epochs)
                    result.success(null)
                }
                "scheduleAttendanceCheck" -> {
                    val epoch = call.argument<Number>("epochMillis")?.toLong()
                    val key = call.argument<String>("key")
                    if (epoch == null || key.isNullOrBlank() || key.length > 200) {
                        result.error("INVALID_ATTENDANCE_CHECK", "A check time and key are required.", null)
                    } else {
                        AttendanceWorkScheduler.scheduleCheck(appContext, epoch, key) { scheduled ->
                            if (scheduled) result.success(null)
                            else result.error("ATTENDANCE_BACKGROUND_UNAVAILABLE", "Background attendance could not be scheduled.", null)
                        }
                    }
                }
                "cancelAttendanceCheck" -> {
                    val key = call.argument<String>("key")
                    if (key == null) result.success(null)
                    else AttendanceWorkScheduler.cancelCheck(appContext, key) { result.success(null) }
                }
                "cancelAttendanceChecks" -> {
                    AttendanceWorkScheduler.cancelAll(appContext)
                    result.success(null)
                }
                "getBackgroundAttendanceStatus" -> result.success(AttendanceWorkScheduler.diagnostics(appContext))
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("ATTENDANCE_BACKGROUND_UNAVAILABLE", "Background attendance could not be scheduled. Please recheck attendance setup.", null)
        }
    }
}
