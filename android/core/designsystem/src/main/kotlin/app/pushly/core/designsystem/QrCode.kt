package app.pushly.core.designsystem

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/** My profile link as a big QR code on white (best for other cameras). Battle (D-072) and Profile → Friends (D-077). */
@Composable
fun QrDialog(link: String, username: String, onDismiss: () -> Unit) {
    val bitmap = remember(link) { QrCode.bitmap(link) }
    val a11y = stringResource(R.string.qr_a11y, username)
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ColorTokens.BgElevated.resolve(),
        title = { TokenText(stringResource(R.string.qr_title), TypographyTokens.TitleL) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                if (bitmap != null) {
                    Image(
                        bitmap.asImageBitmap(), a11y,
                        Modifier.size(240.dp).clip(RoundedCornerShape(RadiusTokens.M)).background(Color.White).padding(SpacingTokens.M),
                        filterQuality = FilterQuality.None,
                    )
                }
                TokenText("@$username", TypographyTokens.TitleM, color = ColorTokens.BrandFlameText.resolve())
                TokenText(stringResource(R.string.qr_how), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve(),
                    textAlign = TextAlign.Center)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { TokenText(stringResource(R.string.qr_close), TypographyTokens.Button) } },
    )
}

object QrCode {
    /** Black-on-white QR code (ZXing core, medium error correction, D-072). */
    fun bitmap(text: String, size: Int = 512): Bitmap? = runCatching {
        val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 1)
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints)
        val pixels = IntArray(size * size) { i -> if (matrix[i % size, i / size]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
        Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
    }.getOrNull()
}
