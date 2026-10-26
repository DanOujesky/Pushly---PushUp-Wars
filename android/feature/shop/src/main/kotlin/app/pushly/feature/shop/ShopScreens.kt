package app.pushly.feature.shop

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.Cosmetics
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.common.LegalLinks
import app.pushly.core.common.Monetization
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ProBadge
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import kotlinx.coroutines.launch

/**
 * An adaptive banner at the bottom of Stats / Ranks / clan discovery (doc 13 §1), same as iOS. Nothing for Pro users,
 * before consent, during / right after a wake flow and for brand-new users (AdsGate). With a "Remove ads" link.
 */
@Composable
internal fun BannerAdSlot(placement: String, shop: Shop) {
    val state by shop.state.collectAsStateWithLifecycle()
    val canRequest by shop.ads.canRequestAds.collectAsStateWithLifecycle()
    if (state.isPro || !canRequest || !shop.ads.bannerAllowed(placement)) return
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TokenText(stringResource(if (shop.config.usesTestAds) R.string.ad_label_test else R.string.ad_label), TypographyTokens.Caption,
                Modifier.weight(1f), color = ColorTokens.TextTertiary.resolve())
            TextButton(onClick = { Monetization.showPaywall("remove_ads") }, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                TokenText(stringResource(R.string.ad_remove), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
            }
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val width = maxWidth.value.toInt().coerceAtLeast(320)
            val context = LocalContext.current
            val size = remember(width) { AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(context, width) }
            AndroidView(
                factory = { ctx ->
                    AdView(ctx).apply {
                        setAdSize(size)
                        adUnitId = shop.config.bannerUnitId
                        loadAd(AdRequest.Builder().build())
                    }
                },
                modifier = Modifier.fillMaxWidth().height(size.height.dp),
            )
        }
    }
}

/**
 * Pushly Pro paywall (doc 13 §2, D-073, D-074), same as iOS `PaywallView`. Opened only from explicit entry points
 * (Profile, "Remove ads", a locked Pro sound / frame / emblem) — never after a wake flow or a lost battle.
 * Honest copy: comfort and cosmetics only, never pay-to-win.
 */
@Composable
fun PaywallScreen(shop: Shop, onClose: () -> Unit) {
    val state by shop.state.collectAsStateWithLifecycle()
    val myFrame by Monetization.frame.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var selected by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { shop.loadPlans() }
    val plan = state.plans.firstOrNull { it.id == selected } ?: state.plans.firstOrNull()
    val reason = state.paywallReason
    ArenaBackground(glow = ColorTokens.LeagueGold) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            Row {
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onClose, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                    TokenText(stringResource(R.string.paywall_close), TypographyTokens.Button, color = ColorTokens.TextSecondary.resolve())
                }
            }
            // you, with a gold frame and the PRO badge — what Pro looks like on you
            Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                Box {
                    Avatar(state.me?.username ?: "P", state.me?.avatarPreset, size = 112.dp,
                        frame = if (state.isPro) (myFrame ?: "gold") else "gold")
                    ProBadge(Modifier.align(Alignment.BottomEnd).offset(10.dp, 6.dp), large = true)
                }
                TokenText(stringResource(R.string.paywall_title), TypographyTokens.DisplayL)
                TokenText(stringResource(reasonLine(reason)), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve(),
                    textAlign = TextAlign.Center)
            }
            val perks = ProPerks.ordered(reason)
            perks.chunked(2).forEach { row ->
                Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    row.forEach { perk -> PerkCard(perk, perk.id == ProPerks.focus(reason), Modifier.weight(1f)) }
                }
            }
            FreeVsPro()
            when {
                state.isPro -> InlineBanner(stringResource(R.string.paywall_you_have_pro), BannerKind.Success)
                !shop.purchasesAvailable -> InlineBanner(stringResource(R.string.paywall_coming_soon), BannerKind.Info)
                state.loadingPlans && state.plans.isEmpty() -> CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally),
                    color = ColorTokens.LeagueGold.resolve())
                else -> {
                    state.plans.forEach { p -> PlanCard(p, p.id == plan?.id) { selected = p.id } }
                    if (plan != null) {
                        PrimaryButton(stringResource(if (plan.trialDays != null) R.string.paywall_start_trial else R.string.paywall_get_pro), {
                            scope.launch { if (shop.purchase(plan)) onClose() }
                        }, loading = state.busy)
                        TokenText(terms(plan), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    }
                }
            }
            state.message?.let { InlineBanner(stringResource(it), BannerKind.Info) }
            TokenText(stringResource(R.string.paywall_no_p2w), TypographyTokens.Caption, Modifier.fillMaxWidth(),
                color = ColorTokens.TextTertiary.resolve(), textAlign = TextAlign.Center)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (shop.purchasesAvailable) {
                    TextButton(onClick = { scope.launch { shop.restore() } }, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                        TokenText(stringResource(R.string.paywall_restore), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                    }
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(LegalLinks.TERMS))) },
                    modifier = Modifier.heightIn(min = MinTouchTarget)) {
                    TokenText(stringResource(R.string.paywall_terms), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                }
                TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(LegalLinks.PRIVACY))) },
                    modifier = Modifier.heightIn(min = MinTouchTarget)) {
                    TokenText(stringResource(R.string.paywall_privacy), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                }
            }
        }
    }
}

