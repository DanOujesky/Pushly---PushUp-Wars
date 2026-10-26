package app.pushly.feature.profile

import app.pushly.core.common.Monetization
import androidx.compose.runtime.collectAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.common.LegalLinks
import app.pushly.core.common.Profile
import app.pushly.core.common.ProfileVisibility
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.semantics.contentDescription
import app.pushly.core.designsystem.ProBadge
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve

/**
 * Profile tab (D-077): hero (framed avatar with level, name, PRO, trophies), your stats card, friends card and Pushly
 * Pro. Privacy, account, help and sign out live in Settings (gear). Same as iOS `ProfileView`.
 */
@Composable
fun ProfileScreen(
    vm: ProfileViewModel,
    modifier: Modifier = Modifier,
    /** Stats card (:feature:stats `ProfileStatsCard`). Null = guest / no backend. */
    stats: (@Composable () -> Unit)? = null,
    /** Friends card (:feature:social `ProfileFriendsCard`). */
    friends: (@Composable () -> Unit)? = null,
    onOpenSettings: () -> Unit,
    /** Pushly Pro row + frames + ad privacy (:feature:shop, D-073). */
    pro: (@Composable () -> Unit)? = null,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    ArenaBackground(modifier, glow = ColorTokens.BrandVolt, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ScreenTitle(stringResource(R.string.profile_title), token = TypographyTokens.DisplayM, modifier = Modifier.weight(1f))
                val label = stringResource(R.string.profile_settings)
                Box(
                    Modifier.size(MinTouchTarget).clip(CircleShape).background(ColorTokens.BgSurface.resolve())
                        .clickable(role = Role.Button, onClick = onOpenSettings).semantics { contentDescription = label },
                    contentAlignment = Alignment.Center,
                ) { TokenText("⚙", TypographyTokens.TitleL) }
            }
            Hero(s.profile)
            val profile = s.profile
            if (profile == null) {
                PushlyCard {
                    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                        TokenText(stringResource(R.string.profile_guest_text), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
                        PrimaryButton(stringResource(R.string.profile_create_account), vm::createAccount)
                    }
                }
            } else {
                if (stats != null) {
                    SectionLabel(stringResource(R.string.profile_your_stats))
                    stats()
                }
                if (friends != null) {
                    SectionLabel(stringResource(R.string.profile_friends_section))
                    friends()
                }
                if (pro != null) {
                    SectionLabel(stringResource(R.string.profile_pro_section))
                    pro()
                }
            }
            s.failure?.let {
                InlineBanner(stringResource(if (it == ProfileViewModel.Failure.Network) R.string.profile_save_failed_network else R.string.profile_save_failed))
            }
        }
    }
}

