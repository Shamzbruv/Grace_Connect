package love.graceconnect

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/** Published global reflections only. No user access/refresh tokens live here. */
class DailyWordWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        refresh(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in setOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            refresh(context)
        }
    }

    companion object {
        private const val PREFS = "grace_daily_word_widget"
        private const val NONCE = "grace_quote_widget_nonce"

        fun configure(context: Context, apiUrl: String, apiKey: String, viewer: String) {
            val url = URL(apiUrl)
            require(url.protocol == "https" && url.host.endsWith(".supabase.co"))
            // Only publishable keys; this channel never accepts an
            // account access token, service-role key or a privileged secret key.
            require(apiKey.startsWith("sb_publishable_") && apiKey.length < 512)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().putString("api_url", apiUrl.trimEnd('/')).putString("api_key", apiKey).apply()
            setViewer(context, viewer)
            refresh(context)
        }

        fun setViewer(context: Context, viewer: String) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString("viewer", "") != viewer) {
                prefs.edit().putString("viewer", viewer).remove("liked_quote").apply()
                renderAll(context)
            }
        }

        fun setEngagement(context: Context, id: String, count: Long, liked: Boolean) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val cached = readQuote(context) ?: return
            if (cached.optString("id") != id) return
            cached.put("like_count", count.coerceAtLeast(0))
            prefs.edit().putString("quote", cached.toString())
                .putString("liked_quote", if (liked) id else "").apply()
            renderAll(context)
        }

        fun requestPin(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return manager.isRequestPinAppWidgetSupported &&
                manager.requestPinAppWidget(ComponentName(context, DailyWordWidget::class.java), null, null)
        }

        fun isTrustedLike(context: Context, intent: Intent): Boolean {
            val expected = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(NONCE, null)
            return !expected.isNullOrEmpty() && intent.getBooleanExtra("daily_word_like", false) &&
                intent.getStringExtra(NONCE) == expected
        }

        private fun readQuote(context: Context): JSONObject? = try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("quote", null)?.let { JSONObject(it) }
        } catch (_: Exception) { null }

        fun refresh(context: Context) {
            val app = context.applicationContext
            renderAll(app)
            val manager = AppWidgetManager.getInstance(app)
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (manager.getAppWidgetIds(ComponentName(app, DailyWordWidget::class.java)).isEmpty() ||
                prefs.getString("api_key", "").isNullOrEmpty() ||
                System.currentTimeMillis() - prefs.getLong("last_attempt", 0) in 0L..299_999L) return
            // Network work survives process death without holding a broadcast
            // receiver open. Slow DNS must never cause a launcher/widget ANR.
            WorkManager.getInstance(app).enqueueUniqueWork("daily-word-widget-refresh", ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<DailyWordRefreshWorker>()
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .build())
        }

        fun fetchQuote(context: Context) {
            val app = context.applicationContext
            val manager = AppWidgetManager.getInstance(app)
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (manager.getAppWidgetIds(ComponentName(app, DailyWordWidget::class.java)).isEmpty() ||
                prefs.getString("api_key", "").isNullOrEmpty() ||
                System.currentTimeMillis() - prefs.getLong("last_attempt", 0) in 0L..299_999L) return
            prefs.edit().putLong("last_attempt", System.currentTimeMillis()).apply()
            try {
                val started = android.os.SystemClock.elapsedRealtime()
                val connection = URL(prefs.getString("api_url", "") + "/rest/v1/rpc/get_daily_word_widget")
                    .openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "POST"
                    connection.connectTimeout = 2500
                    connection.readTimeout = 3500
                    connection.setRequestProperty("apikey", prefs.getString("api_key", ""))
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.doOutput = true
                    connection.outputStream.use { it.write("{}".toByteArray()) }
                    if (connection.responseCode == 200) {
                        // readNBytes is unavailable on some supported Android
                        // versions. Bound both bytes and background work time.
                        val bytes = connection.inputStream.use { input ->
                            val output = ByteArrayOutputStream()
                            val buffer = ByteArray(2048)
                            while (output.size() <= 32768) {
                                if (android.os.SystemClock.elapsedRealtime() - started > 5500) throw IOException("Widget refresh timed out")
                                val size = input.read(buffer)
                                if (size < 0) break
                                output.write(buffer, 0, size)
                            }
                            output.toByteArray()
                        }
                        if (bytes.size <= 32768) {
                            val body = bytes.toString(Charsets.UTF_8).trim()
                            if (body == "null") prefs.edit().remove("quote").remove("liked_quote").apply()
                            else {
                                val quote = JSONObject(body)
                                if (quote.optString("id").matches(Regex("[a-fA-F0-9-]{36}")) && quote.optString("message").isNotBlank()) {
                                    prefs.edit().putString("quote", quote.toString()).apply()
                                }
                            }
                        }
                    }
                } finally { connection.disconnect() }
                renderAll(app)
            } catch (_: Exception) {
                // Offline or service outage: retain the dated cached reflection.
            }
        }

        private fun renderAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, DailyWordWidget::class.java))
                .forEach { render(context, manager, it) }
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val quote = readQuote(context)
            val quoteId = quote?.optString("id").orEmpty()
            val views = RemoteViews(context.packageName, R.layout.daily_word_widget)
            views.setTextViewText(R.id.grace_verse, quote?.optString("message")
                ?: "Open Grace Connect to bring daily encouragement to your home screen.")
            val reference = quote?.optString("scripture_reference").orEmpty()
            views.setTextViewText(R.id.grace_reference, if (reference.isNotBlank()) "Reflection inspired by $reference" else "A moment of encouragement")
            val date = try { LocalDate.parse(quote?.optString("publish_date"))
                .format(DateTimeFormatter.ofPattern("MMM d", Locale.getDefault())) } catch (_: Exception) { "" }
            views.setTextViewText(R.id.grace_date, date)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val liked = quoteId.isNotEmpty() && prefs.getString("liked_quote", "") == quoteId
            val count = quote?.optLong("like_count", 0)?.coerceAtLeast(0) ?: 0
            views.setTextViewText(R.id.grace_connect, "${if (liked) "♥" else "♡"} ${CompactLikeCount.format(count)}")
            views.setContentDescription(R.id.grace_connect, "Like this Daily Word. $count likes. Opens Grace Connect.")
            views.setBoolean(R.id.grace_connect, "setEnabled", quoteId.isNotEmpty())
            views.setOnClickPendingIntent(R.id.grace_content, launch(context, id, quoteId, false))
            views.setOnClickPendingIntent(R.id.grace_read, launch(context, id, quoteId, false))
            views.setOnClickPendingIntent(R.id.grace_connect, launch(context, id, quoteId, true))
            manager.updateAppWidget(id, views)
        }

        private fun launch(context: Context, id: Int, quoteId: String, like: Boolean): PendingIntent {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val nonce = prefs.getString(NONCE, null) ?: UUID.randomUUID().toString().also { prefs.edit().putString(NONCE, it).apply() }
            val intent = Intent(context, MainActivity::class.java).apply {
                action = DailyGraceWidget.ACTION
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(DailyGraceWidget.EXTRA_DESTINATION, "quote")
                putExtra(DailyGraceWidget.EXTRA_REFERENCE, quoteId)
                putExtra("daily_word_like", like)
                putExtra(NONCE, nonce)
            }
            return PendingIntent.getActivity(context, DailyWidgetIntent.requestCode(id, if (like) 3 else 2), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}

class DailyWordRefreshWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result {
        DailyWordWidget.fetchQuote(applicationContext)
        return Result.success()
    }
}

object CompactLikeCount {
    fun format(count: Long): String {
        val value = count.coerceAtLeast(0)
        for ((base, suffix) in listOf(1_000_000_000_000L to "T", 1_000_000_000L to "B", 1_000_000L to "M", 1_000L to "K")) {
            if (value >= base) {
                val tenths = value / (base / 10)
                return "${tenths / 10}${if (tenths % 10 == 0L) "" else ".${tenths % 10}"}$suffix"
            }
        }
        return value.toString()
    }
}
