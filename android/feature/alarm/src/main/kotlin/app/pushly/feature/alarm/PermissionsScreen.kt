package app.pushly.feature.alarm

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve

/**
 * Pre-permission explainer (P2-10, CLAUDE.md §10): shown after the first alarm is saved — never at launch — and from
 * health warnings. Each step says why it is needed, then opens the system dialog or settings page.
 */
@Composable
fun PermissionsScreen(modifier: Modifier = Modifier, onDone: () -> Unit) {
    val context = LocalContext.current
    var refresh by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        refresh++
        onPauseOrDispose { }
    }
    val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        refresh++
        if (!granted) runCatching { context.startActivity(AlarmPermissions.settingsIntent(context, AlarmPermissions.Step.Notifications)) }
    }
    val steps = AlarmPermissions.steps()
    // Re-read grants whenever we come back from a system dialog or settings page.
    val granted = remember(refresh) { steps.associateWith { AlarmPermissions.isGranted(context, it) } }
    val missing = steps.filter { it != AlarmPermissions.Step.Battery && granted[it] != true }

    ArenaBackground(modifier, glow = ColorTokens.BrandVolt, glowOffset = DpOffset(0.dp, (-200).dp)) {
        Column(Modifier.fillMaxSize().padding(SpacingTokens.L)) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            ) {
                ScreenTitle(stringResource(R.string.perm_title), token = TypographyTokens.DisplayXl)
                TokenText(stringResource(R.string.perm_text), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                steps.forEach { step ->
                    val isGranted = granted[step] == true
                    PushlyCard(padding = SpacingTokens.M) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                                TokenText(stringResource(stepTitle(step)), TypographyTokens.TitleS)
                                TokenText(stringResource(stepText(step)), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                            }
                            if (isGranted) {
                                Pill(stringResource(R.string.perm_done), color = ColorTokens.StateSuccessText)
                            } else {
                                SecondaryButton(stringResource(R.string.perm_allow), modifier = Modifier.widthIn(max = 120.dp), onClick = {
                                    if (step == AlarmPermissions.Step.Notifications && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                        notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                    } else {
                                        runCatching { context.startActivity(AlarmPermissions.settingsIntent(context, step)) }
                                    }
                                })
                            }
                        }
                    }
                }
                if (missing.isNotEmpty()) InlineBanner(stringResource(R.string.perm_missing_warning), BannerKind.Warning)
            }
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                PrimaryButton(stringResource(R.string.perm_continue), onClick = onDone, enabled = missing.isEmpty())
                if (missing.isNotEmpty()) GhostButton(stringResource(R.string.perm_later), onClick = onDone, modifier = Modifier.align(Alignment.CenterHorizontally))
            }
        }
    }
}

private fun stepTitle(step: AlarmPermissions.Step) = when (step) {
    AlarmPermissions.Step.Notifications -> R.string.perm_notifications
    AlarmPermissions.Step.ExactAlarms -> R.string.perm_exact
    AlarmPermissions.Step.FullScreen -> R.string.perm_fullscreen
    AlarmPermissions.Step.Battery -> R.string.perm_battery
}

private fun stepText(step: AlarmPermissions.Step) = when (step) {
    AlarmPermissions.Step.Notifications -> R.string.perm_notifications_text
    AlarmPermissions.Step.ExactAlarms -> R.string.perm_exact_text
    AlarmPermissions.Step.FullScreen -> R.string.perm_fullscreen_text
    AlarmPermissions.Step.Battery -> R.string.perm_battery_text
}
