import Core
import Foundation
import Supabase

/// Real backend implementation on top of supabase-swift. The only file that imports `Supabase`,
/// so the SDK can be swapped or mocked without touching features.
public final class SupabaseBackend: AuthServicing, ProfileServicing, RemoteConfigServicing, AlarmSyncServicing,
    RepSessionServicing, Sendable {
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

    // MARK: Alarm sync (P2-09)

    public func syncAlarms(_ changes: Data) async throws -> Data {
        try await mapErrors {
            struct Params: Encodable, Sendable { let changes: AnyJSON }
            let json = try JSONDecoder().decode(AnyJSON.self, from: changes)
            return try await client.rpc("sync_alarms", params: Params(changes: json)).execute().data
        }
    }

    // MARK: Rep sessions (P4-03/P4-05)

    public func submitRepSession(_ log: Data) async throws -> Data {
        try await mapErrors {
            try await client.functions.invoke("submit-rep-session", options: FunctionInvokeOptions(body: log)) { data, _ in
                data
            }
        }
    }

    public func wakeSummary() async throws -> Data {
        try await mapErrors { try await client.rpc("get_wake_summary").execute().data }
    }

    public func registerDevice(_ request: Data) async throws -> String {
        struct Params: Encodable, Sendable { let p: AnyJSON }
        return try await mapErrors {
            let json = try JSONDecoder().decode(AnyJSON.self, from: request)
            return try await client.rpc("register_device", params: Params(p: json)).execute().value
        }
    }

    public func serverTimeMs() async throws -> Int64 {
        struct Health: Decodable { let serverMs: Int64 }
        return try await mapErrors {
            try await client.functions.invoke("health", options: FunctionInvokeOptions(method: .get)) { data, _ in
                try JSONDecoder().decode(Health.self, from: data).serverMs
            }
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
        if case let FunctionsError.httpError(status, data) = error {
            return map(httpStatus: status, body: data)
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

    /// Edge Function errors: `{ "error": { "code", "message", "retryable" } }` (doc 12); falls back to the status.
    public static func map(httpStatus: Int, body: Data) -> AppError {
        struct Envelope: Decodable {
            struct Inner: Decodable { let code: String; let message: String?; let retryable: Bool? }
            let error: Inner
        }
        if let e = try? JSONDecoder().decode(Envelope.self, from: body), let code = AppErrorCode(rawValue: e.error.code) {
            return AppError(code: code, message: e.error.message ?? code.rawValue, retryable: e.error.retryable)
        }
        let code: AppErrorCode = switch httpStatus {
        case 401: .unauthenticated
        case 403: .forbidden
        case 404: .notFound
        case 409: .conflict
        case 422, 400: .validationFailed
        case 426: .upgradeRequired
        case 429: .rateLimited
        default: httpStatus >= 500 ? .internal : .unknown
        }
        return AppError(code: code, message: "HTTP \(httpStatus)")
    }

    static func postgresCode(in text: String) -> String? {
        for code in ["23505", "22023", "P0001", "28000", "42501", "P0002"] where text.contains(code) {
            return code
        }
        return nil
    }
}
