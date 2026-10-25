package app.pushly.core.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens

/**
 * The "side view only" rule (D-064, D-070), same as iOS `SideViewNotice`: only push-ups filmed from the side count for
 * battles and Clan Wars; from the front they count for the alarm and personal stats.
 */
@Composable
fun SideViewNotice(modifier: Modifier = Modifier, compact: Boolean = false) {
    val volt = ColorTokens.BrandVoltText.resolve()
    if (compact) {
        TokenText("▭  " + stringResource(R.string.side_view_compact), TypographyTokens.Caption, modifier, color = volt)
        return
    }
    val title = stringResource(R.string.side_view_title)
    val rule = stringResource(R.string.side_view_rule)
    val front = stringResource(R.string.side_view_front)
    val shape = RoundedCornerShape(RadiusTokens.M)
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(ColorTokens.BgElevated.resolve())
            .border(1.5.dp, ColorTokens.BrandVolt.resolve(), shape)
            .padding(SpacingTokens.M)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SideViewGlyph(Modifier.size(64.dp, 44.dp).clearAndSetSemantics {})
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(title, TypographyTokens.Overline, color = volt)
            TokenText(rule, TypographyTokens.BodyS)
            TokenText(front, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        }
    }
}

/** A phone standing on the floor, filming a person in a plank from the side. */
@Composable
private fun SideViewGlyph(modifier: Modifier) {
    val line = ColorTokens.StrokeStrong.resolve()
    val volt = ColorTokens.BrandVolt.resolve()
    val person = ColorTokens.TextPrimary.resolve()
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val floor = h * 0.92f
        drawLine(line, Offset(0f, floor), Offset(w, floor), strokeWidth = 1.5.dp.toPx())
        val phoneW = w * 0.14f
        val phoneH = h * 0.5f
        drawRoundRect(volt, Offset(0f, floor - phoneH), Size(phoneW, phoneH), CornerRadius(3.dp.toPx()))
        val cone = Path().apply {
            moveTo(phoneW, floor - phoneH / 2)
            lineTo(w, floor - h * 0.72f)
            lineTo(w, floor)
            close()
        }
        drawPath(cone, volt.copy(alpha = 0.18f))
        val r = h * 0.08f
        val head = Offset(w * 0.36f + r, floor - h * 0.56f + r)
        drawCircle(person, r, head)
        drawLine(person, Offset(head.x + r, head.y + h * 0.04f), Offset(w * 0.96f, floor - h * 0.06f),
            strokeWidth = 3.dp.toPx(), cap = StrokeCap.Round)
        val armX = head.x + r + w * 0.03f
        drawLine(person, Offset(armX, head.y + h * 0.07f), Offset(armX, floor), strokeWidth = 2.5.dp.toPx(), cap = StrokeCap.Round)
    }
}
