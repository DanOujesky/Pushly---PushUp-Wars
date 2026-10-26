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
    LaunchedEffect(vm) { vm.start() }
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
        }
    }
    if (showQr && myUsername != null) QrDialog(profileLink(myUsername), myUsername) { showQr = false }
}

@Composable
private fun Action(label: String, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.heightIn(min = MinTouchTarget).clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgElevated.resolve())
            .clickable(role = Role.Button, onClick = onClick).padding(horizontal = SpacingTokens.S),
        contentAlignment = Alignment.Center,
    ) { TokenText(label, TypographyTokens.Button, maxLines = 1) }
}
