package app.pushly.core.designsystem

import androidx.annotation.StringRes
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.GradientTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TouchTarget
import app.pushly.core.designsystem.generated.TypeToken
import app.pushly.core.designsystem.generated.TypographyTokens

// Pushly "arena" components (doc 14 §4). Same set and look as iOS DesignSystem/Components.swift.

@Composable
fun heroBrush(): Brush {
    val colors = GradientTokens.Hero.stops.map { it.resolve() }
    return Brush.linearGradient(colors, start = Offset.Zero, end = Offset.Infinite)
}

/** Text in a type token, including its uppercase rule. */
@Composable
fun TokenText(
    text: String,
    token: TypeToken,
    modifier: Modifier = Modifier,
    color: Color = ColorTokens.TextPrimary.resolve(),
    textAlign: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
    style: TextStyle = token.toTextStyle(),
) {
    Text(token.format(text), modifier = modifier, color = color, style = style, textAlign = textAlign, maxLines = maxLines)
}

// ----------------------------------------------------------------------------- Buttons

/** Main call-to-action: hero gradient with a flame glow, 58 dp tall, full width, spinner while [loading]. */
@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, loading: Boolean = false) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, label = "press")
    val glow = ColorTokens.BrandFlame.resolve()
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 58.dp)
            .scale(scale)
            .shadow(if (enabled) 16.dp else 0.dp, shape, ambientColor = glow, spotColor = glow)
            .alpha(if (enabled) 1f else 0.4f)
            .clip(shape)
            .background(heroBrush())
            .clickable(interaction, indication = null, enabled = enabled && !loading, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (loading) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
        } else {
            TokenText(text, TypographyTokens.Button, color = Color.White, modifier = Modifier.padding(horizontal = SpacingTokens.M))
        }
    }
}

/** Secondary action: dark surface with a subtle border, same size as [PrimaryButton]. */
@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(ColorTokens.BgSurface.resolve())
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        TokenText(text, TypographyTokens.Button)
    }
}

/** Low-emphasis text action ("Skip", "Continue as guest"). */
@Composable
fun GhostButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .heightIn(min = TouchTarget.Minimum)
            .widthIn(min = TouchTarget.Minimum)
            .clip(RoundedCornerShape(RadiusTokens.S))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = SpacingTokens.S),
        contentAlignment = Alignment.Center,
    ) {
        TokenText(
            text,
            TypographyTokens.BodyS,
            color = ColorTokens.TextSecondary.resolve(),
            textAlign = TextAlign.Center,
            style = TypographyTokens.BodyS.toTextStyle().copy(fontWeight = FontWeight.SemiBold),
        )
    }
}

// ----------------------------------------------------------------------------- Text

/** Small uppercase label above a field or card ("USERNAME", "THIS WEEK"). */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier, color: TokenColor = ColorTokens.TextTertiary) {
    TokenText(text, TypographyTokens.Overline, color = color.resolve(), modifier = modifier.semantics { heading() })
}

/** Big condensed uppercase screen title ("JOIN THE ARENA"). */
@Composable
fun ScreenTitle(text: String, modifier: Modifier = Modifier, token: TypeToken = TypographyTokens.DisplayL, textAlign: TextAlign? = null) {
    TokenText(text, token, modifier = modifier.semantics { heading() }, textAlign = textAlign)
}

// ----------------------------------------------------------------------------- Fields

enum class FieldStatus { Normal, Error, Success }

