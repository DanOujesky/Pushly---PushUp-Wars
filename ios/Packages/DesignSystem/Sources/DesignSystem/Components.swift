import SwiftUI

// Pushly "arena" components (doc 14 §4). Same set and look as Android core/designsystem/Components.kt.

// MARK: - Buttons

/// Main call-to-action: hero gradient with a flame glow, 58 pt tall, full width, spinner while `isLoading`.
public struct PrimaryButton: View {
    let title: LocalizedStringKey
    let isLoading: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: LocalizedStringKey, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).typography(TypographyTokens.button).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(LinearGradient(GradientTokens.hero), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
            .shadow(color: isEnabled ? Glow.flame : .clear, radius: 16, y: 12)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isLoading)
    }
}

/// Secondary action: dark surface with a subtle border, same size as `PrimaryButton`.
public struct SecondaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .typography(TypographyTokens.button)
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Low-emphasis text action ("Skip", "Continue as guest").
public struct GhostButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .typography(TypographyTokens.bodyS)
                .fontWeight(.semibold)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .multilineTextAlignment(.center)
                .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: MotionTokens.fastSeconds), value: configuration.isPressed)
    }
}

// MARK: - Text

/// Small uppercase label above a field or card ("USERNAME", "THIS WEEK").
public struct SectionLabel: View {
    let text: LocalizedStringKey
    let color: TokenColor

    public init(_ text: LocalizedStringKey, color: TokenColor = ColorTokens.textTertiary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .typography(TypographyTokens.overline)
            .foregroundStyle(Color(color))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Big condensed uppercase screen title ("JOIN THE ARENA").
public struct ScreenTitle: View {
    let text: LocalizedStringKey
    let token: TypeToken

    public init(_ text: LocalizedStringKey, token: TypeToken = TypographyTokens.displayL) {
        self.text = text
        self.token = token
    }

    public var body: some View {
        Text(text)
            .typography(token)
            .foregroundStyle(Color(ColorTokens.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Fields

/// Text field with a label above it and an optional message below (validation state colours the border).
public struct PushlyTextField: View {
    public enum Status: Sendable { case normal, error, success }

    let label: LocalizedStringKey
    /// Example input shown verbatim (not localized — e.g. "you@example.com"; avoids Markdown auto-linking).
    let placeholder: String
    @Binding var text: String
    let message: LocalizedStringKey?
    let status: Status
    @FocusState private var focused: Bool

    public init(
        _ label: LocalizedStringKey,
        placeholder: String = "",
        text: Binding<String>,
        message: LocalizedStringKey? = nil,
        status: Status = .normal
    ) {
        self.label = label
        self.placeholder = placeholder
        _text = text
        self.message = message
        self.status = status
    }

    /// Convenience for callers that only distinguish error / no error.
    public init(_ label: LocalizedStringKey, text: Binding<String>, message: LocalizedStringKey? = nil, isError: Bool) {
        self.init(label, text: text, message: message, status: isError ? .error : .normal)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            SectionLabel(label)
            HStack(spacing: SpacingTokens.s) {
                TextField(label, text: $text, prompt: Text(verbatim: placeholder).foregroundStyle(Color(ColorTokens.textDisabled)))
                    .typography(TypographyTokens.body)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .focused($focused)
                if status == .success {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color(ColorTokens.stateSuccess))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, SpacingTokens.ml)
            .frame(minHeight: 56)
            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).stroke(Color(borderColor), lineWidth: 1.5))
            .animation(.easeOut(duration: MotionTokens.fastSeconds), value: focused)
            if let message {
                Text(message)
                    .typography(TypographyTokens.caption)
                    .fontWeight(status == .normal ? .regular : .semibold)
                    .foregroundStyle(Color(messageColor))
            }
        }
    }

    private var borderColor: TokenColor {
        switch status {
        case .error: ColorTokens.stateDanger
        case .success: ColorTokens.stateSuccess
        case .normal: focused ? ColorTokens.brandFlame : ColorTokens.strokeSubtle
        }
    }

    private var messageColor: TokenColor {
        switch status {
        case .error: ColorTokens.stateDanger
        case .success: ColorTokens.stateSuccessText
        case .normal: ColorTokens.textTertiary
        }
    }
}

/// A tappable field that opens a picker (country, birth year) — looks like `PushlyTextField`.
public struct PickerField<Content: View>: View {
    let label: LocalizedStringKey
    let value: String
    let content: Content

    public init(_ label: LocalizedStringKey, value: String, @ViewBuilder menu: () -> Content) {
        self.label = label
        self.value = value
        self.content = menu()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            SectionLabel(label)
            Menu {
                content
            } label: {
                HStack {
                    Text(verbatim: value)
                        .typography(TypographyTokens.body)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .lineLimit(1)
                    Spacer(minLength: SpacingTokens.xs)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                }
                .padding(.horizontal, SpacingTokens.m)
                .frame(minHeight: 56)
                .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(verbatim: value))
        }
    }
}

// MARK: - Containers

/// Card container (doc 14 §3): dark surface, 24 pt radius, hairline border.
public struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = SpacingTokens.ml, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1))
    }
}