private fun reasonLine(reason: String?): Int = when (reason) {
    "sound" -> R.string.paywall_reason_sound
    "frame" -> R.string.paywall_reason_frame
    "emblem" -> R.string.paywall_reason_emblem
    "remove_ads" -> R.string.paywall_reason_ads
    else -> R.string.paywall_reason_default
}

/** What Pro gives — only things that exist (D-073, D-074). Same list and order on iOS. */
internal object ProPerks {
    data class Perk(val id: String, val glyph: String, val title: Int, val detail: Int)

    val all: List<Perk> = listOf(
        Perk("ads", "🚫", R.string.perk_no_ads, R.string.perk_no_ads_detail),
        Perk("frame", "🖼️", R.string.perk_frames, R.string.perk_frames_detail),
        Perk("sound", "🎺", R.string.perk_sounds, R.string.perk_sounds_detail),
        Perk("emblem", "🐉", R.string.perk_emblems, R.string.perk_emblems_detail),
        Perk("freeze", "❄️", R.string.perk_freezes, R.string.perk_freezes_detail),
        Perk("badge", "👑", R.string.perk_badge, R.string.perk_badge_detail),
        Perk("support", "❤️", R.string.perk_support, R.string.perk_support_detail),
    )

    fun focus(reason: String?): String? = when (reason) {
        "sound" -> "sound"
        "frame" -> "frame"
        "emblem" -> "emblem"
        "remove_ads" -> "ads"
        else -> null
    }

    /** The perk behind the paywall reason comes first. */
    fun ordered(reason: String?): List<Perk> {
        val key = focus(reason)
        return all.filter { it.id == key } + all.filter { it.id != key }
    }
}

@Composable
private fun PerkCard(perk: ProPerks.Perk, highlight: Boolean, modifier: Modifier) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    Column(
        modifier.fillMaxSize().clip(shape).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.9f))
            .border(if (highlight) 2.dp else 1.dp, (if (highlight) ColorTokens.LeagueGold else ColorTokens.StrokeSubtle).resolve(), shape)
            .padding(SpacingTokens.Sm)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
    ) {
        TokenText(perk.glyph, TypographyTokens.TitleL, Modifier.clearAndSetSemantics {})
        TokenText(stringResource(perk.title), TypographyTokens.TitleS)
        TokenText(stringResource(perk.detail), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
    }
}

/** What you get, side by side (only things that exist — D-074). */
@Composable
private fun FreeVsPro() {
    val rows = listOf(
        Triple(R.string.cmp_ads, R.string.cmp_ads_free, R.string.cmp_ads_pro),
        Triple(R.string.cmp_freezes, R.string.cmp_freezes_free, R.string.cmp_freezes_pro),
        Triple(R.string.cmp_frames, R.string.cmp_frames_free, R.string.cmp_frames_pro),
        Triple(R.string.cmp_sounds, R.string.cmp_sounds_free, R.string.cmp_sounds_pro),
        Triple(R.string.cmp_emblems, R.string.cmp_emblems_free, R.string.cmp_emblems_pro),
        Triple(R.string.cmp_ranks, R.string.cmp_ranks_both, R.string.cmp_ranks_both),
    )
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.9f))
            .padding(horizontal = SpacingTokens.M, vertical = SpacingTokens.S),
    ) {
        Row(Modifier.padding(vertical = SpacingTokens.Xs), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.weight(1f))
            TokenText(stringResource(R.string.cmp_free), TypographyTokens.LabelDisplay, Modifier.width(96.dp),
                color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center)
            Box(Modifier.width(96.dp), contentAlignment = Alignment.Center) { ProBadge() }
        }
        rows.forEach { (title, free, pro) ->
            HorizontalDivider(color = ColorTokens.StrokeSubtle.resolve())
            Row(Modifier.padding(vertical = SpacingTokens.Xs + 2.dp).semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically) {
                TokenText(stringResource(title), TypographyTokens.BodyS, Modifier.weight(1f))
                TokenText(stringResource(free), TypographyTokens.Caption, Modifier.width(96.dp), color = ColorTokens.TextTertiary.resolve(),
                    textAlign = TextAlign.Center)
                TokenText(stringResource(pro), TypographyTokens.Caption, Modifier.width(96.dp), color = ColorTokens.LeagueGold.resolve(),
                    textAlign = TextAlign.Center)
            }
        }
    }
}

