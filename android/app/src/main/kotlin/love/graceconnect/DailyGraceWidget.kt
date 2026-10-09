package love.graceconnect

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import android.util.TypedValue
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Public-domain Scripture, bundled with the app. No account, network or AI required. */
class DailyGraceWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in setOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            updateAll(context)
        }
    }

    companion object {
        const val ACTION = "love.graceconnect.DAILY_GRACE"
        const val EXTRA_DESTINATION = "daily_grace_destination"
        const val EXTRA_REFERENCE = "daily_grace_reference"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, DailyGraceWidget::class.java))
                .forEach { update(context, manager, it) }
        }

        fun requestPin(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            if (!manager.isRequestPinAppWidgetSupported) return false
            return manager.requestPinAppWidget(ComponentName(context, DailyGraceWidget::class.java), null, null)
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val today = LocalDate.now()
            // A bundled fallback keeps the widget useful if an OEM delivers an
            // update while the APK's assets are being replaced during an upgrade.
            var reference = "Psalms 23:1"
            var text = "Yahweh is my shepherd: I shall lack nothing."
            try {
                val catalogue = context.assets.open("flutter_assets/assets/daily_grace.json")
                    .bufferedReader().use { JSONObject(it.readText()).getJSONArray("verses") }
                val verse = catalogue.getJSONObject(DailyGraceDate.index(today, catalogue.length()))
                reference = verse.getString("reference")
                text = verse.getString("text")
            } catch (_: Exception) { /* Local fallback; never hide the whole widget. */ }

            val views = RemoteViews(context.packageName, R.layout.daily_grace_widget)
            views.setTextViewText(R.id.grace_date, today.format(DateTimeFormatter.ofPattern("EEE, MMM d", Locale.getDefault())))
            views.setTextViewText(R.id.grace_verse, text)
            views.setTextViewText(R.id.grace_reference, "$reference · WEB")
            val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
            views.setTextViewTextSize(R.id.grace_verse, TypedValue.COMPLEX_UNIT_SP, if (height >= 230) 22f else 17f)
            views.setOnClickPendingIntent(R.id.grace_content, launch(context, id, "scripture", reference))
            views.setOnClickPendingIntent(R.id.grace_read, launch(context, id, "scripture", reference))
            views.setOnClickPendingIntent(R.id.grace_connect, launch(context, id, "community", reference))
            manager.updateAppWidget(id, views)
        }

        private fun launch(context: Context, id: Int, destination: String, reference: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = ACTION
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_DESTINATION, destination)
                putExtra(EXTRA_REFERENCE, reference)
            }
            // Keep the destinations distinct without Intent.data: Flutter treats
            // every data URI as a route even for this private widget action.
            val requestCode = DailyWidgetIntent.requestCode(id, if (destination == "community") 1 else 0)
            return PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}

object DailyWidgetIntent {
    fun requestCode(widgetId: Int, action: Int): Int {
        require(action in 0..3)
        return widgetId * 4 + action
    }
}

/** Epoch-day selection avoids DST / time-zone offsets shifting a day's passage. */
object DailyGraceDate {
    fun index(day: LocalDate, count: Int): Int {
        require(count > 0)
        return Math.floorMod(day.toEpochDay(), count.toLong()).toInt()
    }
}