/// Small rounded label ("Bronze III", "20 push-ups").
public struct Pill: View {
    let text: LocalizedStringKey
    let color: TokenColor?

    /// `color` tints the pill; nil gives a neutral glass pill.
    public init(_ text: LocalizedStringKey, color: TokenColor? = nil) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .typography(TypographyTokens.bodyS)
            .fontWeight(.bold)
            .foregroundStyle(color.map { Color($0) } ?? Color(ColorTokens.textPrimary))
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.xs + 2)
            .background(
                color.map { Color($0).opacity(0.16) } ?? Color.white.opacity(0.08),
                in: Capsule()
            )
    }
}

/// Inline error / warning / success message.
public struct InlineBanner: View {
    public enum Kind: Sendable { case error, warning, info, success }
    let text: LocalizedStringKey
    let kind: Kind

    public init(_ text: LocalizedStringKey, kind: Kind = .error) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        let (color, symbol): (TokenColor, String) = switch kind {
        case .error: (ColorTokens.stateDanger, "exclamationmark.circle.fill")
        case .warning: (ColorTokens.stateWarning, "exclamationmark.triangle.fill")
        case .info: (ColorTokens.brandCyan, "info.circle.fill")
        case .success: (ColorTokens.stateSuccess, "checkmark.circle.fill")
        }
        HStack(alignment: .firstTextBaseline, spacing: SpacingTokens.sm) {
            Image(systemName: symbol)
                .foregroundStyle(Color(color))
                .accessibilityHidden(true)
            Text(text)
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SpacingTokens.m)
        .background(Color(color).opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).stroke(Color(color).opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Gradient progress bar (rep progress, onboarding progress).
public struct GradientProgressBar: View {
    let value: Double
    let height: CGFloat

    public init(value: Double, height: CGFloat = 8) {
        self.value = min(max(value, 0), 1)
        self.height = height
    }

    public var body: some View {
        Capsule()
            .fill(Color(ColorTokens.strokeSubtle))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(ColorTokens.brandFlame), Color(ColorTokens.brandVolt)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * value)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Page indicator: the active page is a wide flame capsule.
public struct PageDots: View {
    let count: Int
    let index: Int

    public init(count: Int, index: Int) {
        self.count = count
        self.index = index
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color(i == index ? ColorTokens.brandFlame : ColorTokens.strokeStrong))
                    .frame(width: i == index ? 24 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: MotionTokens.baseSeconds), value: index)
        .accessibilityHidden(true)
    }
}

// MARK: - Arena background

/// Soft radial light behind hero content.
public struct GlowSpot: View {
    let color: TokenColor
    let size: CGFloat
    let intensity: Double

    public init(_ color: TokenColor = ColorTokens.brandFlame, size: CGFloat = 520, intensity: Double = 0.24) {
        self.color = color
        self.size = size
        self.intensity = intensity
    }

