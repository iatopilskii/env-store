import Foundation
import Testing

@testable import EnvStoreCrypto

struct RootKeyStoreTests {
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
