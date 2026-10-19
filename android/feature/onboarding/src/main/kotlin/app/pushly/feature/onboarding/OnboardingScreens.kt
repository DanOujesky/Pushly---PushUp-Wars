package app.pushly.feature.onboarding

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.AvatarPreset
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyTextField
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.launch

/** Three short value screens (doc 02 PS-01). */
@Composable
fun WelcomeScreen(onContinue: () -> Unit) {
    val pages = listOf(
        Triple(R.string.welcome_1_title, R.string.welcome_1_text, ColorTokens.BrandFlame),
        Triple(R.string.welcome_2_title, R.string.welcome_2_text, ColorTokens.BrandVolt),
        Triple(R.string.welcome_3_title, R.string.welcome_3_text, ColorTokens.BrandLime),
    )
    val pager = rememberPagerState { pages.size }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.Gutter)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = onContinue) { Text(stringResource(R.string.welcome_skip)) }
        }
        HorizontalPager(state = pager, modifier = Modifier.weight(1f)) { index ->
            val (title, text, color) = pages[index]
            Column(
                Modifier.fillMaxSize().padding(horizontal = SpacingTokens.L),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(Modifier.size(120.dp).padding(SpacingTokens.M)) {
                    Avatar(username = "P", presetId = AvatarPreset.entries[index].id, size = 96.dp)
                }
                Spacer(Modifier.height(SpacingTokens.L))
                Text(stringResource(title), style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center,
                    color = color.resolve())
                Spacer(Modifier.height(SpacingTokens.S))
                Text(stringResource(text), style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center,
                    color = ColorTokens.TextSecondary.resolve())
            }
        }
        val last = pager.currentPage == pages.lastIndex
        PrimaryButton(
            text = stringResource(if (last) R.string.welcome_get_started else R.string.welcome_next),
            onClick = { if (last) onContinue() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
        )
    }
}

/** Sign-in (doc 02 PS-02): email one-time code, or continue as guest (alarm only). */
@Composable
fun SignInScreen(vm: SignInViewModel, onGuest: () -> Unit) {
    val s by vm.state.collectAsStateWithLifecycle()
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(SpacingTokens.Gutter),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Text(stringResource(R.string.signin_title), style = MaterialTheme.typography.headlineLarge)
        Text(stringResource(R.string.signin_subtitle), style = MaterialTheme.typography.bodyLarge,
            color = ColorTokens.TextSecondary.resolve())
        if (!s.isBackendAvailable) InlineBanner(stringResource(R.string.signin_no_backend), BannerKind.Warning)
        s.failure?.let { InlineBanner(stringResource(it.messageRes())) }

        when (val step = s.step) {
            SignInViewModel.Step.EnterEmail -> {
                PushlyTextField(s.email, vm::onEmailChange, stringResource(R.string.signin_email), keyboardType = KeyboardType.Email)
                PrimaryButton(stringResource(R.string.signin_send_code), vm::sendCode, enabled = s.canSendCode, loading = s.isWorking)
            }
            is SignInViewModel.Step.EnterCode -> {
                Text(stringResource(R.string.signin_code_sent, step.email), style = MaterialTheme.typography.bodyLarge)
                PushlyTextField(s.code, vm::onCodeChange, stringResource(R.string.signin_code), keyboardType = KeyboardType.NumberPassword)
                PrimaryButton(stringResource(R.string.signin_verify), vm::verify, enabled = s.canVerify, loading = s.isWorking)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(onClick = vm::changeEmail) { Text(stringResource(R.string.signin_other_email)) }
                    TextButton(onClick = vm::sendCodeAgain) { Text(stringResource(R.string.signin_resend)) }
                }
            }
        }

        TextButton(onClick = onGuest, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.signin_guest), color = ColorTokens.TextSecondary.resolve())
        }
    }
}

private fun SignInViewModel.Failure.messageRes(): Int = when (this) {
    SignInViewModel.Failure.InvalidCode -> R.string.signin_error_code
    SignInViewModel.Failure.Network -> R.string.error_network
    SignInViewModel.Failure.BackendUnavailable -> R.string.signin_error_backend
    SignInViewModel.Failure.Generic -> R.string.error_generic
}

