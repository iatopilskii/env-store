import EnvStoreCore
import EnvStoreCrypto
import Foundation
import Testing

@testable import EnvStoreAppCore

@MainActor
struct VaultViewModelTests {
  @Test
  func reportsMissingKeychainEntitlement() async {
    let databaseURL = FileManager.default.temporaryDirectory
      .appending(path: "EnvStoreMissingEntitlement-\(UUID().uuidString).sqlite")
    let model = VaultViewModel(
      databaseURL: databaseURL,
      rootKeyStore: FailingRootKeyStore(error: .keychainFailure(-34_018))
    )

    await model.unlock()

    #expect(model.lockState == .locked)
    #expect(
      model.errorMessage
        == "This build cannot access the Data Protection Keychain because its signing entitlement is missing."
    )
  }

  @Test
  func unlocksCreatesUpdatesAndLocksWithoutRetainingSets() async throws {
    let model = try makeModel()

    await model.unlock()
    #expect(model.lockState == .unlocked)
    #expect(model.sets.isEmpty)

    let created = await model.create(
      EnvironmentSetDraft(
        name: "Development",
        variables: [EnvironmentVariable(key: "TOKEN", value: "secret")]
      )
    )
    #expect(created)
    #expect(model.selectedSet?.variables.first?.value == "secret")

    await model.lock()
    #expect(model.lockState == .locked)
    #expect(model.sets.isEmpty)
  }

  @Test
  func exportRoundTripsThroughDotenvParser() async throws {
    let model = try makeModel()
    await model.unlock()
    _ = await model.create(
      EnvironmentSetDraft(
        name: "Export",
        variables: [EnvironmentVariable(key: "MULTILINE", value: "one\ntwo")]
      )
    )
    let id = try #require(model.selectedSetID)

    let exported = try #require(await model.dotenvForExport(id: id))
    let parsed = DotenvParser().parse(exported)

    #expect(parsed.errors.isEmpty)
    #expect(parsed.value(for: "MULTILINE") == "one\ntwo")
  }

  private func makeModel() throws -> VaultViewModel {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "EnvStoreViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return VaultViewModel(
      databaseURL: directory.appending(path: "vault.sqlite"),
      rootKeyStore: InMemoryRootKeyStore()
    )
  }
}

private struct FailingRootKeyStore: RootKeyStore {
  let error: EnvStoreCryptoError

  func loadExisting(reason _: String) throws -> VaultKey {
    throw error
  }

  func createIfMissing(reason _: String) throws -> VaultKey {
    throw error
  }
}
