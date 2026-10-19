import Foundation

/// Account rules (doc 02 PS-03, doc 16 §2). Mirrors tools/reference/pushly_ref/account.py and the server
/// (`update_profile`); verified against shared/test-vectors/account/rules.json.
public enum AccountRules {
    public static let minAge = 16
    public static let minBirthYear = 1900

    public enum UsernameError: String, Sendable, Equatable {
        case tooShort, tooLong, invalidCharacters, reserved
    }

    public enum BirthYearError: String, Sendable, Equatable {
        case invalid, tooYoung
    }

    public static func usernameError(_ name: String) -> UsernameError? {
        if name.count < 3 { return .tooShort }
        if name.count > 20 { return .tooLong }
        if name.wholeMatch(of: /[A-Za-z0-9_.]{3,20}/) == nil { return .invalidCharacters }
        if name.wholeMatch(of: /u_[0-9a-f]{12}/) != nil { return .reserved }
        return nil
    }

    public static func birthYearError(_ birthYear: Int, currentYear: Int) -> BirthYearError? {
        if birthYear < minBirthYear || birthYear > currentYear { return .invalid }
        if currentYear - birthYear < minAge { return .tooYoung }
        return nil
    }

    /// Birth years offered in the picker, newest allowed first.
    public static func selectableBirthYears(currentYear: Int) -> [Int] {
        Array(stride(from: currentYear - minAge, through: minBirthYear + 6, by: -1))
    }
}

/// Semantic app version (`major.minor.patch`, extra build suffix after a space ignored).
public struct AppVersion: Comparable, Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        let core = string.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// True when the running app is older than the minimum supported version. Unparseable versions never force an update.
    public static func updateRequired(app: String, minSupported: String) -> Bool {
        guard let a = AppVersion(app), let m = AppVersion(minSupported) else { return false }
        return a < m
    }
}
