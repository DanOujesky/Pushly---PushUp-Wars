package app.pushly.feature.profile

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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.common.ProfileVisibility
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.resolve

@Composable
fun ProfileScreen(vm: ProfileViewModel, appVersion: String, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    var confirmSignOut by remember { mutableStateOf(false) }

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.Gutter),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
    ) {
        Text(stringResource(R.string.profile_title), style = MaterialTheme.typography.headlineLarge)

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            val name = s.profile?.username ?: stringResource(R.string.profile_guest)
            Avatar(name, s.profile?.avatarPreset, size = 64.dp)
            Column {
                Text(name, style = MaterialTheme.typography.titleLarge)
                s.profile?.let {
                    Text(stringResource(R.string.profile_level_trophies, it.level, it.trophies),
                        style = MaterialTheme.typography.bodyMedium, color = ColorTokens.TextSecondary.resolve())
                }
            }
        }

        val profile = s.profile
        if (profile == null) {
            PushlyCard {
                Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                    Text(stringResource(R.string.profile_guest_text), style = MaterialTheme.typography.bodyMedium)
                    SecondaryButton(stringResource(R.string.profile_create_account), vm::createAccount)
                }
            }
        } else {
            Text(stringResource(R.string.profile_privacy).uppercase(), style = MaterialTheme.typography.labelMedium,
                color = ColorTokens.TextSecondary.resolve())
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
                            RadioButton(selected = profile.profileVisibility == value, onClick = null)
                            Text(stringResource(label), modifier = Modifier.padding(start = SpacingTokens.S))
                        }
                    }
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)
                            .toggleable(profile.leaderboardVisible, role = Role.Switch) { vm.setLeaderboardVisible(it) },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.profile_leaderboard), modifier = Modifier.weight(1f))
                        Switch(checked = profile.leaderboardVisible, onCheckedChange = null)
                    }
                    Text(stringResource(R.string.profile_leaderboard_hint), style = MaterialTheme.typography.bodySmall,
                        color = ColorTokens.TextSecondary.resolve())
                }
            }
            s.failure?.let {
                InlineBanner(stringResource(if (it == ProfileViewModel.Failure.Network) R.string.profile_save_failed_network else R.string.profile_save_failed))
            }
            TextButton(onClick = { confirmSignOut = true }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.profile_sign_out), color = ColorTokens.StateDanger.resolve())
            }
        }

        Text(stringResource(R.string.profile_version, appVersion), style = MaterialTheme.typography.bodySmall,
            color = ColorTokens.TextTertiary.resolve())
    }

    if (confirmSignOut) {
        AlertDialog(
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
