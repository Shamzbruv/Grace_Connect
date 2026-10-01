package love.graceconnect

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File

@UnstableApi
class GraceVideoExporter(private val context: Context) {
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null
    private var output: File? = null
    private var generation = 0

    fun export(inputPath: String?, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "A video is already being prepared.", null); return }
        try {
            val input = File(inputPath ?: "").canonicalFile
            val directory = File(context.cacheDir, "grace_exports").canonicalFile
            require(input.parentFile == directory && input.isFile) { "Invalid export input." }
            val target = File(directory, "${input.nameWithoutExtension}-watermarked.mp4")
            target.delete()
            output = target
            pending = result
            val requestId = ++generation
            val title = SpannableString(" Grace Connect ").apply {
                setSpan(AbsoluteSizeSpan(32), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                setSpan(ForegroundColorSpan(Color.WHITE), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                setSpan(BackgroundColorSpan(0x99000000.toInt()), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            val settings = OverlaySettings.Builder()
                .setBackgroundFrameAnchor(-0.94f, -0.94f)
                .setOverlayFrameAnchor(-1f, -1f).build()
            val overlay = TextOverlay.createStaticTextOverlay(title, settings)
            val edited = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input)))
                .setEffects(Effects(emptyList(), listOf(OverlayEffect(listOf(overlay)))))
                .build()
            transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        if (requestId != generation) return
                        val reply = pending
                        pending = null; transformer = null; output = null
                        reply?.success(target.path)
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, exception: ExportException) {
                        if (requestId != generation) return
                        fail("This video could not be prepared. Please try again.")
                    }
                }).build()
            transformer!!.start(edited, target.path)
        } catch (_: Exception) {
            if (pending != null) fail("Video export failed.")
            else result.error("export_failed", "Video export failed.", null)
        }
    }

    private fun fail(message: String) {
        generation++
        val reply = pending
        pending = null
        transformer?.cancel(); transformer = null
        output?.delete(); output = null
        reply?.error("export_failed", message, null)
    }

    fun cancel() { fail("Video preparation cancelled.") }
}
