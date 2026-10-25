package app.pushly.core.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.TokenColor
import kotlinx.serialization.Serializable
import kotlin.math.cos
import kotlin.math.sin

/**
 * Cosmetics catalog (D-074, shared/cosmetics/cosmetics.json): Pro profile frames and clan badges. Cosmetic only —
 * nothing here changes reps, trophies, matchmaking, wars or leaderboards. Same as iOS `Cosmetics`.
 */
object Cosmetics {
    val frames: List<String> = listOf("gold", "neon", "fire", "ice", "royal")
    val badgeShapes: List<String> = listOf("shield", "round", "hex")
    val badgeColors: List<String> = listOf("flame", "volt", "cyan", "lime", "gold", "red", "diamond", "pink")

    data class Emblem(val id: String, val glyph: String, val pro: Boolean)

    val emblems: List<Emblem> = listOf(
        Emblem("flame", "🔥", false), Emblem("fist", "👊", false), Emblem("bolt", "⚡", false), Emblem("muscle", "💪", false),
        Emblem("wolf", "🐺", false), Emblem("lion", "🦁", false), Emblem("eagle", "🦅", false), Emblem("skull", "💀", false),
        Emblem("dragon", "🐉", true), Emblem("crown", "👑", true), Emblem("diamond", "💎", true), Emblem("rocket", "🚀", true),
        Emblem("trident", "🔱", true), Emblem("shark", "🦈", true), Emblem("comet", "☄️", true), Emblem("volcano", "🌋", true),
    )

    fun emblem(id: String?): Emblem? = emblems.firstOrNull { it.id == id }

    fun badgeColor(id: String): TokenColor = when (id) {
        "volt" -> ColorTokens.BrandVolt
        "cyan" -> ColorTokens.BrandCyan
        "lime" -> ColorTokens.BrandLime
        "gold" -> ColorTokens.LeagueGold
        "red" -> ColorTokens.StateDanger
        "diamond" -> ColorTokens.LeagueDiamond
        "pink" -> ColorTokens.LeagueChampion
        else -> ColorTokens.BrandFlame
    }

    /** Gradient stops of a frame (null = no frame). */
    fun frameColors(id: String?): List<TokenColor>? = when (id) {
        "gold" -> listOf(ColorTokens.LeagueGold, ColorTokens.BrandFlame, ColorTokens.LeagueGold, ColorTokens.LeagueSilver, ColorTokens.LeagueGold)
        "neon" -> listOf(ColorTokens.BrandCyan, ColorTokens.BrandVolt, ColorTokens.BrandLime, ColorTokens.BrandCyan)
        "fire" -> listOf(ColorTokens.BrandFlame, ColorTokens.StateDanger, ColorTokens.LeagueGold, ColorTokens.BrandFlame)
        "ice" -> listOf(ColorTokens.LeagueDiamond, ColorTokens.LeagueSilver, ColorTokens.BrandCyan, ColorTokens.LeagueDiamond)
        "royal" -> listOf(ColorTokens.BrandVolt, ColorTokens.LeagueChampion, ColorTokens.LeagueGold, ColorTokens.BrandVolt)
        else -> null
    }
}

/** A clan's badge: shape + colour + emblem. `{}` (older clans) gets a stable look from the tag. Same as iOS. */
@Serializable
data class ClanBadgeStyle(val shape: String? = null, val color: String? = null, val emblem: String? = null) {
    data class Resolved(val shape: String, val color: String, val emblem: Cosmetics.Emblem)

    /** The badge as drawn: missing parts are picked from the tag, so every clan looks different and stays the same. */
    fun resolved(tag: String): Resolved {
        val seed = seed(tag)
        val free = Cosmetics.emblems.filter { !it.pro }
        return Resolved(
            shape = shape?.takeIf { it in Cosmetics.badgeShapes } ?: "shield",
            color = color?.takeIf { it in Cosmetics.badgeColors } ?: Cosmetics.badgeColors[seed % Cosmetics.badgeColors.size],
            emblem = Cosmetics.emblem(emblem) ?: free[(seed / 8) % free.size],
        )
    }

