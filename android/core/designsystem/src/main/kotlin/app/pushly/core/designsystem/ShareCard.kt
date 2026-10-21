package app.pushly.core.designsystem

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.Typeface
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.FileProvider
import app.pushly.core.designsystem.generated.ColorTokens
import java.io.File

/** FileProvider for share cards (its own class so it doesn't clash with other providers in the app). */
class ShareFileProvider : FileProvider()

/**
 * Square share image (doc 10 §6, PS-32 "Share"): one big number with a few lines on the arena background, drawn with
 * the design tokens. Same content as the iOS `ShareCard`. No personal data beyond what the caller passes.
 */
object ShareCard {
    private const val SIZE = 1080

    fun render(headline: String, value: String, unit: String, lines: List<String>): Bitmap {
        val bmp = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(ColorTokens.BgBase.dark.toArgb())
        val flame = ColorTokens.BrandFlame.dark.toArgb()
        val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(SIZE / 2f, SIZE * 0.3f, SIZE * 0.6f, intArrayOf((flame and 0x00FFFFFF) or 0x70000000, 0), null,
                Shader.TileMode.CLAMP)
        }
        c.drawRect(0f, 0f, SIZE.toFloat(), SIZE.toFloat(), glow)
        fun paint(color: Int, size: Float, bold: Boolean) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize = size
            typeface = Typeface.create(Typeface.DEFAULT, if (bold) Typeface.BOLD else Typeface.NORMAL)
        }
        val left = 96f
        c.drawText("PUSHLY", left, 160f, paint(ColorTokens.TextPrimary.dark.toArgb(), 64f, true))
        var y = 470f
        c.drawText(headline.uppercase(), left, y, paint(ColorTokens.BrandFlameText.dark.toArgb(), 44f, true))
        y += 300f
        val big = paint(ColorTokens.TextPrimary.dark.toArgb(), 320f, true)
        while (big.measureText(value) > SIZE - 2 * left && big.textSize > 120f) big.textSize -= 10f
        c.drawText(value, left - 12f, y, big)
        y += 80f
        c.drawText(unit, left, y, paint(ColorTokens.TextSecondary.dark.toArgb(), 52f, false))
        lines.take(3).forEach { line ->
            y += 72f
            c.drawText(line, left, y, paint(ColorTokens.TextPrimary.dark.toArgb(), 52f, true))
        }
        c.drawText("pushly · PushUp Wars", left, SIZE - 80f, paint(ColorTokens.TextTertiary.dark.toArgb(), 36f, false))
        return bmp
    }

    /** Renders the card into cache/share/ and opens the system share sheet. */
    fun share(context: Context, chooserTitle: String, headline: String, value: String, unit: String, lines: List<String>) {
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "pushly-share.png")
        file.outputStream().use { render(headline, value, unit, lines).compress(Bitmap.CompressFormat.PNG, 100, it) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", file)
        val send = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(send, chooserTitle).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
