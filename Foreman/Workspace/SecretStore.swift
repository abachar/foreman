import Foundation
import Security
import Synchronization

/// Where a secret lives: the Keychain in the app, memory in the tests (architecture: shared
/// services; `AGENTS.md`: a struct of closures, no single-implementation protocol).
///
/// The account of a Postgres password is `foreman.postgres.<host>:<port>/<database>/<user>`
/// (postgres, technical options). A secret never reaches a log, `.foreman/` or an error.
nonisolated struct SecretStore: Sendable {
    /// The secret stored for an account, `nil` when there is none.
    let read: @Sendable (_ account: String) throws(SecretStoreError) -> String?
    /// Stores or replaces the secret of an account.
    let write: @Sendable (_ secret: String, _ account: String) throws(SecretStoreError) -> Void
    /// Removes the secret of an account; nothing to remove is not an error.
    let delete: @Sendable (_ account: String) throws(SecretStoreError) -> Void
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

extension SecretStore {
    /// The user's login keychain, through Security.framework (postgres R3, config R11).
    ///
    /// Using `SecItemAdd`/`SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete` on a generic
    /// password because that is the whole need; nothing is wrapped beyond the four calls.
    static func keychain(service: String = "dev.crafters.foreman") -> SecretStore {
        SecretStore(
            read: { account throws(SecretStoreError) in
                var query = keychainQuery(service: service, account: account)
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
            },
            // Adds the item, or updates it in place on `errSecDuplicateItem`: replacing never
            // deletes first, so the item and its metadata survive a failed write.
            write: { secret, account throws(SecretStoreError) in
                var attributes = keychainQuery(service: service, account: account)
                attributes[kSecValueData as String] = Data(secret.utf8)
                let status = SecItemAdd(attributes as CFDictionary, nil)
                if status == errSecDuplicateItem {
                    let update = [kSecValueData as String: Data(secret.utf8)]
                    let updated = SecItemUpdate(
                        keychainQuery(service: service, account: account) as CFDictionary, update as CFDictionary)
                    guard updated == errSecSuccess else { throw .keychain(updated) }
                    return
                }
                guard status == errSecSuccess else { throw .keychain(status) }
            },
            delete: { account throws(SecretStoreError) in
                let status = SecItemDelete(keychainQuery(service: service, account: account) as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
            })
    }

    /// The store of the tests: the Keychain cannot be used hermetically (postgres, technical
    /// options); a plain dictionary behind a mutex, no policy of its own.
    static func inMemory() -> SecretStore {
        let secrets = Mutex<[String: String]>([:])
        return SecretStore(
            read: { account in secrets.withLock { $0[account] } },
            write: { secret, account in secrets.withLock { $0[account] = secret } },
            delete: { account in secrets.withLock { $0[account] = nil } })
    }

    private static func keychainQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