@Composable
private fun Hero(p: Profile?) {
    val name = p?.username ?: stringResource(R.string.profile_guest)
    val pro = Monetization.pro.collectAsState().value
    val shape = RoundedCornerShape(RadiusTokens.Xl)
    Row(
        Modifier.fillMaxWidth().clip(shape)
            .background(Brush.linearGradient(listOf(ColorTokens.BrandVolt.resolve().copy(alpha = 0.16f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(SpacingTokens.Ml)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Box(contentAlignment = Alignment.BottomEnd) {
            Avatar(name, p?.avatarPreset, size = 96.dp, frame = myFrame())
            if (p != null) {
                Box(
                    Modifier.size(32.dp).clip(CircleShape).background(ColorTokens.BgBase.resolve()).padding(3.dp)
                        .clip(CircleShape).background(ColorTokens.BrandVolt.resolve()),
                    contentAlignment = Alignment.Center,
                ) { TokenText("${p.level}", TypographyTokens.TitleS, color = ColorTokens.BgBase.resolve()) }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                TokenText(name, TypographyTokens.Name, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                if (p?.isPro == true || pro) ProBadge()
            }
            if (p != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    Pill("🏆 ${p.trophies}", color = ColorTokens.LeagueGold)
                    Pill(stringResource(R.string.profile_level, p.level), color = ColorTokens.BrandVoltText)
                }
            } else {
                Pill(stringResource(R.string.profile_alarm_only), color = ColorTokens.BrandFlameText)
            }
        }
    }
}

/** Settings (D-077): privacy, account & data, sign out, help and legal, version — off the main Profile page. */
@Composable
fun ProfileSettingsScreen(
    vm: ProfileViewModel,
    appVersion: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    /** Opens Account & data (notifications, export, deletion). */
    onOpenAccount: (() -> Unit)? = null,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    var confirmSignOut by remember { mutableStateOf(false) }
    ArenaBackground(modifier, glow = ColorTokens.BrandVolt, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.profile_back), color = ColorTokens.BrandFlameText.resolve())
            }
            ScreenTitle(stringResource(R.string.profile_settings), token = TypographyTokens.DisplayM)
            val profile = s.profile
            if (profile != null) {
                SectionLabel(stringResource(R.string.profile_privacy))
                PushlyCard {
                    Column {
                        Text(stringResource(R.string.profile_visible_to), style = MaterialTheme.typography.titleSmall)
                        listOf(
                            ProfileVisibility.Public to R.string.visibility_public,
                            ProfileVisibility.Friends to R.string.visibility_friends,
                            ProfileVisibility.Private to R.string.visibility_private,
                        ).forEach { (value, label) ->
                            Row(
                                Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)
                                    .selectable(profile.profileVisibility == value, role = Role.RadioButton) { vm.setVisibility(value) },
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                RadioButton(
                                    selected = profile.profileVisibility == value,
                                    onClick = null,
                                    colors = RadioButtonDefaults.colors(selectedColor = ColorTokens.BrandFlame.resolve()),
                                )
                                Text(stringResource(label), modifier = Modifier.padding(start = SpacingTokens.S))
                            }
                        }
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)
                                .toggleable(profile.leaderboardVisible, role = Role.Switch) { vm.setLeaderboardVisible(it) },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(stringResource(R.string.profile_leaderboard), modifier = Modifier.weight(1f))
                            Switch(
                                checked = profile.leaderboardVisible,
                                onCheckedChange = null,
                                colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()),
                            )
                        }
                        Text(stringResource(R.string.profile_leaderboard_hint), style = MaterialTheme.typography.bodySmall,
                            color = ColorTokens.TextSecondary.resolve())
                    }
                }
                s.failure?.let {
                    InlineBanner(stringResource(if (it == ProfileViewModel.Failure.Network) R.string.profile_save_failed_network else R.string.profile_save_failed))
                }
                if (onOpenAccount != null) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = MinTouchTarget)
                            .clip(RoundedCornerShape(RadiusTokens.L))
                            .background(ColorTokens.BgSurface.resolve())
                            .clickable(role = Role.Button, onClick = onOpenAccount)
                            .padding(SpacingTokens.Ml),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TokenText(stringResource(R.string.profile_account), TypographyTokens.TitleS, modifier = Modifier.weight(1f))
                        TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
                    }
                }
                TextButton(onClick = { confirmSignOut = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.profile_sign_out), color = ColorTokens.StateDanger.resolve())
                }
            }
            LegalLinksCard()
            Text(stringResource(R.string.profile_version, appVersion), style = MaterialTheme.typography.bodySmall,
                color = ColorTokens.TextTertiary.resolve())
        }
    }

    if (confirmSignOut) {
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = { confirmSignOut = false },
            title = { Text(stringResource(R.string.profile_sign_out_confirm)) },
            text = { Text(stringResource(R.string.profile_sign_out_text)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmSignOut = false
                    vm.signOut()
                }) { Text(stringResource(R.string.profile_sign_out)) }
            },
            dismissButton = { TextButton(onClick = { confirmSignOut = false }) { Text(stringResource(R.string.profile_cancel)) } },
        )
    }
}

/** Help + legal pages (doc 16 §7): opened in the browser, same URLs as iOS. */
@Composable
private fun LegalLinksCard() {
    val uri = LocalUriHandler.current
    val links = listOf(
        R.string.profile_help to LegalLinks.SUPPORT,
        R.string.profile_terms to LegalLinks.TERMS,
        R.string.profile_privacy_policy to LegalLinks.PRIVACY,
        R.string.profile_community to LegalLinks.COMMUNITY,
    )
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve()),
    ) {
        links.forEach { (label, url) ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = MinTouchTarget)
                    .clickable(role = Role.Button) { uri.openUri(url) }
                    .padding(horizontal = SpacingTokens.Ml),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TokenText(stringResource(label), TypographyTokens.Body, modifier = Modifier.weight(1f))
                TokenText("↗", TypographyTokens.Body, color = ColorTokens.TextTertiary.resolve())
            }
        }
    }
}

/** My Pro frame (D-074), only while Pro. */
@Composable
private fun myFrame(): String? {
    val pro = Monetization.pro.collectAsState().value
    val frame = Monetization.frame.collectAsState().value
    return if (pro) frame else null
}
