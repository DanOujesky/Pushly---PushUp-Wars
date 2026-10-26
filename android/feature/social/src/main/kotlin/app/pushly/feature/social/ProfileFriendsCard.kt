package app.pushly.feature.social

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.QrDialog
import app.pushly.core.designsystem.QrScannerDialog
import app.pushly.core.common.PushPrompt
import kotlinx.coroutines.delay
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve

/**
 * Profile tab card (D-077): friends at a glance — count, new requests, faces, the newest activity — plus the three ways
 * to add someone. Tapping opens Friends on the Friends tab (0 Activity, 1 Friends, 2 Add). Same as iOS.
 */
@Composable
fun ProfileFriendsCard(vm: FriendsViewModel, myUsername: String?, onOpen: (Int) -> Unit) {
    val s by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showQr by rememberSaveable { mutableStateOf(false) }
    var scanning by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(vm) {
        // new requests show up without leaving the tab (D-078); ask for push in context once
        PushPrompt.request(PushPrompt.Reason.Friends)
        while (true) {
            vm.reload()
            delay(15_000)
        }
    }
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier.fillMaxWidth().clip(shape)
            .background(Brush.linearGradient(listOf(ColorTokens.BrandCyan.resolve().copy(alpha = 0.14f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(SpacingTokens.Ml),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M)).clickable(role = Role.Button) { onOpen(1) }
                .semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                TokenText(stringResource(R.string.social_card_title), TypographyTokens.TitleM)
                TokenText("${s.list.friends.size}", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
                if (s.list.incoming.isNotEmpty()) {
                    TokenText(stringResource(R.string.social_card_new, s.list.incoming.size), TypographyTokens.Caption, color = Color.White,
                        modifier = Modifier.clip(CircleShape).background(ColorTokens.BrandFlame.resolve()).padding(horizontal = 8.dp, vertical = 2.dp))
                }
                Box(Modifier.weight(1f))
                TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
            }
            if (s.list.friends.isEmpty()) {
                TokenText(stringResource(R.string.social_card_empty), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
            } else {
                Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy((-10).dp)) {
                    s.list.friends.take(7).forEach { f ->
                        Box(Modifier.clip(CircleShape).border(2.dp, ColorTokens.BgSurface.resolve(), CircleShape)) {
                            Avatar(f.username, f.avatarPreset, size = 40.dp, frame = f.frame)
                        }
                    }
                    if (s.list.friends.size > 7) {
                        Box(Modifier.size(40.dp).clip(CircleShape).background(ColorTokens.BgElevated.resolve()), contentAlignment = Alignment.Center) {
                            TokenText("+${s.list.friends.size - 7}", TypographyTokens.Caption)
                        }
                    }
                }
                s.feed.firstOrNull()?.let { item ->
                    val (res, arg) = describe(item)
                    TokenText(stringResource(R.string.social_card_feed, item.user.username, stringResource(res, arg)), TypographyTokens.Caption,
                        color = ColorTokens.TextSecondary.resolve(), maxLines = 1)
                }
            }
        }
        // friend requests right here — accept without digging (D-078)
        s.list.incoming.forEach { u ->
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M))
                    .background(ColorTokens.BrandFlame.resolve().copy(alpha = 0.10f)).padding(SpacingTokens.S),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
            ) {
                Avatar(u.username, u.avatarPreset, size = 36.dp, frame = u.frame)
                Column(Modifier.weight(1f)) {
                    TokenText(u.username, TypographyTokens.TitleS, maxLines = 1)
                    TokenText(stringResource(R.string.social_card_wants), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                }
                Box(
                    Modifier.size(MinTouchTarget).clip(CircleShape).background(ColorTokens.BgElevated.resolve())
                        .clickable(role = Role.Button) { vm.respond(u, false) },
                    contentAlignment = Alignment.Center,
                ) { TokenText("✕", TypographyTokens.TitleS, color = ColorTokens.TextSecondary.resolve()) }
                Box(
                    Modifier.heightIn(min = MinTouchTarget).clip(CircleShape).background(ColorTokens.BrandFlame.resolve())
                        .clickable(role = Role.Button) { vm.respond(u, true) }.padding(horizontal = SpacingTokens.M),
                    contentAlignment = Alignment.Center,
                ) { TokenText(stringResource(R.string.social_accept), TypographyTokens.Button, color = Color.White) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Action("🔍 " + stringResource(R.string.social_card_find), Modifier.weight(1f)) { onOpen(2) }
            if (myUsername != null) {
                val share = stringResource(R.string.social_share_text, profileLink(myUsername))
                Action("↗ " + stringResource(R.string.social_card_share), Modifier.weight(1f)) {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, share)
                    context.startActivity(Intent.createChooser(send, null))
                }
                Action("▦ " + stringResource(R.string.social_card_qr), Modifier.weight(1f)) { showQr = true }
            }
            Action("⌖ " + stringResource(R.string.social_card_scan), Modifier.weight(1f)) { scanning = true }
        }
    }
    if (showQr && myUsername != null) QrDialog(profileLink(myUsername), myUsername) { showQr = false }
    if (scanning) QrScannerDialog(onDismiss = { scanning = false }) { text -> openScannedProfile(context, text) }
}

@Composable
private fun Action(label: String, modifier: Modifier, onClick: () -> Unit) {
    // "🔍 Find" → glyph on top, label below, so four fit on a phone
    val glyph = label.substringBefore(' ')
    val text = label.substringAfter(' ')
    Column(
        modifier.heightIn(min = 52.dp).clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgElevated.resolve())
            .clickable(role = Role.Button, onClick = onClick).padding(horizontal = SpacingTokens.Xs, vertical = SpacingTokens.Xs)
            .semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
    ) {
        TokenText(glyph, TypographyTokens.TitleS, modifier = Modifier.clearAndSetSemantics {})
        TokenText(text, TypographyTokens.Caption, maxLines = 1)
    }
}
