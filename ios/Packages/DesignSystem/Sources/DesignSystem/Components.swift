import SwiftUI

// Phase 1 components (doc 14 §4). Each has a preview at the bottom of the file.

/// Main call-to-action: hero gradient, 56 pt tall, full width, shows a spinner while `isLoading`.
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
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
            .font(.token(TypographyTokens.titleS))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(LinearGradient(GradientTokens.hero), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isLoading)
        .accessibilityAddTraits(.isButton)
    }
}

/// Secondary action: outlined, same size as `PrimaryButton`.
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
                .font(.token(TypographyTokens.titleS))
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1.5))
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

/// Text field with Pushly styling and an optional validation message under it.
public struct PushlyTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let message: LocalizedStringKey?
    let isError: Bool

    public init(_ title: LocalizedStringKey, text: Binding<String>, message: LocalizedStringKey? = nil, isError: Bool = false) {
        self.title = title
        _text = text
        self.message = message
        self.isError = isError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            TextField(title, text: $text)
                .font(.token(TypographyTokens.body))
                .padding(.horizontal, SpacingTokens.m)
                .frame(minHeight: 52)
                .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.m)
                        .stroke(Color(isError ? ColorTokens.stateDanger : ColorTokens.strokeSubtle), lineWidth: 1)
                )
            if let message {
                Text(message)
                    .font(.token(TypographyTokens.caption))
                    .foregroundStyle(Color(isError ? ColorTokens.stateDanger : ColorTokens.textSecondary))
            }
        }
    }
}

/// Card container (doc 14 §3).
public struct Card<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(SpacingTokens.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1))
    }
}

/// Inline error / warning message.
public struct InlineBanner: View {
    public enum Kind: Sendable { case error, warning, info }
    let text: LocalizedStringKey
    let kind: Kind

    public init(_ text: LocalizedStringKey, kind: Kind = .error) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        let color: TokenColor = switch kind {
        case .error: ColorTokens.stateDanger
        case .warning: ColorTokens.stateWarning
        case .info: ColorTokens.brandCyan
        }
        Text(text)
            .font(.token(TypographyTokens.bodyS))
            .foregroundStyle(Color(ColorTokens.textPrimary))
            .padding(SpacingTokens.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(color).opacity(0.15), in: RoundedRectangle(cornerRadius: RadiusTokens.s))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(color)).frame(width: 4)
            }
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

    public static let `default` = AvatarPreset.flame
}

/// Circle with the user's initial on the preset color.
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
        Circle()
            .fill(Color(preset.color))
            .frame(width: size, height: size)
            .overlay {
                Text(String(username.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Components") {
    ScrollView {
        VStack(spacing: SpacingTokens.m) {
            PrimaryButton("Continue") {}
            PrimaryButton("Loading", isLoading: true) {}
            PrimaryButton("Disabled") {}.disabled(true)
            SecondaryButton("Secondary") {}
            PushlyTextField("Username", text: .constant("Dan"), message: "Available", isError: false)
            PushlyTextField("Username", text: .constant("a!"), message: "Only letters, numbers, _ and .", isError: true)
            Card { Text("Card content") }
            InlineBanner("Something went wrong")
            HStack { ForEach(AvatarPreset.allCases) { AvatarView(username: "Dan", presetID: $0.rawValue, size: 36) } }
        }
        .padding(SpacingTokens.gutter)
    }
    .background(Color(ColorTokens.bgBase))
}
