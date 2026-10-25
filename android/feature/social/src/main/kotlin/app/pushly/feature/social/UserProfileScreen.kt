package app.pushly.feature.social

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.PLog
import app.pushly.core.common.PushPrompt
import app.pushly.core.common.ReportTarget
import app.pushly.core.common.Reporter
import app.pushly.core.common.SocialService
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ReportAction
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Player profile (doc 15 §1, P6-02). Same behaviour as iOS UserProfileModel. */
class UserProfileViewModel(
    private val service: SocialService,
    private val userId: String?,
    private val username: String?,
) : ViewModel() {
    data class UiState(val profile: UserProfile? = null, val loaded: Boolean = false, val failed: Boolean = false)

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        try {
            val p = UserProfile.decode(service.userProfile(userId, username))
            _state.update { it.copy(profile = p, loaded = true) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "profile load failed: ${e.message}" }
            _state.update { it.copy(loaded = true) }
        }
    }

    private fun run(block: suspend (UserProfile) -> Unit) {
        val p = _state.value.profile ?: return
        viewModelScope.launch {
            try {
                block(p)
                _state.update { it.copy(failed = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(failed = true) }
            }
            reload()
        }
    }

    fun addFriend() = run {
        service.sendFriendRequest(it.user.id)
        PushPrompt.request(PushPrompt.Reason.Friends)
    }

    fun accept() = run { service.respondFriendRequest(it.user.id, true) }
    fun block() = run { service.blockUser(it.user.id) }
}

@Composable
fun UserProfileScreen(vm: UserProfileViewModel, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.load() }
    var confirmBlock by remember { mutableStateOf(false) }
    ArenaBackground(modifier, glow = ColorTokens.BrandVolt, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.social_back), color = ColorTokens.BrandFlameText.resolve())
            }
            val p = s.profile
            when {
                p != null -> ProfileContent(vm, p, s.failed) { confirmBlock = true }
                s.loaded -> TokenText(stringResource(R.string.profile_unavailable), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                else -> CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
            }
        }
    }
    if (confirmBlock) {
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = { confirmBlock = false },
            title = { Text(stringResource(R.string.profile_block_title)) },
            text = { Text(stringResource(R.string.profile_block_text)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmBlock = false
                    vm.block()
                    onBack()
                }) { Text(stringResource(R.string.social_block), color = ColorTokens.StateDanger.resolve()) }
            },
            dismissButton = { TextButton(onClick = { confirmBlock = false }) { Text(stringResource(R.string.social_cancel)) } },
        )
    }
}

@Composable
private fun ProfileContent(vm: UserProfileViewModel, p: UserProfile, failed: Boolean, onBlock: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        Avatar(p.user.username, p.user.avatarPreset, size = 72.dp, frame = p.user.frame)
        Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(p.user.username, TypographyTokens.Name)
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Pill(stringResource(R.string.social_level, p.user.level), color = ColorTokens.BrandVoltText)
                Pill("${p.user.trophies} 🏆", color = ColorTokens.LeagueGold)
                p.user.streak?.takeIf { it > 0 }?.let { Pill("🔥 $it", color = ColorTokens.BrandFlameText) }
            }
            val league = p.league.league.replaceFirstChar { it.uppercase() } + (p.league.tier?.let { " $it" } ?: "")
            TokenText(p.user.clanTag?.let { "$league · [$it]" } ?: league, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
    when (p.relation) {
        "none" -> PrimaryButton(stringResource(R.string.profile_add_friend), vm::addFriend)
        "incoming" -> PrimaryButton(stringResource(R.string.profile_accept), vm::accept)
        "outgoing" -> TokenText(stringResource(R.string.profile_request_sent), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
        "friends" -> TokenText(stringResource(R.string.profile_friends), TypographyTokens.Body, color = ColorTokens.StateSuccessText.resolve())
    }
    if (failed) InlineBanner(stringResource(R.string.social_failed), BannerKind.Warning)

    SectionLabel(stringResource(R.string.profile_stats))
    ProfileCard {
        val st = p.stats
        if (st == null) {
            TokenText(stringResource(if (p.relation == "friends") R.string.profile_private else R.string.profile_friends_only),
                TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
        } else {
            StatLine(stringResource(R.string.profile_reps_total), "${st.repsTotal}")
            StatLine(stringResource(R.string.profile_best_set), "${st.bestSet}")
            StatLine(stringResource(R.string.profile_best_streak), "${st.bestStreak}")
            StatLine(stringResource(R.string.profile_achievements), "${st.achievements}")
            StatLine(stringResource(R.string.profile_best_trophies), "${st.bestTrophies}")
            StatLine(stringResource(R.string.profile_member_since), st.memberSince)
        }
    }
    p.headToHead?.takeIf { it.wins + it.losses + it.draws > 0 }?.let { h ->
        SectionLabel(stringResource(R.string.profile_h2h))
        ProfileCard { TokenText(stringResource(R.string.profile_h2h_line, h.wins, h.losses, h.draws), TypographyTokens.TitleS) }
    }
    if (p.relation != "self") {
        ProfileCard {
            if (Reporter.isAvailable) ReportAction { reason -> Reporter.send(ReportTarget.User(p.user.id), reason) }
            TextButton(onClick = onBlock, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.social_block), color = ColorTokens.StateDanger.resolve())
            }
        }
    }
}

@Composable
private fun StatLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        TokenText(label, TypographyTokens.Body, modifier = Modifier.weight(1f))
        TokenText(value, TypographyTokens.TitleS)
    }
}

@Composable
private fun ProfileCard(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) { content() }
}
