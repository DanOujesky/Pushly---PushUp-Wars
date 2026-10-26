package app.pushly.feature.onboarding

import android.annotation.SuppressLint
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.width
import androidx.compose.material3.TextButton
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import app.pushly.core.common.LegalLinks
import app.pushly.core.designsystem.LogoMark
import app.pushly.core.designsystem.Wordmark
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.common.AccountRules
import app.pushly.core.common.LegalLinks
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.AvatarPreset
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.FieldStatus
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.GlowSpot
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.PageDots
import app.pushly.core.designsystem.PickerField
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.PushlyTextField
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.Wordmark
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TouchTarget
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.heroBrush
import app.pushly.core.designsystem.resolve
import app.pushly.core.designsystem.toTextStyle
import kotlinx.coroutines.launch

// ============================================================================ Welcome

private data class WelcomePage(val title: Int, val text: Int, val glow: TokenColor)

/** Three short value screens (doc 02 PS-01), swipeable and skippable. */
@Composable
fun WelcomeScreen(onContinue: () -> Unit) {
    val pages = listOf(
        WelcomePage(R.string.welcome_1_title, R.string.welcome_1_text, ColorTokens.BrandFlame),
        WelcomePage(R.string.welcome_2_title, R.string.welcome_2_text, ColorTokens.BrandVolt),
        WelcomePage(R.string.welcome_3_title, R.string.welcome_3_text, ColorTokens.BrandCyan),
    )
    val pager = rememberPagerState { pages.size }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(ColorTokens.BgBase.resolve()).safeDrawingPadding()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.S),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Wordmark()
            Spacer(Modifier.weight(1f))
            // Skip goes to the last page: "Get started" there is the Terms / health acceptance (doc 16 §3).
            if (pager.currentPage < pages.lastIndex) {
                GhostButton(stringResource(R.string.welcome_skip), onClick = { scope.launch { pager.animateScrollToPage(pages.lastIndex) } })
            }
        }
        HorizontalPager(state = pager, modifier = Modifier.weight(1f)) { index ->
            val page = pages[index]
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.L),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xl - 4.dp),
            ) {
                WelcomeHero(index, page.glow)
                Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    ScreenTitle(stringResource(page.title))
                    TokenText(stringResource(page.text), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                }
            }
        }
        Column(
            Modifier.padding(horizontal = SpacingTokens.L).padding(bottom = SpacingTokens.M),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PageDots(pages.size, pager.currentPage)
            val last = pager.currentPage == pages.lastIndex
            if (last) LegalNotice()
            PrimaryButton(
                text = stringResource(if (last) R.string.welcome_get_started else R.string.welcome_next),
                onClick = { if (last) onContinue() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
            )
        }
    }
}

@Composable
private fun LegalNotice() {
    val uri = LocalUriHandler.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(stringResource(R.string.welcome_health_notice), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        TokenText(stringResource(R.string.welcome_terms_notice), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
            LegalLink(stringResource(R.string.welcome_terms)) { uri.openUri(LegalLinks.TERMS) }
            LegalLink(stringResource(R.string.welcome_privacy)) { uri.openUri(LegalLinks.PRIVACY) }
        }
    }
}

@Composable
private fun LegalLink(text: String, onClick: () -> Unit) {
    TokenText(
        text,
        TypographyTokens.BodyS,
        color = ColorTokens.BrandVoltText.resolve(),
        modifier = Modifier
            .heightIn(min = TouchTarget.Minimum)
            .clickable(role = Role.Button, onClick = onClick)
            .wrapContentHeight(Alignment.CenterVertically),
    )
}

@Composable
private fun WelcomeHero(index: Int, glow: TokenColor) {
    val shape = RoundedCornerShape(RadiusTokens.Xl)
    Box(
        Modifier
            .fillMaxWidth()
            .height(300.dp)
            .clip(shape)
            .background(ColorTokens.BgSurface.resolve())
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        GlowSpot(glow, size = 380.dp, intensity = 0.32f)
        when (index) {
            0 -> AlarmHero()
            1 -> BattleHero()
            else -> ClanHero()
        }
    }
}

/** Display numerals at a fixed size: illustrations must not reflow with font scale. */
@Composable
private fun fixedSp(size: Dp) = with(LocalDensity.current) { size.toSp() }

