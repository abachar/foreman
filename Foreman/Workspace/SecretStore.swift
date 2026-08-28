import Foundation
import Security
import Synchronization

/// Where a secret lives: the Keychain in the app, memory in the tests (architecture: shared
/// services; `AGENTS.md`: two implementations in the same commit).
///
/// The account of a Postgres password is `foreman.postgres.<host>:<port>/<database>/<user>`
/// (postgres, technical options). A secret never reaches a log, `.foreman/` or an error.
nonisolated protocol SecretStore: Sendable {
    /// The secret stored for `account`, `nil` when there is none.
    func read(_ account: String) throws(SecretStoreError) -> String?
    /// Stores or replaces the secret of `account`.
    func write(_ secret: String, for account: String) throws(SecretStoreError)
    /// Removes the secret of `account`; nothing to remove is not an error.
    func delete(_ account: String) throws(SecretStoreError)
}

/// Why the store could not answer; the secret itself is never part of it.
nonisolated enum SecretStoreError: Error, Equatable, CustomStringConvertible {
    /// A Security.framework status other than "found" or "not found".
    case keychain(OSStatus)

    var description: String {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil).map { String($0) } ?? "status \(status)"
            return "Keychain: \(message)"
        }
    }
}

/// The user's login keychain, through Security.framework (postgres R3, config R11).
///
/// Using `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` on a generic password because that
/// is the whole need; nothing is wrapped beyond the three calls.
nonisolated struct KeychainSecretStore: SecretStore {
    static let service = "dev.crafters.foreman"

    func read(_ account: String) throws(SecretStoreError) -> String? {
        var query = Self.query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw .keychain(status) }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw .keychain(errSecDecode)
        }
        return secret
    }

    func write(_ secret: String, for account: String) throws(SecretStoreError) {
        try delete(account)
        var attributes = Self.query(account)
        attributes[kSecValueData as String] = Data(secret.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw .keychain(status) }
    }

    func delete(_ account: String) throws(SecretStoreError) {
        let status = SecItemDelete(Self.query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// The store of the tests: the Keychain cannot be used hermetically (postgres, technical
/// options); a plain dictionary behind a mutex, no policy of its own.
nonisolated final class InMemorySecretStore: SecretStore {
    private let secrets = Mutex<[String: String]>([:])

    init() {}

    func read(_ account: String) throws(SecretStoreError) -> String? {
        secrets.withLock { $0[account] }
    }

    func write(_ secret: String, for account: String) throws(SecretStoreError) {
        secrets.withLock { $0[account] = secret }
    }

    func delete(_ account: String) throws(SecretStoreError) {
        secrets.withLock { $0[account] = nil }
    }
}
