import Foundation
import Security
import Testing

@testable import EnvStoreCrypto

struct RootKeyStoreTests {
  @Test
  func automaticBackendUsesFileBasedKeychainWithoutApplicationIdentifier() {
    let backend = KeychainRootKeyStore.resolveBackend(
      .automatic,
      hasDataProtectionEntitlement: false
    )

    #expect(backend == .fileBased)
  }

  @Test
  func automaticBackendUsesDataProtectionWithApplicationIdentifier() {
    let backend = KeychainRootKeyStore.resolveBackend(
      .automatic,
      hasDataProtectionEntitlement: true
    )

    #expect(backend == .dataProtection)
  }

  @Test
  func fileBasedQueryDoesNotRequestDataProtectionAttributes() {
    let store = KeychainRootKeyStore(backend: .fileBased)

    #expect(store.baseQuery[kSecUseDataProtectionKeychain as String] == nil)
    #expect(store.baseQuery[kSecAttrSynchronizable as String] == nil)
    #expect(store.baseQuery[kSecAttrAccessible as String] == nil)
  }

  @Test
  func dataProtectionQueryExplicitlyDisablesSynchronization() {
    let store = KeychainRootKeyStore(backend: .dataProtection)

    #expect(store.baseQuery[kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(store.baseQuery[kSecAttrSynchronizable as String] as? Bool == false)
  }

  @Test
  func doesNotCreateAKeyWhenLoadingMissingVault() {
    let store = InMemoryRootKeyStore()

    #expect(throws: EnvStoreCryptoError.missingRootKey) {
      try store.loadExisting(reason: "Test")
    }
    #expect(store.hasKey == false)
  }

  @Test
  func createsOnceAndReturnsSameKey() throws {
    let store = InMemoryRootKeyStore()

    let created = try store.createIfMissing(reason: "Create")
    let loaded = try store.loadExisting(reason: "Load")
    let secondCreate = try store.createIfMissing(reason: "Create again")

    #expect(created.bytesForTesting == loaded.bytesForTesting)
    #expect(created.bytesForTesting == secondCreate.bytesForTesting)
  }
}
