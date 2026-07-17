import EnvStoreCore
import EnvStoreCrypto
import Foundation
import Testing

@testable import EnvStoreStorage

@Suite(.serialized)
struct EncryptedVaultStoreTests {
  @Test
  func persistsEncryptedSetAndReopensIt() async throws {
    let fixture = try VaultFixture()
    let created = try await fixture.store.createSet(sampleDraft)

    #expect(created.name == "Production")
    #expect(created.revision == 1)
    #expect(created.variables.map(\.key) == ["DATABASE_URL", "API_TOKEN"])
    #expect(try await fixture.store.listSets().map(\.name) == ["Production"])

    await fixture.store.close()
    let reopened = try EncryptedVaultStore(
      databaseURL: fixture.databaseURL,
      rootKeyStore: fixture.rootKeyStore
    )
    let loaded = try await reopened.loadSet(id: created.id)

    #expect(loaded == created)
    await reopened.close()

    let databaseBytes = try Data(contentsOf: fixture.databaseURL)
    let databaseText = String(decoding: databaseBytes, as: UTF8.self)
    #expect(!databaseText.contains("Production"))
    #expect(!databaseText.contains("DATABASE_URL"))
    #expect(!databaseText.contains("postgres://secret-123"))
  }

  @Test
  func updatesAtomicallyAndRetainsEncryptedRevisions() async throws {
    let fixture = try VaultFixture()
    let created = try await fixture.store.createSet(sampleDraft)
    let changed = EnvironmentSetDraft(
      name: "Production v2",
      variables: [EnvironmentVariable(key: "API_TOKEN", value: "rotated")]
    )

    let updated = try await fixture.store.updateSet(id: created.id, draft: changed)
    let revisions = try await fixture.store.revisions(for: created.id)

    #expect(updated.revision == 2)
    #expect(updated.variables.map(\.value) == ["rotated"])
    #expect(revisions.map(\.revision) == [2, 1])
    #expect(revisions.last?.variables.first?.value == "postgres://secret-123")
  }

  @Test
  func validationFailureDoesNotPartiallyReplaceASet() async throws {
    let fixture = try VaultFixture()
    let created = try await fixture.store.createSet(sampleDraft)
    let invalid = EnvironmentSetDraft(
      name: "Broken",
      variables: [
        EnvironmentVariable(key: "DUPLICATE", value: "one"),
        EnvironmentVariable(key: "DUPLICATE", value: "two"),
      ]
    )

    await #expect(throws: EnvironmentSetValidationError.duplicateVariableKey("DUPLICATE")) {
      try await fixture.store.updateSet(id: created.id, draft: invalid)
    }
    #expect(try await fixture.store.loadSet(id: created.id) == created)
  }

  @Test
  func refusesExistingVaultWhenRootKeyIsMissingOrWrong() async throws {
    let fixture = try VaultFixture()
    _ = try await fixture.store.createSet(sampleDraft)
    await fixture.store.close()

    #expect(throws: EnvStoreCryptoError.missingRootKey) {
      try EncryptedVaultStore(
        databaseURL: fixture.databaseURL,
        rootKeyStore: InMemoryRootKeyStore()
      )
    }

    let wrongStore = InMemoryRootKeyStore()
    _ = try wrongStore.createIfMissing(reason: "Wrong")
    let wrongVault = try EncryptedVaultStore(
      databaseURL: fixture.databaseURL,
      rootKeyStore: wrongStore
    )
    await #expect(throws: EnvStoreCryptoError.authenticationFailed) {
      _ = try await wrongVault.listSets()
    }
  }

  @Test
  func deletesASetAndItsRevisions() async throws {
    let fixture = try VaultFixture()
    let created = try await fixture.store.createSet(sampleDraft)

    try await fixture.store.deleteSet(id: created.id)

    #expect(try await fixture.store.listSets().isEmpty)
    #expect(try await fixture.store.revisions(for: created.id).isEmpty)
  }

  @Test
  func encryptsProjectBindingsAndCommandProfiles() async throws {
    let fixture = try VaultFixture()
    let set = try await fixture.store.createSet(sampleDraft)
    let binding = ProjectBinding(path: "/tmp/private-project", setID: set.id)
    let profile = CommandProfile(
      name: "Tests",
      setID: set.id,
      projectRoot: "/tmp/private-project",
      executablePath: "/usr/bin/true",
      arguments: [],
      trustMode: .development
    )

    try await fixture.store.saveProjectBinding(binding)
    try await fixture.store.saveCommandProfile(profile)

    #expect(try await fixture.store.listProjectBindings() == [binding])
    #expect(try await fixture.store.listCommandProfiles() == [profile])
    #expect(
      try await fixture.store.resolveSet(name: nil, workingDirectory: "/tmp/private-project/src").id
        == set.id)

    await fixture.store.close()
    let raw = String(decoding: try Data(contentsOf: fixture.databaseURL), as: UTF8.self)
    #expect(!raw.contains("private-project"))
    #expect(!raw.contains("Tests"))
    #expect(!raw.contains("/usr/bin/true"))
  }

  private var sampleDraft: EnvironmentSetDraft {
    EnvironmentSetDraft(
      name: "Production",
      note: "Primary deployment",
      variables: [
        EnvironmentVariable(key: "DATABASE_URL", value: "postgres://secret-123"),
        EnvironmentVariable(key: "API_TOKEN", value: "token-value"),
      ]
    )
  }
}

private struct VaultFixture {
  let databaseURL: URL
  let rootKeyStore: InMemoryRootKeyStore
  let store: EncryptedVaultStore

  init() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "EnvStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    databaseURL = directory.appending(path: "vault.sqlite")
    rootKeyStore = InMemoryRootKeyStore()
    store = try EncryptedVaultStore(databaseURL: databaseURL, rootKeyStore: rootKeyStore)
  }
}
