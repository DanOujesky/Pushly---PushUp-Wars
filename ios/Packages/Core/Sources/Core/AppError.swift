import Foundation

/// Server error codes (doc 12, shared HTTP format) plus client-side failures.
public enum AppErrorCode: String, Sendable, Codable, CaseIterable {
    case unauthenticated = "UNAUTHENTICATED"
    case forbidden = "FORBIDDEN"
    case validationFailed = "VALIDATION_FAILED"
    case notFound = "NOT_FOUND"
    case conflict = "CONFLICT"
    case rateLimited = "RATE_LIMITED"
    case integrityFailed = "INTEGRITY_FAILED"
    case upgradeRequired = "UPGRADE_REQUIRED"
    case `internal` = "INTERNAL"
    case network = "NETWORK"        // client only
    case unknown = "UNKNOWN"        // client only
}

public struct AppError: Error, Sendable, Equatable {
    public let code: AppErrorCode
    public let message: String
    /// Whether the outbox may retry (doc 03 §5). Network failures are always retryable.
    public let retryable: Bool

    public init(code: AppErrorCode, message: String, retryable: Bool? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable ?? [.rateLimited, .internal, .network].contains(code)
    }
}
