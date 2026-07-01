package love.graceconnect

import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val configChannel = "love.graceconnect/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, configChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAndroidMapsApiKeyPresent" -> result.success(isAndroidMapsApiKeyPresent())
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun isAndroidMapsApiKeyPresent(): Boolean {
        val appInfo = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA
        )
        val value = appInfo.metaData
            ?.getString("com.google.android.geo.API_KEY")
            ?.trim()
            .orEmpty()
        return value.isNotEmpty() && !value.startsWith("\${")
    }
}