/** Text field with a label above it and an optional message below (validation status colours the border). */
@Composable
fun PushlyTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    message: String? = null,
    status: FieldStatus = FieldStatus.Normal,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val border by animateColorAsState(
        when (status) {
            FieldStatus.Error -> ColorTokens.StateDanger.resolve()
            FieldStatus.Success -> ColorTokens.StateSuccess.resolve()
            FieldStatus.Normal -> if (focused) ColorTokens.BrandFlame.resolve() else ColorTokens.StrokeSubtle.resolve()
        },
        label = "border",
    )
    val shape = RoundedCornerShape(RadiusTokens.M)
    val textColor = ColorTokens.TextPrimary.resolve()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        SectionLabel(label)
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            interactionSource = interaction,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            textStyle = TypographyTokens.Body.toTextStyle().copy(color = textColor),
            cursorBrush = SolidColor(ColorTokens.BrandFlame.resolve()),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = label },
            decorationBox = { inner ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp)
                        .clip(shape)
                        .background(ColorTokens.BgSurface.resolve())
                        .border(1.5.dp, border, shape)
                        .padding(horizontal = SpacingTokens.Ml),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f)) {
                        if (value.isEmpty() && placeholder.isNotEmpty()) {
                            TokenText(placeholder, TypographyTokens.Body, color = ColorTokens.TextDisabled.resolve())
                        }
                        inner()
                    }
                    if (status == FieldStatus.Success) {
                        CheckGlyph(ColorTokens.StateSuccess.resolve(), Modifier.size(20.dp))
                    }
                }
            },
        )
        if (message != null) {
            TokenText(
                message,
                TypographyTokens.Caption,
                color = when (status) {
                    FieldStatus.Error -> ColorTokens.StateDanger
                    FieldStatus.Success -> ColorTokens.StateSuccessText
                    FieldStatus.Normal -> ColorTokens.TextTertiary
                }.resolve(),
            )
        }
    }
}

/** A tappable field that opens a picker (country, birth year) — looks like [PushlyTextField]. */
@Composable
fun PickerField(label: String, value: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        SectionLabel(label)
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .clip(shape)
                .background(ColorTokens.BgSurface.resolve())
                .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
                .clickable(role = Role.DropdownList, onClickLabel = label, onClick = onClick)
                .padding(horizontal = SpacingTokens.M),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TokenText(value, TypographyTokens.Body, maxLines = 1, modifier = Modifier.weight(1f))
            Text("▾", color = ColorTokens.TextTertiary.resolve(), style = TypographyTokens.Body.toTextStyle())
        }
    }
}

// ----------------------------------------------------------------------------- Containers

/** Card container (doc 14 §3): dark surface, 24 dp radius, hairline border. */
@Composable
fun PushlyCard(modifier: Modifier = Modifier, padding: Dp = SpacingTokens.Ml, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    Box(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(ColorTokens.BgSurface.resolve())
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(padding),
    ) { content() }
}

/** Small rounded label ("Bronze III", "20 push-ups"). [color] null = neutral glass pill. */
@Composable
fun Pill(text: String, modifier: Modifier = Modifier, color: TokenColor? = null) {
    val c = color?.resolve()
    TokenText(
        text,
        TypographyTokens.BodyS,
        color = c ?: ColorTokens.TextPrimary.resolve(),
        style = TypographyTokens.BodyS.toTextStyle().copy(fontWeight = FontWeight.Bold),
        modifier = modifier
            .clip(CircleShape)
            .background(c?.copy(alpha = 0.16f) ?: Color.White.copy(alpha = 0.08f))
            .padding(horizontal = SpacingTokens.Sm, vertical = SpacingTokens.Xs + 2.dp),
    )
}

enum class BannerKind { Error, Warning, Info, Success }

/** Inline error / warning / success message. */
@Composable
fun InlineBanner(text: String, kind: BannerKind = BannerKind.Error, modifier: Modifier = Modifier) {
    val (token, mark) = when (kind) {
        BannerKind.Error -> ColorTokens.StateDanger to "!"
        BannerKind.Warning -> ColorTokens.StateWarning to "!"
        BannerKind.Info -> ColorTokens.BrandCyan to "i"
        BannerKind.Success -> ColorTokens.StateSuccess to "✓"
    }
    val color = token.resolve()
    val shape = RoundedCornerShape(RadiusTokens.M)
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(color.copy(alpha = 0.12f))
            .border(1.dp, color.copy(alpha = 0.35f), shape)
            .padding(SpacingTokens.M),
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        Box(Modifier.size(22.dp).clip(CircleShape).background(color).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            Text(mark, color = ColorTokens.BgBase.resolve(), fontSize = 13.sp, style = TypographyTokens.Overline.toTextStyle())
        }
        TokenText(text, TypographyTokens.BodyS, modifier = Modifier.weight(1f))
    }
}