    public var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(color).opacity(intensity), Color(color).opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size * 0.33))
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Full-screen arena background: base colour plus one glow spot.
    func arenaBackground(glow: TokenColor = ColorTokens.brandFlame, alignment: Alignment = .top, offset: CGSize = .zero) -> some View {
        background {
            ZStack(alignment: alignment) {
                Color(ColorTokens.bgBase)
                GlowSpot(glow).offset(offset)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Brand

/// The Pushly mark: gradient rounded square with the push-up glyph.
public struct LogoMark: View {
    let size: CGFloat

    public init(size: CGFloat = 112) {
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.286, style: .continuous)
            .fill(LinearGradient(GradientTokens.hero))
            .frame(width: size, height: size)
            .overlay { PushupGlyph().frame(width: size * 0.57, height: size * 0.57) }
            .shadow(color: Color(ColorTokens.brandFlame).opacity(0.35), radius: size * 0.27, y: size * 0.2)
            .accessibilityHidden(true)
    }
}

/// Glyph drawn on a 64×64 grid (same geometry as the Android vector and the app icon).
struct PushupGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 64
            var body = Path()
            body.move(to: CGPoint(x: 14 * s, y: 40 * s))
            body.addLine(to: CGPoint(x: 30 * s, y: 40 * s))
            body.addLine(to: CGPoint(x: 38 * s, y: 28 * s))
            body.addLine(to: CGPoint(x: 50 * s, y: 28 * s))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 44 * s, y: 20 * s))
            arrow.addLine(to: CGPoint(x: 52 * s, y: 28 * s))
            arrow.addLine(to: CGPoint(x: 44 * s, y: 36 * s))
            let stroke = StrokeStyle(lineWidth: 6 * s, lineCap: .round, lineJoin: .round)
            context.stroke(body, with: .color(.white), style: stroke)
            context.stroke(arrow, with: .color(.white), style: stroke)
            context.fill(Path(ellipseIn: CGRect(x: 12 * s, y: 20 * s, width: 12 * s, height: 12 * s)), with: .color(.white))
        }
    }
}

/// "PUSHLY" wordmark in condensed black italic.
public struct Wordmark: View {
    let token: TypeToken

    public init(token: TypeToken = TypographyTokens.displayWordmark) {
        self.token = token
    }

    public var body: some View {
        Text(verbatim: "Pushly")
            .typography(token)
            .foregroundStyle(Color(ColorTokens.textPrimary))
            .accessibilityLabel(Text(verbatim: "Pushly"))
    }
}

// MARK: - Avatars

/// Preset avatars (doc 14 §4 `Avatar`). Ids are stored in `profiles.avatar_preset` and are identical on Android.
public enum AvatarPreset: String, CaseIterable, Sendable, Identifiable {
    case flame = "preset.flame"
    case volt = "preset.volt"
    case lime = "preset.lime"
    case cyan = "preset.cyan"
    case gold = "preset.gold"
    case diamond = "preset.diamond"
    case champion = "preset.champion"
    case silver = "preset.silver"

    public var id: String { rawValue }

    public var color: TokenColor {
        switch self {
        case .flame: ColorTokens.brandFlame
        case .volt: ColorTokens.brandVolt
        case .lime: ColorTokens.brandLime
        case .cyan: ColorTokens.brandCyan
        case .gold: ColorTokens.leagueGold
        case .diamond: ColorTokens.leagueDiamond
        case .champion: ColorTokens.leagueChampion
        case .silver: ColorTokens.leagueSilver
        }
    }

    /// Accessible colour name for VoiceOver.
    public var displayName: LocalizedStringKey {
        switch self {
        case .flame: "Flame"
        case .volt: "Volt"
        case .lime: "Lime"
        case .cyan: "Cyan"
        case .gold: "Gold"
        case .diamond: "Diamond"
        case .champion: "Champion"
        case .silver: "Silver"
        }
    }

    public static let `default` = AvatarPreset.flame
}

/// Rounded square in the preset colour with the user's initial in condensed black italic.
public struct AvatarView: View {
    let username: String
    let preset: AvatarPreset
    let size: CGFloat

    public init(username: String, presetID: String?, size: CGFloat = 56) {
        self.username = username
        self.preset = presetID.flatMap(AvatarPreset.init(rawValue:)) ?? .default
        self.size = size
    }

    public var body: some View {
        let color = Color(preset.color)
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(String(username.prefix(1)).uppercased())
                    .font(.token(TypographyTokens.displayCounter, fixedSize: size * 0.55))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            LogoMark(size: 72)
            ScreenTitle("Join the\narena")
            PrimaryButton("Continue") {}
            PrimaryButton("Loading", isLoading: true) {}
            PrimaryButton("Disabled") {}.disabled(true)
            SecondaryButton("Secondary") {}
            GhostButton("Continue as guest") {}
            PushlyTextField("Username", text: .constant("DanPushes"), message: "Available", status: .success)
            PushlyTextField("Username", text: .constant("a!"), message: "Only letters, numbers, _ and .", status: .error)
            Card { Pill("Bronze III", color: ColorTokens.leagueBronze) }
            InlineBanner("Something went wrong")
            GradientProgressBar(value: 0.7)
            PageDots(count: 3, index: 0)
            HStack { ForEach(AvatarPreset.allCases) { AvatarView(username: "Dan", presetID: $0.rawValue, size: 36) } }
        }
        .padding(SpacingTokens.l)
    }
    .arenaBackground()
    .preferredColorScheme(.dark)
}