@Composable
private fun AlarmHero() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        TokenText(
            stringResource(R.string.welcome_hero_alarm),
            TypographyTokens.Overline,
            color = ColorTokens.BrandFlameText.resolve(),
            modifier = Modifier
                .clip(CircleShape)
                .background(ColorTokens.BrandFlame.resolve().copy(alpha = 0.14f))
                .padding(horizontal = SpacingTokens.Sm, vertical = SpacingTokens.Xs + 2.dp),
        )
        val big = fixedSp(140.dp)
        Text("14", color = ColorTokens.TextPrimary.resolve(), style = TypographyTokens.DisplayCounter.toTextStyle().copy(fontSize = big, lineHeight = big))
        TokenText(stringResource(R.string.welcome_hero_of_pushups), TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve())
        GradientProgressBar(0.7f, Modifier.width(220.dp).padding(top = SpacingTokens.Sm))
    }
}

@Composable
private fun BattleHero() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        Pill(stringResource(R.string.welcome_hero_live), color = ColorTokens.BrandVoltText)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            Fighter(stringResource(R.string.welcome_hero_you), "18", AvatarPreset.Flame.id)
            val vs = fixedSp(28.dp)
            Text(stringResource(R.string.welcome_hero_vs), color = ColorTokens.TextTertiary.resolve(), style = TypographyTokens.DisplayWordmark.toTextStyle().copy(fontSize = vs))
            Fighter(stringResource(R.string.welcome_hero_rival), "15", AvatarPreset.Volt.id)
        }
    }
}

@Composable
private fun Fighter(name: String, score: String, preset: String) {
    Column(Modifier.width(100.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Avatar(name, preset, size = 64.dp)
        val big = fixedSp(64.dp)
        Text(score, color = ColorTokens.TextPrimary.resolve(), style = TypographyTokens.Stat.toTextStyle().copy(fontSize = big, lineHeight = big))
        TokenText(name, TypographyTokens.Overline, color = ColorTokens.TextSecondary.resolve())
    }
}

@Composable
private fun ClanHero() {
    Column(Modifier.fillMaxWidth().padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        TokenText(stringResource(R.string.welcome_hero_clan_war), TypographyTokens.Overline, color = ColorTokens.BrandCyan.resolve())
        ClanRow(stringResource(R.string.welcome_hero_clan_1), "4,210", 1f, highlight = true)
        ClanRow(stringResource(R.string.welcome_hero_clan_2), "3,980", 0.94f, highlight = false)
    }
}

@Composable
private fun ClanRow(name: String, total: String, share: Float, highlight: Boolean) {
    val color = (if (highlight) ColorTokens.TextPrimary else ColorTokens.TextSecondary).resolve()
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Row(verticalAlignment = Alignment.Bottom) {
            TokenText(name, TypographyTokens.TitleS, color = color, modifier = Modifier.weight(1f))
            val big = fixedSp(36.dp)
            Text(total, color = color, style = TypographyTokens.Stat.toTextStyle().copy(fontSize = big, lineHeight = big))
        }
        GradientProgressBar(share, Modifier.alpha(if (highlight) 1f else 0.45f), height = 10.dp)
    }
}

// ============================================================================ Sign in

/**
 * Sign-in (doc 02 PS-02, D-078): brand header, what an account keeps, a card with Continue with Google (the official
 * "G" from Google Play services) and email, legal line, guest at the bottom. Same layout as iOS `SignInView`.
 */
