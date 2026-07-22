import Combine
import EnvStoreCore
import EnvStoreCrypto
import EnvStoreStorage
import Foundation
import Security

public struct SafeActivityEvent: Identifiable, Equatable, Sendable {
  public enum Kind: String, Sendable {
    case copied
    case created
    case deleted
    case exported
    case imported
    case locked
    case revealed
    case updated
    case unlocked
  }

  public let id: UUID
  public let kind: Kind
  public let setName: String?
  public let variableKey: String?
  public let date: Date

  public init(
    id: UUID = UUID(),
    kind: Kind,
    setName: String? = nil,
    variableKey: String? = nil,
    date: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.setName = setName
    self.variableKey = variableKey
    self.date = date
  }
}

@MainActor
public final class VaultViewModel: ObservableObject {
  public enum LockState: Equatable {
    case locked
    case unlocking
    case unlocked
  }

  @Published public private(set) var lockState: LockState = .locked
  @Published public private(set) var sets: [EnvironmentSet] = []
  @Published public private(set) var projectBindings: [ProjectBinding] = []
  @Published public private(set) var profiles: [CommandProfile] = []
  @Published public private(set) var activity: [SafeActivityEvent] = []
  @Published public var selectedSetID: UUID?
  @Published public private(set) var errorMessage: String?

  private let databaseURL: URL
  private let rootKeyStore: any RootKeyStore
  private var store: EncryptedVaultStore?

  public init(databaseURL: URL, rootKeyStore: any RootKeyStore) {
    self.databaseURL = databaseURL
    self.rootKeyStore = rootKeyStore
  }

  public convenience init() {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    self.init(
      databaseURL:
        applicationSupport
        .appending(path: "EnvStore", directoryHint: .isDirectory)
        .appending(path: "vault.sqlite"),
      rootKeyStore: KeychainRootKeyStore()
    )
  }

  public var selectedSet: EnvironmentSet? {
    sets.first { $0.id == selectedSetID }
  }

  public func unlock() async {
    guard lockState != .unlocking else { return }
    lockState = .unlocking
    errorMessage = nil
    do {
      let store = try EncryptedVaultStore(
        databaseURL: databaseURL,
        rootKeyStore: rootKeyStore,
        verifyRootKeyOnOpen: false
      )
      self.store = store
      let snapshot = try await store.loadManagerSnapshot()
      sets = snapshot.sets
      projectBindings = snapshot.projectBindings
      profiles = snapshot.profiles
      selectedSetID =
        selectedSetID.flatMap { id in
          sets.contains(where: { $0.id == id }) ? id : nil
        } ?? sets.first?.id
      lockState = .unlocked
      record(.unlocked)
    } catch {
      store = nil
      lockState = .locked
      errorMessage = friendlyMessage(for: error)
    }
  }

  public func lock() async {
    if let store {
      await store.close()
    }
    store = nil
    sets = []
    projectBindings = []
    profiles = []
    selectedSetID = nil
    lockState = .locked
    record(.locked)
  }

  public func create(_ draft: EnvironmentSetDraft, imported: Bool = false) async -> Bool {
    guard let store else { return false }
    do {
      let created = try await store.createSet(draft)
      sets.append(created)
      sets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      selectedSetID = created.id
      record(imported ? .imported : .created, setName: created.name)
      errorMessage = nil
      return true
    } catch {
      errorMessage = friendlyMessage(for: error)
      return false
    }
  }

  public func update(id: UUID, draft: EnvironmentSetDraft) async -> Bool {
    guard let store else { return false }
    do {
      let updated = try await store.updateSet(id: id, draft: draft)
      sets.removeAll { $0.id == id }
      sets.append(updated)
      sets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      selectedSetID = id
      record(.updated, setName: updated.name)
      errorMessage = nil
      return true
    } catch {
      errorMessage = friendlyMessage(for: error)
      return false
    }
  }

  public func duplicate(id: UUID) async -> Bool {
    guard let source = sets.first(where: { $0.id == id }) else { return false }
    let variables = source.variables.map {
      EnvironmentVariable(key: $0.key, value: $0.value)
    }
    return await create(
      EnvironmentSetDraft(
        name: "\(source.name) Copy",
        note: source.note,
        variables: variables
      )
    )
  }

  public func delete(id: UUID) async -> Bool {
    guard let store, let existing = sets.first(where: { $0.id == id }) else {
      return false
    }
    do {
      try await store.deleteSet(id: id)
      sets.removeAll { $0.id == id }
      selectedSetID = sets.first?.id
      record(.deleted, setName: existing.name)
      errorMessage = nil
      return true
    } catch {
      errorMessage = friendlyMessage(for: error)
      return false
    }
  }