/** Profile → "Profile frame": pick a Pro frame (D-074). Free users see them and get the paywall on tap. */
@Composable
fun ProFramePicker(shop: Shop) {
    val state by shop.state.collectAsStateWithLifecycle()
    val frame by Monetization.frame.collectAsState()
    val scope = rememberCoroutineScope()
    val current = if (state.isPro) frame else null
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(stringResource(R.string.frame_title), TypographyTokens.TitleS)
            ProBadge()
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
            (listOf<String?>(null) + Cosmetics.frames).forEach { id ->
                val selected = current == id
                val name = stringResource(frameName(id))
                val locked = id != null && !state.isPro
                Column(
                    Modifier.clip(RoundedCornerShape(RadiusTokens.M))
                        .border(2.dp, if (selected) ColorTokens.LeagueGold.resolve() else Color.Transparent, RoundedCornerShape(RadiusTokens.M))
                        .selectable(selected, enabled = !state.busy, role = Role.RadioButton) {
                            if (locked) Monetization.showPaywall("frame") else scope.launch { shop.setFrame(id) }
                        }
                        .semantics(mergeDescendants = true) { contentDescription = name }
                        .padding(SpacingTokens.Xs),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
                ) {
                    Avatar(state.me?.username ?: "P", state.me?.avatarPreset, size = 56.dp, frame = id,
                        modifier = Modifier.alpha(if (locked) 0.6f else 1f))
                    TokenText(name, TypographyTokens.Caption,
                        color = (if (selected) ColorTokens.LeagueGold else ColorTokens.TextSecondary).resolve())
                }
            }
        }
    }
}

private fun frameName(id: String?): Int = when (id) {
    "gold" -> R.string.frame_gold
    "neon" -> R.string.frame_neon
    "fire" -> R.string.frame_fire
    "ice" -> R.string.frame_ice
    "royal" -> R.string.frame_royal
    else -> R.string.frame_none
}

@Composable
private fun terms(plan: PaywallPlan): String = when (plan.kind) {
    PaywallPlan.Kind.Lifetime -> stringResource(R.string.paywall_terms_lifetime, plan.price)
    else -> {
        val period = stringResource(if (plan.kind == PaywallPlan.Kind.Monthly) R.string.paywall_month else R.string.paywall_year)
        val days = plan.trialDays
        if (days != null) stringResource(R.string.paywall_terms_trial, days, plan.price, period)
        else stringResource(R.string.paywall_terms_plain, plan.price, period)
    }
}

@Composable
private fun PlanCard(plan: PaywallPlan, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    val gold = ColorTokens.LeagueGold.resolve()
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clip(shape).background(ColorTokens.BgSurface.resolve())
            .border(if (selected) 2.dp else 1.dp, if (selected) gold else ColorTokens.StrokeSubtle.resolve(), shape)
            .selectable(selected, role = Role.RadioButton, onClick = onClick)
            .padding(SpacingTokens.M)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        TokenText(if (selected) "◉" else "○", TypographyTokens.TitleS, color = if (selected) gold else ColorTokens.TextTertiary.resolve())
        Column(Modifier.weight(1f)) {
            TokenText(stringResource(when (plan.kind) {
                PaywallPlan.Kind.Monthly -> R.string.plan_monthly
                PaywallPlan.Kind.Annual -> R.string.plan_yearly
                PaywallPlan.Kind.Lifetime -> R.string.plan_lifetime
                PaywallPlan.Kind.Other -> R.string.paywall_title
            }), TypographyTokens.TitleS)
            plan.trialDays?.let {
                TokenText(stringResource(R.string.plan_trial, it), TypographyTokens.Caption, color = ColorTokens.StateSuccessText.resolve())
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            TokenText(plan.price, TypographyTokens.TitleS)
            if (plan.kind == PaywallPlan.Kind.Annual) TokenText(stringResource(R.string.plan_best), TypographyTokens.Caption, color = gold)
        }
    }
}

/** Profile → "Pushly Pro" row: status for Pro users, the entry point for everyone else. */
@Composable
fun ProProfileRow(shop: Shop) {
    val state by shop.state.collectAsStateWithLifecycle()
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clickable(role = Role.Button) { Monetization.showPaywall("profile") }
            .padding(vertical = SpacingTokens.S),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        ProBadge()
        Column(Modifier.weight(1f)) {
            TokenText(stringResource(if (state.isPro) R.string.pro_row_have else R.string.pro_row_get), TypographyTokens.TitleS)
            TokenText(stringResource(if (state.isPro) R.string.pro_row_thanks else R.string.pro_row_pitch), TypographyTokens.Caption,
                color = ColorTokens.TextSecondary.resolve())
        }
        TokenText("›", TypographyTokens.TitleM, Modifier.clearAndSetSemantics {}, color = ColorTokens.TextTertiary.resolve())
    }
}

/** "Ad privacy settings" (UMP) — only where the law needs an entry point (EU). */
@Composable
fun AdPrivacyRow(shop: Shop) {
    val required by shop.ads.privacyOptionsRequired.collectAsStateWithLifecycle()
    if (!required) return
    TextButton(onClick = { shop.activity()?.let { shop.ads.showPrivacyOptions(it) } }, modifier = Modifier.heightIn(min = MinTouchTarget)) {
        TokenText(stringResource(R.string.ad_privacy), TypographyTokens.BodyS)
    }
}
