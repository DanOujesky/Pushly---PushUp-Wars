package app.pushly.feature.profile

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.AccountService
import app.pushly.core.common.PLog
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/** Account & data (doc 16 §4, doc 15 §2): notification categories, data export, account deletion. Same as iOS. */
class AccountViewModel(private val account: AccountService, private val onDeleted: () -> Unit) : ViewModel() {
    @Serializable data class Prefs(
        val categories: Map<String, Boolean> = emptyMap(),
        val quietStart: String = "22:00",
        val quietEnd: String = "07:00",
    )

    enum class Message { None, SaveFailed, ExportFailed, DeleteFailed, Reauth }

    data class UiState(
        val prefs: Prefs = Prefs(),
        val working: Boolean = false,
        val message: Message = Message.None,
        val exportJson: String? = null,
        /** Others may race an anonymous recording of this user's battles (doc 07 §7). Off = runs deleted. */
        val ghostContribution: Boolean = true,
    )

    @Serializable private data class PrivacySettings(val ghostOptOut: Boolean = false)

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun enabled(category: String): Boolean = _state.value.prefs.categories[category] ?: (category != "promotions")

    fun load() {
        viewModelScope.launch {
            runCatching { json.decodeFromString(Prefs.serializer(), account.notificationPrefs()) }
                .onSuccess { p -> _state.update { it.copy(prefs = p) } }
            runCatching { json.decodeFromString(PrivacySettings.serializer(), account.privacySettings()) }
                .onSuccess { p -> _state.update { it.copy(ghostContribution = !p.ghostOptOut) } }
        }
    }

    fun setGhostContribution(on: Boolean) {
        val before = _state.value.ghostContribution
        _state.update { it.copy(ghostContribution = on) }
        viewModelScope.launch {
            try {
                account.setGhostOptOut(!on)
                _state.update { it.copy(message = Message.None) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PLog.error { "ghost opt-out save failed: ${e.message}" }
                _state.update { it.copy(ghostContribution = before, message = Message.SaveFailed) }
            }
        }
    }

    fun set(category: String, on: Boolean) {
        val prefs = _state.value.prefs.let { it.copy(categories = it.categories + (category to on)) }
        _state.update { it.copy(prefs = prefs) }
        viewModelScope.launch {
            try {
                val saved = account.setNotificationPrefs(json.encodeToString(Prefs.serializer(), prefs))
                _state.update { it.copy(prefs = json.decodeFromString(Prefs.serializer(), saved), message = Message.None) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PLog.error { "prefs save failed: ${e.message}" }
                _state.update { it.copy(message = Message.SaveFailed) }
            }
        }
    }

    fun export() {
        _state.update { it.copy(working = true) }
        viewModelScope.launch {
            try {
                val data = account.exportMyData()
                _state.update { it.copy(exportJson = data, working = false, message = Message.None) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(working = false, message = Message.ExportFailed) }
            }
        }
    }

    fun exportShared() = _state.update { it.copy(exportJson = null) }

    fun delete() {
        _state.update { it.copy(working = true) }
        viewModelScope.launch {
            try {
                account.deleteMyAccount()
                _state.update { it.copy(working = false) }
                onDeleted()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val reauth = "${e.message}".let { "reauth" in it || "sign in again" in it }
                _state.update { it.copy(working = false, message = if (reauth) Message.Reauth else Message.DeleteFailed) }
            }
        }
    }

    companion object {
        val categories = listOf("social", "battles", "clan", "activity", "promotions")
    }
}

@Composable
fun AccountScreen(vm: AccountViewModel, onBack: () -> Unit, onSignInAgain: () -> Unit, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    var confirmDelete by remember { mutableStateOf(false) }
    val context = LocalContext.current
    LaunchedEffect(vm) { vm.load() }
    LaunchedEffect(s.exportJson) {
        val data = s.exportJson ?: return@LaunchedEffect
        val dir = File(context.cacheDir, "export").apply { mkdirs() }
        val file = File(dir, "pushly-my-data.json").apply { writeText(data) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.export", file)
        val send = Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(send, null))
        vm.exportShared()
    }
    ArenaBackground(modifier, glow = ColorTokens.BrandVolt, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.account_back), color = ColorTokens.BrandFlameText.resolve())
            }
            ScreenTitle(stringResource(R.string.account_title), token = TypographyTokens.DisplayM)
            SectionLabel(stringResource(R.string.account_notifications))
            PushlyCard {
                Column {
                    AccountViewModel.categories.forEach { c ->
                        val label = stringResource(
                            when (c) {
                                "social" -> R.string.account_cat_social
                                "battles" -> R.string.account_cat_battles
                                "clan" -> R.string.account_cat_clan
                                "activity" -> R.string.account_cat_activity
                                else -> R.string.account_cat_promotions
                            },
                        )
                        val on = s.prefs.categories[c] ?: (c != "promotions")
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).toggleable(on, role = Role.Switch) { vm.set(c, it) },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(label, modifier = Modifier.weight(1f))
                            Switch(on, onCheckedChange = null, colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()))
                        }
                    }
                    TokenText(stringResource(R.string.account_quiet, s.prefs.quietStart, s.prefs.quietEnd), TypographyTokens.Caption,
                        color = ColorTokens.TextTertiary.resolve())
                }
            }
            SectionLabel(stringResource(R.string.account_privacy))
            PushlyCard {
                Column {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)
                            .toggleable(s.ghostContribution, role = Role.Switch) { vm.setGhostContribution(it) },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.account_ghost), modifier = Modifier.weight(1f))
                        Switch(s.ghostContribution, onCheckedChange = null,
                            colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()))
                    }
                    TokenText(stringResource(R.string.account_ghost_note), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
            SectionLabel(stringResource(R.string.account_data))
            PushlyCard {
                Column {
                    TextButton(onClick = vm::export, enabled = !s.working, modifier = Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)) {
                        Text(stringResource(R.string.account_export))
                    }
                    TextButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/account/subscriptions")))
                    }, modifier = Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)) { Text(stringResource(R.string.account_subscriptions)) }
                }
            }
            when (s.message) {
                AccountViewModel.Message.SaveFailed -> InlineBanner(stringResource(R.string.account_save_failed), BannerKind.Warning)
                AccountViewModel.Message.ExportFailed -> InlineBanner(stringResource(R.string.account_export_failed), BannerKind.Warning)
                AccountViewModel.Message.DeleteFailed -> InlineBanner(stringResource(R.string.account_delete_failed), BannerKind.Warning)
                AccountViewModel.Message.Reauth -> {
                    InlineBanner(stringResource(R.string.account_reauth), BannerKind.Info)
                    TextButton(onClick = onSignInAgain, modifier = Modifier.heightIn(min = MinTouchTarget)) { Text(stringResource(R.string.account_sign_in_again)) }
                }
                AccountViewModel.Message.None -> Unit
            }
            TextButton(onClick = { confirmDelete = true }, enabled = !s.working, modifier = Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.account_delete), color = ColorTokens.StateDanger.resolve())
            }
            TokenText(stringResource(R.string.account_delete_note), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
    if (confirmDelete) {
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.account_delete_confirm)) },
            text = { Text(stringResource(R.string.account_delete_text)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    vm.delete()
                }) { Text(stringResource(R.string.account_delete_for_good), color = ColorTokens.StateDanger.resolve()) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.profile_cancel)) } },
        )
    }
}
