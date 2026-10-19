import Core
import DesignSystem
import Networking
import SwiftUI

/// Profile setup after the first sign-in (doc 02 PS-03).
public struct ProfileSetupView: View {
    @State private var model: ProfileSetupViewModel
    private let countries = CountryList.all()

    public init(model: ProfileSetupViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.l) {
                VStack(alignment: .leading, spacing: SpacingTokens.s) {
                    SectionLabel("Last step", color: ColorTokens.brandFlameText)
                    ScreenTitle("Pick your\nfighter name")
                }

                previewCard

                PushlyTextField("Username", text: $model.username, message: usernameMessage, status: usernameStatus)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: model.username) { model.usernameChanged() }

                VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                    SectionLabel("Color")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SpacingTokens.sm), count: 4),
                              spacing: SpacingTokens.sm) {
                        ForEach(AvatarPreset.allCases) { preset in
                            swatch(preset)
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: SpacingTokens.sm) { countryField; birthYearField }
                    VStack(spacing: SpacingTokens.m) { countryField; birthYearField }
                }

                Text("16+ only. Your birth year is never shown to others.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .padding(.top, -SpacingTokens.s)

                if let failure = model.failure {
                    InlineBanner(Self.message(for: failure))
                }
            }
            .padding(.horizontal, SpacingTokens.l)
            .padding(.top, SpacingTokens.xl)
            .padding(.bottom, SpacingTokens.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Enter the arena", isLoading: model.isSaving) {
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
            .padding(.horizontal, SpacingTokens.l)
            .padding(.bottom, SpacingTokens.s)
            .background(Color(ColorTokens.bgBase).opacity(0.94).ignoresSafeArea())
        }
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private var displayName: String { model.username.isEmpty ? "?" : model.username }

    private var previewCard: some View {
        Card(padding: SpacingTokens.m) {
            HStack(spacing: SpacingTokens.m) {
                AvatarView(username: displayName, presetID: model.preset.rawValue, size: 72)
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    Text(verbatim: model.username.isEmpty ? "—" : model.username)
                        .typography(TypographyTokens.name)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let code = model.country, let country = countries.first(where: { $0.code == code }) {
                        Text(verbatim: "\(country.flag) \(country.name)")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    } else {
                        Text("New fighter")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func swatch(_ preset: AvatarPreset) -> some View {
        let selected = model.preset == preset
        return Button { model.preset = preset } label: {
            RoundedRectangle(cornerRadius: RadiusTokens.s, style: .continuous)
                .fill(Color(preset.color))
                .frame(height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: RadiusTokens.s, style: .continuous)
                        .stroke(Color(ColorTokens.textPrimary), lineWidth: selected ? 3 : 0)
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(preset.displayName))
        .accessibilityHint(Text("Avatar color"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var countryField: some View {
        let selected = model.country.flatMap { code in countries.first { $0.code == code } }
        return PickerField("Country", value: selected.map { "\($0.flag) \($0.name)" } ?? String(localized: "Not set")) {
            Picker("Country", selection: $model.country) {
                Text("Not set").tag(String?.none)
                ForEach(countries) { c in Text(verbatim: "\(c.flag) \(c.name)").tag(Optional(c.code)) }
            }
        }
    }

    private var birthYearField: some View {
        PickerField("Birth year", value: model.birthYear.map { String($0) } ?? String(localized: "Select")) {
            Picker("Birth year", selection: $model.birthYear) {
                Text("Select").tag(Int?.none)
                ForEach(model.birthYearOptions, id: \.self) { y in Text(verbatim: String(y)).tag(Optional(y)) }
            }
        }
    }

    private var usernameStatus: PushlyTextField.Status {
        switch model.availability {
        case .taken, .invalid: .error
        case .available: .success
        default: .normal
        }
    }

    private var usernameMessage: LocalizedStringKey? {
        switch model.availability {
        case .idle: "3–20 characters: letters, numbers, _ and ."
        case .checking: "Checking…"
        case .available: "Available"
        case .taken: "That username is taken."
        case .unknown: "Couldn't check right now — we'll check when you continue."
        case let .invalid(error):
            switch error {
            case .tooShort: "At least 3 characters."
            case .tooLong: "At most 20 characters."
            case .invalidCharacters: "Only letters, numbers, _ and . are allowed."
            case .reserved: "That username is reserved."
            }
        }
    }

    static func message(for failure: ProfileSetupViewModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .usernameTaken: "Someone just took that username. Try another one."
        case .tooYoung: "You must be at least 16 to use Pushly."
        case .network: "No connection. Check your internet and try again."
        case .generic: "Something went wrong. Please try again."
        }
    }
}

#Preview {
    NavigationStack {
        ProfileSetupView(model: ProfileSetupViewModel(
            profile: Profile(id: UUID(), username: "u_0123456789ab", onboardingCompleted: false),
            profiles: InMemoryBackend(),
            onCompleted: { _ in }
        ))
    }
    .preferredColorScheme(.dark)
}