@Composable
fun SignInScreen(
    vm: SignInViewModel,
    onGuest: () -> Unit,
    linkFailed: Boolean = false,
    /** Google sign-in done by the app (Credential Manager); returns an ID token or null when cancelled. */
    google: (suspend () -> String?)? = null,
    /** Google sign-in in the browser — used when the native sheet fails (D-078). */
    googleBrowser: (suspend () -> Unit)? = null,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    val uri = LocalUriHandler.current
    ArenaBackground(glow = ColorTokens.BrandVolt, glowAlignment = Alignment.TopEnd, glowOffset = DpOffset(220.dp, (-220).dp)) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = SpacingTokens.L)
                    .padding(top = SpacingTokens.Xl, bottom = SpacingTokens.L),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
            ) {
                when (val step = s.step) {
                    SignInViewModel.Step.EnterEmail -> Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
                            modifier = Modifier.clearAndSetSemantics {}) {
                            LogoMark(size = 44.dp)
                            Wordmark(token = TypographyTokens.TitleL)
                        }
                        ScreenTitle(stringResource(R.string.signin_title), token = TypographyTokens.DisplayXl)
                        TokenText(stringResource(R.string.signin_subtitle), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                            Perk("🏆", stringResource(R.string.signin_perk_trophies), Modifier.weight(1f))
                            Perk("⚔️", stringResource(R.string.signin_perk_battles), Modifier.weight(1f))
                            Perk("🛡️", stringResource(R.string.signin_perk_clans), Modifier.weight(1f))
                        }
                    }
                    is SignInViewModel.Step.EnterCode -> Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                        Box(
                            Modifier.size(72.dp).clip(RoundedCornerShape(22.dp)).background(heroBrush()).clearAndSetSemantics {},
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("✉", color = Color.White, style = TypographyTokens.DisplayM.toTextStyle())
                        }
                        Spacer(Modifier.height(SpacingTokens.S))
                        ScreenTitle(stringResource(R.string.signin_inbox_title), token = TypographyTokens.DisplayXl)
                        TokenText(stringResource(R.string.signin_code_sent, step.email), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                    }
                }

                if (!s.isBackendAvailable) InlineBanner(stringResource(R.string.signin_no_backend), BannerKind.Warning)
                if (linkFailed) InlineBanner(stringResource(R.string.signin_link_failed))
                s.failure?.let { InlineBanner(stringResource(it.messageRes())) }

                when (s.step) {
                    SignInViewModel.Step.EnterEmail -> Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.Xl)).background(ColorTokens.BgSurface.resolve())
                            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), RoundedCornerShape(RadiusTokens.Xl))
                            .padding(SpacingTokens.L),
                        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
                    ) {
                        if (google != null && s.isBackendAvailable) {
                            val scope = rememberCoroutineScope()
                            GoogleButton(enabled = !s.isWorking) {
                                scope.launch {
                                    try {
                                        google()?.let(vm::signInWithGoogle)
                                    } catch (e: kotlinx.coroutines.CancellationException) {
                                        throw e
                                    } catch (e: Exception) {
                                        // native sheet unavailable (e.g. no Google account / app not registered) → browser
                                        val browser = googleBrowser
                                        if (browser != null) {
                                            runCatching { browser() }.onFailure { vm.googleFailed() }
                                        } else {
                                            vm.googleFailed()
                                        }
                                    }
                                }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                                Box(Modifier.weight(1f).height(1.dp).background(ColorTokens.StrokeSubtle.resolve()))
                                TokenText(stringResource(R.string.signin_or_email), TypographyTokens.Overline, color = ColorTokens.TextDisabled.resolve())
                                Box(Modifier.weight(1f).height(1.dp).background(ColorTokens.StrokeSubtle.resolve()))
                            }
                        }
                        PushlyTextField(
                            s.email,
                            vm::onEmailChange,
                            stringResource(R.string.signin_email),
                            placeholder = stringResource(R.string.signin_email_placeholder),
                            keyboardType = KeyboardType.Email,
                        )
                        PrimaryButton(stringResource(R.string.signin_send_code), vm::sendCode, enabled = s.canSendCode, loading = s.isWorking)
                        TokenText(stringResource(R.string.signin_email_hint), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    }
                    is SignInViewModel.Step.EnterCode -> Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                        PushlyTextField(
                            s.code,
                            vm::onCodeChange,
                            stringResource(R.string.signin_code),
                            placeholder = stringResource(R.string.signin_code_placeholder),
                            keyboardType = KeyboardType.NumberPassword,
                        )
                        PrimaryButton(stringResource(R.string.signin_verify), vm::verify, enabled = s.canVerify, loading = s.isWorking)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            GhostButton(stringResource(R.string.signin_other_email), onClick = vm::changeEmail)
                            GhostButton(stringResource(R.string.signin_resend), onClick = vm::sendCodeAgain)
                        }
                    }
                }
                if (s.step == SignInViewModel.Step.EnterEmail) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                        TokenText(stringResource(R.string.signin_legal), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                        TextButton(onClick = { uri.openUri(LegalLinks.TERMS) }) {
                            TokenText(stringResource(R.string.signin_terms), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
                        }
                        TokenText("·", TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                        TextButton(onClick = { uri.openUri(LegalLinks.PRIVACY) }) {
                            TokenText(stringResource(R.string.signin_privacy), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
                        }
                    }
                }
            }
            GhostButton(
                stringResource(R.string.signin_guest),
                onClick = onGuest,
                modifier = Modifier.fillMaxWidth().padding(horizontal = SpacingTokens.L).padding(bottom = SpacingTokens.S),
            )
        }
    }
}