/** Gradient progress bar (rep progress, onboarding progress). */
@Composable
fun GradientProgressBar(value: Float, modifier: Modifier = Modifier, height: Dp = 8.dp) {
    val flame = ColorTokens.BrandFlame.resolve()
    val volt = ColorTokens.BrandVolt.resolve()
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(CircleShape)
            .background(ColorTokens.StrokeSubtle.resolve())
            .clearAndSetSemantics {},
    ) {
        Box(
            Modifier
                .fillMaxWidth(value.coerceIn(0f, 1f))
                .height(height)
                .clip(CircleShape)
                .background(Brush.horizontalGradient(listOf(flame, volt))),
        )
    }
}

/** Page indicator: the active page is a wide flame capsule. */
@Composable
fun PageDots(count: Int, index: Int, modifier: Modifier = Modifier) {
    Row(modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(count) { i ->
            val width by animateDpAsState(if (i == index) 24.dp else 6.dp, label = "dot")
            Box(
                Modifier
                    .width(width)
                    .height(6.dp)
                    .clip(CircleShape)
                    .background((if (i == index) ColorTokens.BrandFlame else ColorTokens.StrokeStrong).resolve()),
            )
        }
    }
}

// ----------------------------------------------------------------------------- Arena background

/** Soft radial light behind hero content. */
@Composable
fun GlowSpot(color: TokenColor = ColorTokens.BrandFlame, size: Dp = 520.dp, intensity: Float = 0.24f, modifier: Modifier = Modifier) {
    val c = color.resolve()
    Box(
        modifier
            .requiredSize(size)
            .drawBehind {
                drawCircle(
                    Brush.radialGradient(
                        listOf(c.copy(alpha = intensity), c.copy(alpha = 0f)),
                        center = center,
                        radius = this.size.minDimension * 0.33f,
                    ),
                )
            }
            .clearAndSetSemantics {},
    )
}

/** Full-screen arena background: base colour plus one glow spot, content on top. */
@Composable
fun ArenaBackground(
    modifier: Modifier = Modifier,
    glow: TokenColor = ColorTokens.BrandFlame,
    glowAlignment: Alignment = Alignment.TopCenter,
    glowOffset: DpOffset = DpOffset.Zero,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(modifier.fillMaxSize().background(ColorTokens.BgBase.resolve())) {
        GlowSpot(glow, modifier = Modifier.align(glowAlignment).offset(glowOffset.x, glowOffset.y))
        content()
    }
}

// ----------------------------------------------------------------------------- Brand

/** The Pushly mark: gradient rounded square with the push-up glyph. */
@Composable
fun LogoMark(size: Dp = 112.dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(size * 0.286f)
    val glow = ColorTokens.BrandFlame.resolve()
    Box(
        modifier
            .size(size)
            .shadow(size * 0.22f, shape, ambientColor = glow, spotColor = glow)
            .clip(shape)
            .background(heroBrush())
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        PushupGlyph(Modifier.size(size * 0.57f))
    }
}

/** Glyph drawn on a 64×64 grid (same geometry as iOS, the app icon and ic_launcher_foreground). */
@Composable
fun PushupGlyph(modifier: Modifier = Modifier, color: Color = Color.White) {
    Canvas(modifier) {
        val s = this.size.width / 64f
        val stroke = Stroke(width = 6 * s, cap = StrokeCap.Round, join = StrokeJoin.Round)
        val body = Path().apply {
            moveTo(14 * s, 40 * s); lineTo(30 * s, 40 * s); lineTo(38 * s, 28 * s); lineTo(50 * s, 28 * s)
        }
        val arrow = Path().apply { moveTo(44 * s, 20 * s); lineTo(52 * s, 28 * s); lineTo(44 * s, 36 * s) }
        drawPath(body, color, style = stroke)
        drawPath(arrow, color, style = stroke)
        drawCircle(color, radius = 6 * s, center = Offset(18 * s, 26 * s))
    }
}

