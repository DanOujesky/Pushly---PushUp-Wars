package app.pushly.core.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.GradientTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TouchTarget

// Phase 1 components (doc 14 §4). Same set as iOS DesignSystem/Components.swift.

@Composable
fun heroBrush(): Brush {
    val colors = GradientTokens.Hero.stops.map { it.resolve() }
    return Brush.linearGradient(colors, start = Offset.Zero, end = Offset.Infinite)
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, loading: Boolean = false) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    Button(
        onClick = onClick,
        enabled = enabled && !loading,
        shape = shape,
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Transparent,
            disabledContainerColor = Color.Transparent,
            contentColor = Color.White,
            disabledContentColor = Color.White,
        ),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        modifier = modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .alpha(if (enabled) 1f else 0.45f)
                .clip(shape)
                .background(heroBrush()),
            contentAlignment = Alignment.Center,
        ) {
            if (loading) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
            } else {
                Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    OutlinedButton(
        onClick = onClick,
        shape = RoundedCornerShape(RadiusTokens.M),
        modifier = modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = ColorTokens.TextPrimary.resolve())
    }
}

@Composable
fun PushlyTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    message: String? = null,
    isError: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    Column(modifier) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            label = { Text(label) },
            singleLine = true,
            isError = isError,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            shape = RoundedCornerShape(RadiusTokens.M),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = ColorTokens.BrandFlame.resolve(),
                unfocusedBorderColor = ColorTokens.StrokeSubtle.resolve(),
            ),
            modifier = Modifier.fillMaxWidth(),
        )
        if (message != null) {
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = if (isError) ColorTokens.StateDanger.resolve() else ColorTokens.TextSecondary.resolve(),
                modifier = Modifier.padding(top = SpacingTokens.Xs, start = SpacingTokens.Xs),
            )
        }
    }
}

@Composable
fun PushlyCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    Box(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(ColorTokens.BgSurface.resolve())
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(SpacingTokens.M),
    ) { content() }
}

enum class BannerKind { Error, Warning, Info }

@Composable
fun InlineBanner(text: String, kind: BannerKind = BannerKind.Error, modifier: Modifier = Modifier) {
    val color = when (kind) {
        BannerKind.Error -> ColorTokens.StateDanger
        BannerKind.Warning -> ColorTokens.StateWarning
        BannerKind.Info -> ColorTokens.BrandCyan
    }.resolve()
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RadiusTokens.S))
            .background(color.copy(alpha = 0.15f)),
    ) {
        Box(Modifier.width(4.dp).heightIn(min = 44.dp).background(color))
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = ColorTokens.TextPrimary.resolve(),
            modifier = Modifier.padding(SpacingTokens.Sm),
        )
    }
}

/** Preset avatars; ids are stored in `profiles.avatar_preset` and identical on iOS (AvatarPreset). */
enum class AvatarPreset(val id: String, val color: TokenColor) {
    Flame("preset.flame", ColorTokens.BrandFlame),
    Volt("preset.volt", ColorTokens.BrandVolt),
    Lime("preset.lime", ColorTokens.BrandLime),
    Cyan("preset.cyan", ColorTokens.BrandCyan),
    Gold("preset.gold", ColorTokens.LeagueGold),
    Diamond("preset.diamond", ColorTokens.LeagueDiamond),
    Champion("preset.champion", ColorTokens.LeagueChampion),
    Silver("preset.silver", ColorTokens.LeagueSilver),
    ;

    companion object {
        val Default = Flame
        fun fromId(id: String?): AvatarPreset = entries.firstOrNull { it.id == id } ?: Default
    }
}

/** Circle with the user's initial on the preset color. Decorative: screen readers skip it. */
@Composable
fun Avatar(username: String, presetId: String?, size: Dp = 56.dp, modifier: Modifier = Modifier) {
    val preset = AvatarPreset.fromId(presetId)
    Box(
        modifier.size(size).clip(CircleShape).background(preset.color.resolve()).clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Text(
            username.take(1).uppercase(),
            color = Color.White,
            fontWeight = FontWeight.Black,
            fontSize = (size.value * 0.45f).sp,
        )
    }
}

val MinTouchTarget: Dp = TouchTarget.Minimum

@Preview(showBackground = true)
@Composable
private fun ComponentsPreview() {
    PushlyTheme {
        Column(Modifier.padding(SpacingTokens.Gutter)) {
            PrimaryButton("Continue", onClick = {})
            Spacer(Modifier.height(SpacingTokens.M))
            PrimaryButton("Loading", onClick = {}, loading = true)
            Spacer(Modifier.height(SpacingTokens.M))
            SecondaryButton("Secondary", onClick = {})
            Spacer(Modifier.height(SpacingTokens.M))
            PushlyTextField("a!", {}, "Username", message = "Only letters, numbers, _ and .", isError = true)
            Spacer(Modifier.height(SpacingTokens.M))
            InlineBanner("Something went wrong")
            Spacer(Modifier.height(SpacingTokens.M))
            Row { AvatarPreset.entries.forEach { Avatar("Dan", it.id, size = 36.dp) } }
        }
    }
}
