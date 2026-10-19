package app.pushly.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.TokenColor

/** Resolves a token color for the current theme. */
@Composable
@ReadOnlyComposable
fun TokenColor.resolve(): Color = if (isSystemInDarkTheme()) dark else light

/**
 * App theme. Material 3 is used for components, but every color comes from the generated tokens (doc 14).
 */
@Composable
fun PushlyTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    fun pick(t: TokenColor) = if (darkTheme) t.dark else t.light
    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = pick(ColorTokens.BrandFlame),
            secondary = pick(ColorTokens.BrandVolt),
            tertiary = pick(ColorTokens.BrandLime),
            background = pick(ColorTokens.BgBase),
            surface = pick(ColorTokens.BgSurface),
            onBackground = pick(ColorTokens.TextPrimary),
            onSurface = pick(ColorTokens.TextPrimary),
            onSurfaceVariant = pick(ColorTokens.TextSecondary),
            outline = pick(ColorTokens.StrokeSubtle),
            error = pick(ColorTokens.StateDanger),
        )
    } else {
        lightColorScheme(
            primary = pick(ColorTokens.BrandFlame),
            secondary = pick(ColorTokens.BrandVolt),
            tertiary = pick(ColorTokens.BrandLime),
            background = pick(ColorTokens.BgBase),
            surface = pick(ColorTokens.BgSurface),
            onBackground = pick(ColorTokens.TextPrimary),
            onSurface = pick(ColorTokens.TextPrimary),
            onSurfaceVariant = pick(ColorTokens.TextSecondary),
            outline = pick(ColorTokens.StrokeSubtle),
            error = pick(ColorTokens.StateDanger),
        )
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