@Composable
private fun CheckGlyph(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val s = this.size.width / 24f
        val path = Path().apply { moveTo(5 * s, 12.5f * s); lineTo(9.5f * s, 17 * s); lineTo(19 * s, 7.5f * s) }
        drawPath(path, color, style = Stroke(width = 2.5f * s, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** "PUSHLY" wordmark in condensed black italic. */
@Composable
fun Wordmark(modifier: Modifier = Modifier, token: TypeToken = TypographyTokens.DisplayWordmark) {
    TokenText("Pushly", token, modifier = modifier)
}

// ----------------------------------------------------------------------------- Avatars

/** Preset avatars; ids are stored in `profiles.avatar_preset` and identical on iOS (AvatarPreset). */
enum class AvatarPreset(val id: String, val color: TokenColor, @StringRes val nameRes: Int) {
    Flame("preset.flame", ColorTokens.BrandFlame, R.string.avatar_flame),
    Volt("preset.volt", ColorTokens.BrandVolt, R.string.avatar_volt),
    Lime("preset.lime", ColorTokens.BrandLime, R.string.avatar_lime),
    Cyan("preset.cyan", ColorTokens.BrandCyan, R.string.avatar_cyan),
    Gold("preset.gold", ColorTokens.LeagueGold, R.string.avatar_gold),
    Diamond("preset.diamond", ColorTokens.LeagueDiamond, R.string.avatar_diamond),
    Champion("preset.champion", ColorTokens.LeagueChampion, R.string.avatar_champion),
    Silver("preset.silver", ColorTokens.LeagueSilver, R.string.avatar_silver),
    ;

    companion object {
        val Default = Flame
        fun fromId(id: String?): AvatarPreset = entries.firstOrNull { it.id == id } ?: Default
    }
}

/** Rounded square in the preset colour with the user's initial. Decorative: screen readers skip it. */
@Composable
fun Avatar(username: String, presetId: String?, size: Dp = 56.dp, modifier: Modifier = Modifier) {
    val color = AvatarPreset.fromId(presetId).color.resolve()
    val shape = RoundedCornerShape(size * 0.3f)
    Box(
        modifier
            .size(size)
            .clip(shape)
            .background(Brush.linearGradient(listOf(color, color.copy(alpha = 0.65f))))
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        // Fixed size (not sp): the initial is a graphic and must fit the avatar at any font scale.
        val fixed = with(LocalDensity.current) { (size * 0.55f).toSp() }
        Text(
            username.take(1).uppercase(),
            color = Color.White,
            style = TypographyTokens.DisplayCounter.toTextStyle().copy(fontSize = fixed, lineHeight = fixed),
        )
    }
}

val MinTouchTarget: Dp = TouchTarget.Minimum

@Preview(showBackground = true, backgroundColor = 0xFF0A0A10)
@Composable
private fun ComponentsPreview() {
    PushlyTheme {
        Column(Modifier.padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            LogoMark(72.dp)
            ScreenTitle("Join the\narena")
            PrimaryButton("Continue", onClick = {})
            PrimaryButton("Loading", onClick = {}, loading = true)
            SecondaryButton("Secondary", onClick = {})
            GhostButton("Continue as guest", onClick = {})
            PushlyTextField("DanPushes", {}, "Username", message = "Available", status = FieldStatus.Success)
            InlineBanner("Something went wrong")
            GradientProgressBar(0.7f)
            PageDots(3, 0)
            Row { AvatarPreset.entries.forEach { Avatar("Dan", it.id, size = 36.dp) } }
            Spacer(Modifier.height(SpacingTokens.M))
        }
    }
}
