import Core
import CryptoKit
import Foundation
import Security
import UIKit

/// This install's signing key (doc 06 §3): P-256 in the Secure Enclave when the device has one (software key in the
/// keychain otherwise, e.g. the simulator). The private key never leaves the device.
public final class DeviceKey: @unchecked Sendable {
    private enum Backing {
        case enclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)
    }

    private let backing: Backing

    private init(_ backing: Backing) { self.backing = backing }

    /// For tests.
    public static func software(_ key: P256.Signing.PrivateKey = .init()) -> DeviceKey { DeviceKey(.software(key)) }

    /// SubjectPublicKeyInfo DER — what `register_device` stores and the server verifies with.
    public var publicKeySPKI: Data {
        switch backing {
        case let .enclave(k): k.publicKey.derRepresentation
        case let .software(k): k.publicKey.derRepresentation
        }
    }

    /// ECDSA P-256 / SHA-256, raw r‖s.
    public func sign(_ data: Data) -> Data? {
        switch backing {
        case let .enclave(k): try? k.signature(for: data).rawRepresentation
        case let .software(k): try? k.signature(for: data).rawRepresentation
        }
    }

    private static let service = "app.pushly.devicekey"

    /// Loads the key from the keychain, or creates and stores one.
    public static func loadOrCreate() -> DeviceKey? {
        if let (kind, blob) = read() {
            if kind == "enclave", let k = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) {
                return DeviceKey(.enclave(k))
            }
            if kind == "software", let k = try? P256.Signing.PrivateKey(rawRepresentation: blob) {
                return DeviceKey(.software(k))
            }
        }
        if SecureEnclave.isAvailable, let k = try? SecureEnclave.P256.Signing.PrivateKey() {
            store("enclave", k.dataRepresentation)
            return DeviceKey(.enclave(k))
        }
        let k = P256.Signing.PrivateKey()
        store("software", k.rawRepresentation)
        return DeviceKey(.software(k))
    }

    private static func read() -> (String, Data)? {
        for kind in ["enclave", "software"] {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: kind, kSecReturnData as String: true]
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
                return (kind, data)
            }
        }
        return nil
    }

    private static func store(_ kind: String, _ data: Data) {
        let attrs: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: kind, kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemDelete(attrs as CFDictionary)
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess { PLog.warning("Device key not stored (\(status))", .sync) }
    }
}

/// Wraps rep logs in the signed envelope `{log, signature, deviceId}` (D-047). Registers the device key once per
/// launch (idempotent on the server). Any failure falls back to the bare log, which the server accepts with a soft
/// flag — signing must never block an upload.
public actor LogSigner {
    public typealias Register = @Sendable (Data) async throws -> String

    private let key: DeviceKey?
    private let register: Register
    private let appVersion: String
    private var deviceId: String?

    public init(key: DeviceKey?, appVersion: String, register: @escaping Register) {
        self.key = key
        self.appVersion = appVersion
        self.register = register
    }

    public func envelope(_ log: Data) async -> Data {
        guard let key, let text = String(data: log, encoding: .utf8) else { return log }
        do {
            let id = try await registeredId(key)
            guard let signature = key.sign(Data(text.utf8)) else { return log }
            return try JSONSerialization.data(withJSONObject: ["log": text, "signature": signature.base64EncodedString(),
                                                               "deviceId": id])
        } catch {
            PLog.warning("Rep log sent unsigned: \(error)", .sync)
            return log
        }
    }

    /// This install's device row id (registers the key if needed) — also used for the push token.
    public func deviceId() async throws -> String {
        guard let key else { throw CancellationError() }
        return try await registeredId(key)
    }

    private func registeredId(_ key: DeviceKey) async throws -> String {
        if let deviceId { return deviceId }
        let (model, os) = await MainActor.run { (RepSessionModel.deviceModel, UIDevice.current.systemVersion) }
        let body: [String: Any] = [
            "platform": "ios", "publicKey": key.publicKeySPKI.base64EncodedString(),
            "model": model, "osVersion": os, "appVersion": appVersion,
        ]
        let id = try await register(try JSONSerialization.data(withJSONObject: body))
        deviceId = id
        return id
    }
}
