package app.pushly.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.TypographyTokens

/**
 * Where a banner ad may sit (doc 13 §1: stats_banner, ranks_banner, clan_banner) — same as iOS `AdBannerSlot`. The
 * app plugs the real banner (shop module) into [AdSlots.provider] at launch; until then the slot is empty. The
 * provider decides whether to show anything (AdsGate, Pro, consent).
 */
object AdSlots {
    @Volatile var provider: (@Composable (String) -> Unit)? = null
}

@Composable
fun AdBannerSlot(placement: String) {
    AdSlots.provider?.invoke(placement)
}

/** The gold PRO badge (Pushly Pro, D-073) — next to Pro users' names and on the paywall. Same as iOS. */
@Composable
fun ProBadge(modifier: Modifier = Modifier, large: Boolean = false) {
    val gold = ColorTokens.LeagueGold.resolve()
    val flame = ColorTokens.BrandFlame.resolve()
    val label = stringResource(R.string.pro_badge)
    TokenText(
        "PRO",
        if (large) TypographyTokens.TitleS else TypographyTokens.Tab,
        modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Brush.linearGradient(listOf(gold, flame)))
            .padding(horizontal = if (large) 8.dp else 5.dp, vertical = if (large) 3.dp else 1.dp)
            .semantics { contentDescription = label },
        color = ColorTokens.BgBase.resolve(),
    )
}
