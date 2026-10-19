import Core
import DesignSystem
import Foundation
import Networking
import Observation

/// Profile setup after the first sign-in (doc 02 PS-03): username, avatar, country, birth year (16+).
@MainActor
@Observable
public final class ProfileSetupViewModel {
    public enum Availability: Equatable, Sendable {
        case idle, checking, available, taken
        case invalid(AccountRules.UsernameError)
        case unknown  // network failed — the server will decide on submit
    }

    public enum Failure: Equatable, Sendable { case usernameTaken, tooYoung, network, generic }

    public var username: String
    public var preset: AvatarPreset = .default
    public var country: String?
    public var birthYear: Int?
    public private(set) var availability: Availability = .idle
    public private(set) var isSaving = false
    public private(set) var failure: Failure?

    public let birthYearOptions: [Int]
    private let profiles: any ProfileServicing
    private let currentYear: Int
    private let debounce: Duration
    private let timeZoneID: String
    private let onCompleted: @MainActor (Profile) -> Void
    private var checkTask: Task<Void, Never>?

    public init(
        profile: Profile,
        profiles: any ProfileServicing,
        currentYear: Int = Calendar.current.component(.year, from: Date()),
        regionCode: String? = Locale.current.region?.identifier,
        timeZoneID: String = TimeZone.current.identifier,
        debounce: Duration = .milliseconds(400),
        onCompleted: @escaping @MainActor (Profile) -> Void
    ) {
        // Never prefill the placeholder username (u_xxxxxxxxxxxx).
        username = AccountRules.usernameError(profile.username) == nil ? profile.username : ""
        preset = profile.avatarPreset.flatMap(AvatarPreset.init(rawValue:)) ?? .default
        country = profile.country ?? regionCode.flatMap { CountryList.isKnown($0) ? $0 : nil }
        birthYear = profile.birthYear
        self.profiles = profiles
        self.currentYear = currentYear
        self.debounce = debounce
        self.timeZoneID = timeZoneID
        self.onCompleted = onCompleted
        birthYearOptions = AccountRules.selectableBirthYears(currentYear: currentYear)
    }

    public var canSubmit: Bool {
        guard !isSaving, AccountRules.usernameError(username) == nil, let birthYear,
              AccountRules.birthYearError(birthYear, currentYear: currentYear) == nil else { return false }
        return availability == .available || availability == .unknown
    }

    /// Call whenever `username` changes; checks availability after a short pause in typing.
    public func usernameChanged() {
        checkTask?.cancel()
        failure = nil
        if let error = AccountRules.usernameError(username) {
            availability = username.isEmpty ? .idle : .invalid(error)
            return
        }
        availability = .checking
        let name = username
        checkTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.checkAvailability(of: name)
        }
    }

    func checkAvailability(of name: String) async {
        do {
            let free = try await profiles.isUsernameAvailable(name)
            guard name == username else { return }  // user kept typing
            availability = free ? .available : .taken
        } catch {
            guard name == username else { return }
            availability = .unknown
        }
    }

    public func submit() async {
        guard canSubmit, let birthYear else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        let patch = ProfilePatch(username: username, avatarPreset: preset.rawValue, country: country,
                                 birthYear: birthYear, timezone: timeZoneID)
        do {
            let updated = try await profiles.updateProfile(patch)
            onCompleted(updated)
        } catch let error as AppError {
            switch error.code {
            case .conflict:
                failure = .usernameTaken
                availability = .taken
            case .validationFailed where error.message.contains("16"):
                failure = .tooYoung
            case .network:
                failure = .network
            default:
                failure = .generic
            }
        } catch {
            failure = .generic
        }
    }
}

/// ISO 3166 countries with localized names, for the country picker.
public enum CountryList {
    public struct Country: Identifiable, Hashable, Sendable {
        public let code: String
        public let name: String
        public var id: String { code }
        public var flag: String {
            code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }.map(String.init).joined()
        }
    }

    public static func all(locale: Locale = .current) -> [Country] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .compactMap { code in locale.localizedString(forRegionCode: code).map { Country(code: code, name: $0) } }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    public static func isKnown(_ code: String) -> Bool {
        code.count == 2 && Locale.Region.isoRegions.contains { $0.identifier == code }
    }
}
