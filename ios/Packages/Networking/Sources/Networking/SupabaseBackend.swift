import Core
import Foundation
import Supabase

/// Real backend implementation on top of supabase-swift. The only file that imports `Supabase`,
/// so the SDK can be swapped or mocked without touching features.
public final class SupabaseBackend: AuthServicing, ProfileServicing, RemoteConfigServicing, Sendable {
    private let client: SupabaseClient

    public init(config: BackendConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    // MARK: Auth

    public func currentUserID() async -> UUID? {
        do {
            return try await client.auth.session.user.id
        } catch {
            return nil
        }
    }

    public func authStateChanges() -> AsyncStream<UUID?> {
        let auth = client.auth
        return AsyncStream { continuation in
            let task = Task {
                for await change in auth.authStateChanges {
                    continuation.yield(change.session?.user.id)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func sendEmailCode(to email: String) async throws {
        try await mapErrors {
            try await client.auth.signInWithOTP(email: email, redirectTo: AuthCallback.url, shouldCreateUser: true)
        }
    }

    public func verifyEmailCode(email: String, code: String) async throws -> UUID {
        try await mapErrors {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            guard let user = response.session?.user else {
                throw AppError(code: .unauthenticated, message: "No session after verification")
            }
            return user.id
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        try await mapErrors {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return session.user.id
        }
    }

    public func handleAuthCallback(_ url: URL) async throws -> UUID {
        try await mapErrors {
            try await client.auth.session(from: url).user.id
        }
    }

    public func signOut() async throws {
        try await mapErrors { try await client.auth.signOut() }
    }

    // MARK: Profile

    public func fetchOwnProfile() async throws -> Profile {
        try await mapErrors {
            let uid = try await client.auth.session.user.id
            return try await client.from("profiles").select().eq("id", value: uid).single().execute().value
        }
    }

    public func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        struct Params: Encodable, Sendable { let patch: ProfilePatch }
        return try await mapErrors {
            try await client.rpc("update_profile", params: Params(patch: patch)).single().execute().value
        }
    }

    public func isUsernameAvailable(_ name: String) async throws -> Bool {
        struct Params: Encodable, Sendable { let name: String }
        return try await mapErrors {
            try await client.rpc("username_available", params: Params(name: name)).execute().value
        }
    }

    // MARK: Remote config

    public func fetch() async throws -> RemoteConfig {
        try await mapErrors {
            let rows: [AppConfigRow] = try await client.from("app_config").select("key,value").execute().value
            return RemoteConfig(rows: rows, platform: "ios")
        }
    }

    // MARK: Errors

    private func mapErrors<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as AppError {
            throw error
        } catch {
            throw BackendErrorMapper.map(error)
        }
    }
}

/// Maps SDK / transport errors to `AppError` (doc 12 error codes). Pure — unit tested.
public enum BackendErrorMapper {
    public static func map(_ error: Error) -> AppError {
        if let urlError = error as? URLError {
            return AppError(code: .network, message: urlError.localizedDescription)
        }
        let text = String(describing: error)
        return map(postgresCode: postgresCode(in: text), message: text)
    }

    /// Postgres SQLSTATEs raised by our RPCs (migration 0002) → app error codes.
    public static func map(postgresCode: String?, message: String) -> AppError {
        switch postgresCode {
        case "23505": AppError(code: .conflict, message: "taken")
        case "22023", "P0001": AppError(code: .validationFailed, message: message)
        case "28000", "42501": AppError(code: .forbidden, message: message)
        case "P0002": AppError(code: .notFound, message: message)
        default: AppError(code: .unknown, message: message)
        }
    }

    static func postgresCode(in text: String) -> String? {
        for code in ["23505", "22023", "P0001", "28000", "42501", "P0002"] where text.contains(code) {
            return code
        }
        return nil
    }
}
