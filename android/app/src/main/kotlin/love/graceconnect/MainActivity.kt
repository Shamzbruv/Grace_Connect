package love.graceconnect

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val configChannel = "love.graceconnect/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, configChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAndroidMapsApiKeyPresent" -> result.success(isAndroidMapsApiKeyPresent())
                    "getAndroidMapsConfigStatus" -> result.success(androidMapsConfigStatus())
                    "getAndroidMapsApiKey" -> result.success(androidMapsApiKey())
                    "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                    "openBatteryOptimizationSettings" -> {
                        openBatteryOptimizationSettings()
                        result.success(null)
                    }
                    "setSecureScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setSecureScreen(enabled)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love.graceconnect/attendance"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleGeofenceRefreshes" -> {
                    val refreshes = call.argument<List<Number>>("epochMillis")
                        ?.map { it.toLong() }
                        .orEmpty()
                    AttendanceGeofenceRefreshWorker.schedule(this, refreshes)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setSecureScreen(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    @Suppress("DEPRECATION")
    private fun isAndroidMapsApiKeyPresent(): Boolean {
        return androidMapsApiKey().isNotEmpty()
    }

    @Suppress("DEPRECATION")
    private fun androidMapsApiKey(): String {
        val appInfo = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA
        )
        val value = appInfo.metaData
            ?.getString("com.google.android.geo.API_KEY")
            ?.trim()
            .orEmpty()
        return if (value.isNotEmpty() && !value.startsWith("\${")) value else ""
    }

    private fun androidMapsConfigStatus(): Map<String, Any?> {
        return mapOf(
            "hasKey" to isAndroidMapsApiKeyPresent(),
            "packageName" to packageName,
            "signingCertificateSha1" to signingCertificateSha1()
        )
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings() {
        val intents = listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            },
            Intent(Settings.ACTION_SETTINGS)
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (_: Exception) {
                // Try the next settings panel.
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun signingCertificateSha1(): String {
        return try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                ).signingInfo?.apkContentsSigners
            } else {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                ).signatures
            }
            val signature = signatures?.firstOrNull() ?: return ""
            val digest = MessageDigest.getInstance("SHA-1")
                .digest(signature.toByteArray())
            digest.joinToString(":") { byte -> "%02X".format(byte) }
        } catch (_: Exception) {
            ""
        }
    }
}