    /** The patch for `update_clan` / `create_clan`. */
    fun toMap(): Map<String, String> = buildMap {
        shape?.let { put("shape", it) }
        color?.let { put("color", it) }
        emblem?.let { put("emblem", it) }
    }

    companion object {
        /** Sum of the tag's code points, uppercased (same as iOS). */
        fun seed(tag: String): Int = tag.uppercase().codePoints().toArray().sum()
    }
}

/** A clan badge — a shield, round or hex in the clan's colour with its emblem. Static. Decorative for screen readers. */
@Composable
fun ClanEmblem(style: ClanBadgeStyle?, tag: String, size: Dp = 56.dp, modifier: Modifier = Modifier) {
    val r = (style ?: ClanBadgeStyle()).resolved(tag)
    val color = Cosmetics.badgeColor(r.color).resolve()
    val height = if (r.shape == "shield") size * 1.12f else size
    Box(modifier.size(size, height).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size, height)) {
            val path = badgePath(r.shape, this.size, 0f)
            drawPath(path, Brush.verticalGradient(listOf(color, color.copy(alpha = 0.55f))))
            drawPath(badgePath(r.shape, this.size, this.size.width * 0.06f), Color.White.copy(alpha = 0.35f),
                style = Stroke(width = maxOf(1f, this.size.width * 0.025f)))
            drawPath(path, Color.Black.copy(alpha = 0.35f), style = Stroke(width = maxOf(1f, this.size.width * 0.02f)))
        }
        val fixed = with(LocalDensity.current) { (size * 0.42f).toSp() }
        Text(
            r.emblem.glyph,
            style = TextStyle(fontSize = fixed, lineHeight = fixed),
            modifier = Modifier.offset(y = if (r.shape == "shield") -size * 0.04f else 0.dp),
        )
    }
}

/** Shield / circle / hexagon used by clan badges, inset by [inset] px. */
fun badgePath(kind: String, size: Size, inset: Float): Path {
    val x = inset
    val y = inset
    val w = size.width - inset * 2
    val h = size.height - inset * 2
    return Path().apply {
        when (kind) {
            "round" -> addOval(androidx.compose.ui.geometry.Rect(x, y, x + w, y + h))
            "hex" -> {
                for (i in 0 until 6) {
                    val a = i * Math.PI / 3 - Math.PI / 2
                    val px = (x + w / 2 + w / 2 * cos(a)).toFloat()
                    val py = (y + h / 2 + h / 2 * sin(a)).toFloat()
                    if (i == 0) moveTo(px, py) else lineTo(px, py)
                }
                close()
            }
            else -> {
                moveTo(x + w * 0.5f, y)
                quadraticTo(x + w * 0.8f, y + h * 0.1f, x + w, y + h * 0.1f)
                lineTo(x + w, y + h * 0.45f)
                quadraticTo(x + w * 0.95f, y + h * 0.82f, x + w * 0.5f, y + h)
                quadraticTo(x + w * 0.05f, y + h * 0.82f, x, y + h * 0.45f)
                lineTo(x, y + h * 0.1f)
                quadraticTo(x + w * 0.2f, y + h * 0.1f, x + w * 0.5f, y)
                close()
            }
        }
    }
}

/** A Pro frame around an avatar (static gradient ring) in already-resolved [colors]. */
internal fun DrawScope.drawProfileFrame(colors: List<Color>) {
    if (colors.size < 2) return
    val stroke = maxOf(2.dp.toPx(), size.width * 0.075f)
    drawRoundRect(
        brush = Brush.sweepGradient(colors, center = Offset(size.width / 2, size.height / 2)),
        topLeft = Offset(stroke / 2, stroke / 2),
        size = Size(size.width - stroke, size.height - stroke),
        cornerRadius = CornerRadius(size.width * 0.34f, size.width * 0.34f),
        style = Stroke(width = stroke),
    )
}
