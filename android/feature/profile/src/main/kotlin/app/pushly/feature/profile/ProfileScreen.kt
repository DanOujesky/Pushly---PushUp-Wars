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
import app.pushly.core.common.ProfileVisibility
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

@Composable
fun ProfileScreen(
    vm: ProfileViewModel,
    appVersion: String,
    modifier: Modifier = Modifier,
    /** Opens Stats & achievements (:feature:stats). Null = no row (guest / no backend). */
    onOpenStats: (() -> Unit)? = null,
    /** Opens Friends & activity (:feature:social). Null = no row. */
    onOpenFriends: (() -> Unit)? = null,
    /** Opens Account & data (notifications, export, deletion). */
    onOpenAccount: (() -> Unit)? = null,
    /** Pushly Pro row + ad privacy (:feature:shop, D-073). */
    pro: (@Composable () -> Unit)? = null,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    var confirmSignOut by remember { mutableStateOf(false) }

    ArenaBackground(modifier, glow = ColorTokens.BrandVolt, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            ScreenTitle(stringResource(R.string.profile_title), token = TypographyTokens.DisplayM)

            Row(
                Modifier.semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            ) {
                val name = s.profile?.username ?: stringResource(R.string.profile_guest)
                Avatar(name, s.profile?.avatarPreset, size = 80.dp, frame = myFrame())
                Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    TokenText(name, TypographyTokens.Name, maxLines = 1)
                    val p = s.profile
                    if (p != null) {
                        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                            Pill(stringResource(R.string.profile_level, p.level), color = ColorTokens.BrandVoltText)
                            Pill(stringResource(R.string.profile_trophies, p.trophies), color = ColorTokens.LeagueGold)
                        }
                    } else {
                        Pill(stringResource(R.string.profile_alarm_only), color = ColorTokens.BrandFlameText)
                    }
                }
            }

            val profile = s.profile
            if (profile == null) {
                PushlyCard {
                    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                        TokenText(stringResource(R.string.profile_guest_text), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
                        PrimaryButton(stringResource(R.string.profile_create_account), vm::createAccount)
                    }
                }
            } else {
                pro?.invoke()
                if (onOpenStats != null || onOpenFriends != null) SectionLabel(stringResource(R.string.profile_progress))
                if (onOpenFriends != null) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = MinTouchTarget)
                            .clip(RoundedCornerShape(RadiusTokens.L))
                            .background(ColorTokens.BgSurface.resolve())
                            .clickable(role = Role.Button, onClick = onOpenFriends)
                            .padding(SpacingTokens.Ml),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TokenText(stringResource(R.string.profile_friends), TypographyTokens.TitleS, modifier = Modifier.weight(1f))
                        TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
                    }
                }
                if (onOpenStats != null) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = MinTouchTarget)
                            .clip(RoundedCornerShape(RadiusTokens.L))
                            .background(ColorTokens.BgSurface.resolve())
                            .clickable(role = Role.Button, onClick = onOpenStats)
                            .padding(SpacingTokens.Ml),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TokenText(stringResource(R.string.profile_stats), TypographyTokens.TitleS, modifier = Modifier.weight(1f))
                        TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
                    }
                }
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