/** Profile setup after the first sign-in (doc 02 PS-03). */
@Composable
fun ProfileSetupScreen(vm: ProfileSetupViewModel) {
    val s by vm.state.collectAsStateWithLifecycle()
    val countries = remember { CountryList.all() }
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(SpacingTokens.Gutter),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
    ) {
        Text(stringResource(R.string.setup_title), style = MaterialTheme.typography.headlineLarge)
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Avatar(s.username.ifEmpty { "?" }, s.presetId, size = 88.dp)
        }

        Section(stringResource(R.string.setup_username)) {
            val (message, isError) = usernameMessage(s.availability)
            PushlyTextField(s.username, vm::onUsernameChange, stringResource(R.string.setup_username), message = message, isError = isError)
        }

        Section(stringResource(R.string.setup_avatar)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                AvatarPreset.entries.forEachIndexed { index, preset ->
                    val selected = preset.id == s.presetId
                    val label = stringResource(R.string.setup_avatar_option, index + 1)
                    Box(
                        Modifier
                            .size(MinTouchTarget)
                            .border(if (selected) 3.dp else 0.dp, ColorTokens.TextPrimary.resolve(), CircleShape)
                            .clickable(role = Role.RadioButton) { vm.onPresetChange(preset.id) }
                            .semantics { this.selected = selected; contentDescription = label },
                        contentAlignment = Alignment.Center,
                    ) { Avatar(s.username.ifEmpty { "?" }, preset.id, size = 36.dp) }
                }
            }
        }

        Section(stringResource(R.string.setup_country)) {
            val current = countries.firstOrNull { it.code == s.country }
            Dropdown(
                label = current?.let { "${it.flag} ${it.name}" } ?: stringResource(R.string.setup_country_not_set),
                options = listOf(null to stringResource(R.string.setup_country_not_set)) + countries.map { it.code to "${it.flag} ${it.name}" },
                onSelect = vm::onCountryChange,
            )
        }

        Section(stringResource(R.string.setup_birth_year)) {
            Dropdown(
                label = s.birthYear?.toString() ?: stringResource(R.string.setup_birth_year_select),
                options = vm.birthYearOptions.map { it to it.toString() },
                onSelect = vm::onBirthYearChange,
            )
            Text(stringResource(R.string.setup_birth_year_hint), style = MaterialTheme.typography.bodySmall,
                color = ColorTokens.TextSecondary.resolve())
        }

        s.failure?.let { InlineBanner(stringResource(it.messageRes())) }

        PrimaryButton(stringResource(R.string.setup_continue), vm::submit, enabled = vm.canSubmit, loading = s.isSaving)
    }
}

@Composable
private fun usernameMessage(a: ProfileSetupViewModel.Availability): Pair<String, Boolean> = when (a) {
    ProfileSetupViewModel.Availability.Idle -> stringResource(R.string.username_hint) to false
    ProfileSetupViewModel.Availability.Checking -> stringResource(R.string.username_checking) to false
    ProfileSetupViewModel.Availability.Available -> stringResource(R.string.username_available) to false
    ProfileSetupViewModel.Availability.Taken -> stringResource(R.string.username_taken) to true
    ProfileSetupViewModel.Availability.Unknown -> stringResource(R.string.username_unknown) to false
    is ProfileSetupViewModel.Availability.Invalid -> stringResource(
        when (a.error) {
            app.pushly.core.common.AccountRules.UsernameError.TooShort -> R.string.username_too_short
            app.pushly.core.common.AccountRules.UsernameError.TooLong -> R.string.username_too_long
            app.pushly.core.common.AccountRules.UsernameError.InvalidCharacters -> R.string.username_invalid
            app.pushly.core.common.AccountRules.UsernameError.Reserved -> R.string.username_reserved
        },
    ) to true
}

private fun ProfileSetupViewModel.Failure.messageRes(): Int = when (this) {
    ProfileSetupViewModel.Failure.UsernameTaken -> R.string.setup_error_taken
    ProfileSetupViewModel.Failure.TooYoung -> R.string.setup_error_young
    ProfileSetupViewModel.Failure.Network -> R.string.error_network
    ProfileSetupViewModel.Failure.Generic -> R.string.error_generic
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, color = ColorTokens.TextSecondary.resolve())
        content()
    }
}

@Composable
private fun <T> Dropdown(label: String, options: List<Pair<T, String>>, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { open = true }, modifier = Modifier.fillMaxWidth().height(52.dp)) {
            Text(label, modifier = Modifier.fillMaxWidth(), color = ColorTokens.TextPrimary.resolve())
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEachIndexed { i, (value, text) ->
                if (i == 1 && options.size > 1) HorizontalDivider()
                DropdownMenuItem(text = { Text(text) }, onClick = {
                    onSelect(value)
                    open = false
                })
            }
        }
    }
}