@Composable
private fun Perk(glyph: String, label: String, modifier: Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.8f))
            .padding(vertical = SpacingTokens.Sm, horizontal = SpacingTokens.Xs).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        TokenText(glyph, TypographyTokens.TitleL, modifier = Modifier.clearAndSetSemantics {})
        TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center, maxLines = 2)
    }
}

/**
 * "Continue with Google" in Google's light style: white, the official multicolour "G" (shipped with Google Play
 * services as `googleg_standard_color_18`, looked up by name) and dark text. Without the asset: text only.
 */
@Composable
private fun GoogleButton(enabled: Boolean, onClick: () -> Unit) {
    val context = LocalContext.current
    @SuppressLint("DiscouragedApi")
    val logo = remember { context.resources.getIdentifier("googleg_standard_color_18", "drawable", context.packageName) }
    val shape = RoundedCornerShape(RadiusTokens.M)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(shape).background(Color.White)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = SpacingTokens.L),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (logo != 0) {
            Image(painterResource(logo), contentDescription = null, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(SpacingTokens.Sm))
        }
        Text(stringResource(R.string.signin_google), color = Color(0xFF1F1F1F), style = TypographyTokens.Button.toTextStyle())
    }
}

private fun SignInViewModel.Failure.messageRes(): Int = when (this) {
    SignInViewModel.Failure.InvalidCode -> R.string.signin_error_code
    SignInViewModel.Failure.Network -> R.string.error_network
    SignInViewModel.Failure.BackendUnavailable -> R.string.signin_error_backend
    SignInViewModel.Failure.Generic -> R.string.error_generic
}

// ============================================================================ Profile setup

/** Profile setup after the first sign-in (doc 02 PS-03). */
@Composable
fun ProfileSetupScreen(vm: ProfileSetupViewModel) {
    val s by vm.state.collectAsStateWithLifecycle()
    val countries = remember { CountryList.all() }
    val country = countries.firstOrNull { it.code == s.country }
    Column(Modifier.fillMaxSize().background(ColorTokens.BgBase.resolve()).safeDrawingPadding()) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SpacingTokens.L)
                .padding(top = SpacingTokens.Xl, bottom = SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                SectionLabel(stringResource(R.string.setup_step), color = ColorTokens.BrandFlameText)
                ScreenTitle(stringResource(R.string.setup_title))
            }

            PushlyCard(padding = SpacingTokens.M, modifier = Modifier.clearAndSetSemantics {}) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                    Avatar(s.username.ifEmpty { "?" }, s.presetId, size = 72.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                        TokenText(s.username.ifEmpty { "—" }, TypographyTokens.Name, maxLines = 1)
                        TokenText(
                            country?.let { "${it.flag} ${it.name}" } ?: stringResource(R.string.setup_new_fighter),
                            TypographyTokens.BodyS,
                            color = ColorTokens.TextSecondary.resolve(),
                        )
                    }
                }
            }

            val (message, status) = usernameMessage(s.availability)
            PushlyTextField(s.username, vm::onUsernameChange, stringResource(R.string.setup_username), message = message, status = status)

            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                SectionLabel(stringResource(R.string.setup_avatar))
                AvatarPreset.entries.chunked(4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                        row.forEach { preset -> Swatch(preset, selected = preset.id == s.presetId) { vm.onPresetChange(preset.id) } }
                    }
                }
            }

            BoxWithConstraints {
                val stacked = maxWidth < 320.dp || LocalDensity.current.fontScale > 1.4f
                val countryField: @Composable (Modifier) -> Unit = { m ->
                    Dropdown(
                        label = stringResource(R.string.setup_country),
                        value = country?.let { "${it.flag} ${it.name}" } ?: stringResource(R.string.setup_country_not_set),
                        options = listOf(null to stringResource(R.string.setup_country_not_set)) +
                            countries.map { it.code to "${it.flag} ${it.name}" },
                        onSelect = vm::onCountryChange,
                        modifier = m,
                    )
                }
                val yearField: @Composable (Modifier) -> Unit = { m ->
                    Dropdown(
                        label = stringResource(R.string.setup_birth_year),
                        value = s.birthYear?.toString() ?: stringResource(R.string.setup_birth_year_select),
                        options = vm.birthYearOptions.map { it to it.toString() },
                        onSelect = vm::onBirthYearChange,
                        modifier = m,
                    )
                }
                if (stacked) {
                    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                        countryField(Modifier.fillMaxWidth())
                        yearField(Modifier.fillMaxWidth())
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                        countryField(Modifier.weight(1f))
                        yearField(Modifier.weight(1f))
                    }
                }
            }
            TokenText(stringResource(R.string.setup_birth_year_hint), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())

            s.failure?.let { InlineBanner(stringResource(it.messageRes())) }
        }
        PrimaryButton(
            stringResource(R.string.setup_continue),
            vm::submit,
            enabled = vm.canSubmit,
            loading = s.isSaving,
            modifier = Modifier.padding(horizontal = SpacingTokens.L).padding(bottom = SpacingTokens.S),
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Swatch(preset: AvatarPreset, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.S)
    val label = stringResource(preset.nameRes)
    val hint = stringResource(R.string.setup_avatar_hint)
    Box(
        Modifier
            .weight(1f)
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(preset.color.resolve())
            .border(if (selected) 3.dp else 0.dp, ColorTokens.TextPrimary.resolve(), shape)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .semantics {
                this.selected = selected
                contentDescription = "$label, $hint"
            },
        contentAlignment = Alignment.Center,
    ) {
        if (selected) Text("✓", color = Color.White, style = TypographyTokens.TitleM.toTextStyle())
    }
}