  public func revisions(for id: UUID) async -> [EnvironmentSet] {
    guard let store else { return [] }
    do {
      return try await store.revisions(for: id)
    } catch {
      errorMessage = friendlyMessage(for: error)
      return []
    }
  }

  public func saveProjectBinding(path: String, setID: UUID) async -> Bool {
    guard let store else { return false }
    let normalized = path.standardizedAbsolutePath
    let binding =
      projectBindings.first(where: { $0.path == normalized })
      .map { ProjectBinding(id: $0.id, path: normalized, setID: setID) }
      ?? ProjectBinding(path: normalized, setID: setID)
    do {
      try await store.saveProjectBinding(binding)
      projectBindings.removeAll { $0.id == binding.id || $0.path == binding.path }
      projectBindings.append(binding)
      projectBindings.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
      errorMessage = nil
      return true
    } catch {
      errorMessage = friendlyMessage(for: error)
      return false
    }
  }

  public func deleteProjectBinding(id: UUID) async {
    guard let store else { return }
    do {
      try await store.deleteProjectBinding(id: id)
      projectBindings.removeAll { $0.id == id }
    } catch {
      errorMessage = friendlyMessage(for: error)
    }
  }

  public func saveProfile(_ profile: CommandProfile) async -> Bool {
    guard let store else { return false }
    do {
      try await store.saveCommandProfile(profile)
      profiles.removeAll { $0.id == profile.id }
      profiles.append(profile)
      profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      errorMessage = nil
      return true
    } catch {
      errorMessage = friendlyMessage(for: error)
      return false
    }
  }

  public func deleteProfile(id: UUID) async {
    guard let store else { return }
    do {
      try await store.deleteCommandProfile(id: id)
      profiles.removeAll { $0.id == id }
    } catch {
      errorMessage = friendlyMessage(for: error)
    }
  }

  public func restore(_ revision: EnvironmentSet) async -> Bool {
    await update(
      id: revision.id,
      draft: EnvironmentSetDraft(
        name: revision.name,
        note: revision.note,
        variables: revision.variables
      )
    )
  }

  public func dotenvForExport(id: UUID) async -> String? {
    guard let store else { return nil }
    do {
      let set = try await store.loadSet(id: id)
      record(.exported, setName: set.name)
      return DotenvSerializer().serialize(
        set.variables.enumerated().map { index, variable in
          DotenvVariable(key: variable.key, value: variable.value, sourceLine: index + 1)
        }
      ) + "\n"
    } catch {
      errorMessage = friendlyMessage(for: error)
      return nil
    }
  }

  public func recordReveal(setName: String, key: String) {
    record(.revealed, setName: setName, variableKey: key)
  }

  public func recordCopy(setName: String, key: String) {
    record(.copied, setName: setName, variableKey: key)
  }

  public func clearError() {
    errorMessage = nil
  }

  private func record(
    _ kind: SafeActivityEvent.Kind,
    setName: String? = nil,
    variableKey: String? = nil
  ) {
    activity.insert(
      SafeActivityEvent(kind: kind, setName: setName, variableKey: variableKey),
      at: 0
    )
    if activity.count > 200 {
      activity.removeLast(activity.count - 200)
    }
  }

  private func friendlyMessage(for error: Error) -> String {
    switch error {
    case EnvStoreCryptoError.authenticationCanceled:
      "Authentication was canceled. The vault remains locked."
    case EnvStoreCryptoError.missingRootKey:
      "The vault key is missing. The encrypted database was preserved."
    case EnvStoreCryptoError.authenticationFailed:
      "A vault record failed authentication and was not opened."
    case EnvStoreCryptoError.authenticationRejected:
      "Authentication was not accepted. The vault remains locked."
    case EnvStoreCryptoError.authenticationUnavailable:
      "Touch ID or macOS password authentication is unavailable."
    case EnvStoreCryptoError.keychainFailure(let status) where status == errSecMissingEntitlement:
      "This build cannot access the Data Protection Keychain because its signing entitlement is missing."
    case EnvStoreCryptoError.keychainFailure(let status):
      keychainErrorMessage(status: status)
    case EnvironmentSetValidationError.emptyName:
      "Enter a name for this set."
    case EnvironmentSetValidationError.duplicateVariableKey(let key):
      "The key \(key) appears more than once."
    case EnvironmentSetValidationError.invalidVariableKey(let key):
      "The key \(key) is not a valid environment variable name."
    case EnvironmentSetValidationError.nullByte(let key):
      "The value for \(key) contains a NUL byte."
    default:
      "EnvStore could not complete the operation."
    }
  }

  private func keychainErrorMessage(status: OSStatus) -> String {
    let description =
      (SecCopyErrorMessageString(status, nil) as String?)
      ?? "Unknown Keychain error"
    return "Keychain error \(status): \(description)"
  }
}
