import Testing

@testable import Foreman

/// The in-memory store (postgres, technical options); the Keychain one is never touched here.
struct SecretStoreTests {
    private let account = "foreman.postgres.localhost:5432/ccoe/postgres"

    @Test func readsBackWhatWasWritten() throws {
        let store = InMemorySecretStore()
        #expect(try store.read(account) == nil)
        try store.write("secret", for: account)
        #expect(try store.read(account) == "secret")
    }

    @Test func overwritesAnExistingSecret() throws {
        let store = InMemorySecretStore()
        try store.write("old", for: account)
        try store.write("new", for: account)
        #expect(try store.read(account) == "new")
    }

    @Test func deleteInvalidatesTheEntryAndIsIdempotent() throws {
        let store = InMemorySecretStore()
        try store.write("secret", for: account)
        try store.delete(account)
        #expect(try store.read(account) == nil)
        try store.delete(account)
        #expect(try store.read(account) == nil)
    }

    @Test func keychainErrorNeverCarriesTheSecret() {
        #expect(SecretStoreError.keychain(-25300).description.hasPrefix("Keychain: "))
    }
}
