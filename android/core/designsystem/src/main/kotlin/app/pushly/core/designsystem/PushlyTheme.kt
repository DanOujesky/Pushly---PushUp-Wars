package app.pushly.core.designsystem

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.FontTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TokenFontFamily
import app.pushly.core.designsystem.generated.TokenFontWeight
import app.pushly.core.designsystem.generated.TypeToken
import app.pushly.core.designsystem.generated.TypographyTokens

/** Whether the dark token values are in use. The app is dark-only for now (D-033). */
val LocalPushlyDark = staticCompositionLocalOf { true }

/** Resolves a token color for the current theme. */
@Composable
@ReadOnlyComposable
fun TokenColor.resolve(): Color = if (LocalPushlyDark.current) dark else light

/** Compose text style for a type token (font, weight, italic, size, line height, tracking). */
fun TypeToken.toTextStyle(): TextStyle = TextStyle(
    fontFamily = when (family) {
        TokenFontFamily.Display -> FontTokens.Display
        TokenFontFamily.Text -> FontTokens.Text
    },
    fontWeight = when (weight) {
        TokenFontWeight.Regular -> FontWeight.Normal
        TokenFontWeight.Medium -> FontWeight.Medium
        TokenFontWeight.Semibold -> FontWeight.SemiBold
        TokenFontWeight.Bold -> FontWeight.Bold
        TokenFontWeight.ExtraBold -> FontWeight.ExtraBold
        TokenFontWeight.Black -> FontWeight.Black
    },
    fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal,
    fontSize = size,
    lineHeight = lineHeight,
    letterSpacing = trackingEm.em,
)

/** Applies the token's uppercase rule to display text. */
fun TypeToken.format(text: String): String = if (uppercase) text.uppercase() else text

private val PushlyTypography = Typography(
    displayLarge = TypographyTokens.DisplayXl.toTextStyle(),
    displayMedium = TypographyTokens.DisplayL.toTextStyle(),
    displaySmall = TypographyTokens.DisplayM.toTextStyle(),
    headlineLarge = TypographyTokens.TitleL.toTextStyle(),
    headlineMedium = TypographyTokens.TitleM.toTextStyle(),
    headlineSmall = TypographyTokens.TitleM.toTextStyle(),
    titleLarge = TypographyTokens.TitleM.toTextStyle(),
    titleMedium = TypographyTokens.TitleS.toTextStyle(),
    titleSmall = TypographyTokens.BodyS.toTextStyle(),
    bodyLarge = TypographyTokens.Body.toTextStyle(),
    bodyMedium = TypographyTokens.BodyS.toTextStyle(),
    bodySmall = TypographyTokens.Caption.toTextStyle(),
    labelLarge = TypographyTokens.Button.toTextStyle(),
    labelMedium = TypographyTokens.Caption.toTextStyle(),
    labelSmall = TypographyTokens.Tab.toTextStyle(),
)

/**
 * App theme. Material 3 is used for components, but every color and font comes from the generated tokens (doc 14).
 * Dark-only arena look (D-033); the light token values stay valid for a future theme setting.
 */
@Composable
fun PushlyTheme(darkTheme: Boolean = true, content: @Composable () -> Unit) {
    fun pick(t: TokenColor) = if (darkTheme) t.dark else t.light
    val base = if (darkTheme) darkColorScheme() else lightColorScheme()
    val scheme = base.copy(
        primary = pick(ColorTokens.BrandFlame),
        onPrimary = Color.White,
        secondary = pick(ColorTokens.BrandVolt),
        onSecondary = Color.White,
        tertiary = pick(ColorTokens.BrandLime),
        background = pick(ColorTokens.BgBase),
        onBackground = pick(ColorTokens.TextPrimary),
        surface = pick(ColorTokens.BgSurface),
        onSurface = pick(ColorTokens.TextPrimary),
        surfaceVariant = pick(ColorTokens.BgElevated),
        onSurfaceVariant = pick(ColorTokens.TextSecondary),
        surfaceContainer = pick(ColorTokens.BgSurface),
        surfaceContainerHigh = pick(ColorTokens.BgElevated),
        surfaceContainerHighest = pick(ColorTokens.BgElevated),
        outline = pick(ColorTokens.StrokeStrong),
        outlineVariant = pick(ColorTokens.StrokeSubtle),
        error = pick(ColorTokens.StateDanger),
    )
    CompositionLocalProvider(LocalPushlyDark provides darkTheme) {
        MaterialTheme(colorScheme = scheme, typography = PushlyTypography, content = content)
    }
}
