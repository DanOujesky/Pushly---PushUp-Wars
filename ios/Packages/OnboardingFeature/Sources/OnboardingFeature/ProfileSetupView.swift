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
                Text("Create your profile")
                    .font(.token(TypographyTokens.displayL))
                    .foregroundStyle(Color(ColorTokens.textPrimary))

                HStack {
                    Spacer()
                    AvatarView(username: model.username.isEmpty ? "?" : model.username, presetID: model.preset.rawValue, size: 88)
                    Spacer()
                }

                section("Username") {
                    PushlyTextField("Username", text: $model.username,
                                    message: usernameMessage, isError: usernameIsError)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: model.username) { model.usernameChanged() }
                }

                section("Avatar color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: SpacingTokens.sm) {
                        ForEach(AvatarPreset.allCases) { preset in
                            Button { model.preset = preset } label: {
                                AvatarView(username: model.username.isEmpty ? "?" : model.username,
                                           presetID: preset.rawValue, size: 52)
                                    .overlay(Circle().stroke(Color(ColorTokens.textPrimary),
                                                             lineWidth: model.preset == preset ? 3 : 0))
                                    .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                            }
                            .accessibilityLabel(Text("Avatar color \(preset.rawValue)"))
                            .accessibilityAddTraits(model.preset == preset ? .isSelected : [])
                        }
                    }
                }

                section("Country") {
                    Picker("Country", selection: $model.country) {
                        Text("Not set").tag(String?.none)
                        ForEach(countries) { c in Text("\(c.flag) \(c.name)").tag(Optional(c.code)) }
                    }
                    .pickerStyle(.navigationLink)
                }

                section("Birth year") {
                    Picker("Birth year", selection: $model.birthYear) {
                        Text("Select").tag(Int?.none)
                        ForEach(model.birthYearOptions, id: \.self) { y in Text(verbatim: String(y)).tag(Optional(y)) }
                    }
                    .pickerStyle(.menu)
                    Text("You must be at least 16 to use Pushly. Your birth year is never shown to others.")
                        .font(.token(TypographyTokens.caption))
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                }

                if let failure = model.failure {
                    InlineBanner(Self.message(for: failure))
                }

                PrimaryButton("Continue", isLoading: model.isSaving) {
                    Task { await model.submit() }
                }
                .disabled(!model.canSubmit)
            }
            .padding(SpacingTokens.gutter)
        }
        .background(Color(ColorTokens.bgBase))
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            Text(title)
                .font(.token(TypographyTokens.overline))
                .textCase(.uppercase)
                .foregroundStyle(Color(ColorTokens.textSecondary))
            content()
        }
    }

    private var usernameIsError: Bool {
        switch model.availability {
        case .taken, .invalid: true
        default: false
        }
    }

    private var usernameMessage: LocalizedStringKey? {
        switch model.availability {
        case .idle: "3–20 characters: letters, numbers, _ and ."
        case .checking: "Checking…"
        case .available: "Available ✓"
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
}