@Composable
private fun usernameMessage(a: ProfileSetupViewModel.Availability): Pair<String, FieldStatus> = when (a) {
    ProfileSetupViewModel.Availability.Idle -> stringResource(R.string.username_hint) to FieldStatus.Normal
    ProfileSetupViewModel.Availability.Checking -> stringResource(R.string.username_checking) to FieldStatus.Normal
    ProfileSetupViewModel.Availability.Available -> stringResource(R.string.username_available) to FieldStatus.Success
    ProfileSetupViewModel.Availability.Taken -> stringResource(R.string.username_taken) to FieldStatus.Error
    ProfileSetupViewModel.Availability.Unknown -> stringResource(R.string.username_unknown) to FieldStatus.Normal
    is ProfileSetupViewModel.Availability.Invalid -> stringResource(
        when (a.error) {
            AccountRules.UsernameError.TooShort -> R.string.username_too_short
            AccountRules.UsernameError.TooLong -> R.string.username_too_long
            AccountRules.UsernameError.InvalidCharacters -> R.string.username_invalid
            AccountRules.UsernameError.Reserved -> R.string.username_reserved
        },
    ) to FieldStatus.Error
}

private fun ProfileSetupViewModel.Failure.messageRes(): Int = when (this) {
    ProfileSetupViewModel.Failure.UsernameTaken -> R.string.setup_error_taken
    ProfileSetupViewModel.Failure.TooYoung -> R.string.setup_error_young
    ProfileSetupViewModel.Failure.Network -> R.string.error_network
    ProfileSetupViewModel.Failure.Generic -> R.string.error_generic
}

@Composable
private fun <T> Dropdown(label: String, value: String, options: List<Pair<T, String>>, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        PickerField(label, value, onClick = { open = true })
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            modifier = Modifier.background(ColorTokens.BgElevated.resolve()).heightIn(max = 420.dp),
        ) {
            options.forEachIndexed { i, (option, text) ->
                if (i == 1 && options.size > 1) HorizontalDivider(color = ColorTokens.StrokeSubtle.resolve())
                DropdownMenuItem(
                    text = { TokenText(text, TypographyTokens.Body) },
                    onClick = {
                        onSelect(option)
                        open = false
                    },
                )
            }
        }
    }
}
