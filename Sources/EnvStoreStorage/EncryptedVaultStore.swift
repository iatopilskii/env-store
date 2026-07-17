import CSQLite
import EnvStoreCore
import EnvStoreCrypto
import Foundation

public actor EncryptedVaultStore {
  public struct ManagerSnapshot: Sendable {
    public let sets: [EnvironmentSet]
    public let projectBindings: [ProjectBinding]
    public let profiles: [CommandProfile]
  }

  public struct ResolvedProfile: Sendable {
    public let profile: CommandProfile
    public let set: EnvironmentSet
  }
  private struct VariableHeader: Codable {
    let id: UUID
    let key: String
  }

  private struct SetManifest: Codable {
    let name: String
    let note: String
    let variables: [VariableHeader]
    let createdAt: Date
    let updatedAt: Date
  }

  private struct SetRow {
    let id: UUID
    let revision: Int
    let wrappedKey: SealedPayload
    let manifest: SealedPayload
  }

  private let connection: SQLiteConnection
  private let cipher = EnvelopeCipher()
  private let rootKeyStore: any RootKeyStore
  private let vaultID: UUID
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    databaseURL: URL,
    rootKeyStore: any RootKeyStore,
    verifyRootKeyOnOpen: Bool = true,
    allowCreatingVault: Bool = true
  ) throws {
    let fileManager = FileManager.default
    let existed = fileManager.fileExists(atPath: databaseURL.path)
    let directory = databaseURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    if existed, verifyRootKeyOnOpen {
      _ = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    } else if !existed, allowCreatingVault {
      _ = try rootKeyStore.createIfMissing(reason: "Create EnvStore vault")
    } else if !existed {
      throw EnvStoreStorageError.vaultNotFound
    }

    let connection = try SQLiteConnection(url: databaseURL)
    try connection.configure()
    try Self.migrate(connection)
    let vaultID = try Self.loadOrCreateVaultID(connection, canCreate: !existed)

    self.connection = connection
    self.rootKeyStore = rootKeyStore
    self.vaultID = vaultID
    encoder = JSONEncoder()
    decoder = JSONDecoder()

    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
  }

  public func createSet(_ draft: EnvironmentSetDraft) throws -> EnvironmentSet {
    try draft.validate()
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    let setKey = try VaultKey.random()
    let id = UUID()
    let now = Date()
    let set = EnvironmentSet(
      id: id,
      name: draft.name,
      note: draft.note,
      variables: draft.variables,
      revision: 1,
      createdAt: now,
      updatedAt: now
    )

    return try connection.transaction {
      let wrappedKey = try cipher.wrap(
        setKey,
        using: rootKey,
        context: context(id: id, kind: .wrappedSetKey)
      )
      let manifest = try sealManifest(for: set, key: setKey)
      try insertSetRow(set, wrappedKey: wrappedKey, manifest: manifest)
      try replaceVariables(for: set, key: setKey)
      try insertRevision(set, key: setKey)
      return set
    }
  }

  public func listSets() throws -> [EnvironmentSet] {
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    return try listSets(using: rootKey)
  }

  public func loadManagerSnapshot() throws -> ManagerSnapshot {
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    let sets = try listSets(using: rootKey)
    let bindings: [ProjectBinding] = try listSecureRecords(
      kind: .projectBinding,
      using: try domainKey(from: rootKey, kind: .projectBinding)
    )
    let profiles: [CommandProfile] = try listSecureRecords(
      kind: .commandProfile,
      using: try domainKey(from: rootKey, kind: .commandProfile)
    )
    return ManagerSnapshot(
      sets: sets,
      projectBindings: bindings.sorted {
        $0.path.localizedStandardCompare($1.path) == .orderedAscending
      },
      profiles: profiles.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
    )
  }

  public func listProjectBindings() throws -> [ProjectBinding] {
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    return try listSecureRecords(
      kind: .projectBinding,
      using: try domainKey(from: rootKey, kind: .projectBinding)
    )
    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }

  public func saveProjectBinding(_ binding: ProjectBinding) throws {
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    try saveSecureRecord(
      binding,
      id: binding.id,
      kind: .projectBinding,
      using: try domainKey(from: rootKey, kind: .projectBinding)
    )
  }

  public func deleteProjectBinding(id: UUID) throws {
    try deleteSecureRecord(id: id, kind: .projectBinding)
  }

  public func listCommandProfiles() throws -> [CommandProfile] {
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    return try listSecureRecords(
      kind: .commandProfile,
      using: try domainKey(from: rootKey, kind: .commandProfile)
    )
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public func saveCommandProfile(_ profile: CommandProfile) throws {
    try profile.validate()
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    try saveSecureRecord(
      profile,
      id: profile.id,
      kind: .commandProfile,
      using: try domainKey(from: rootKey, kind: .commandProfile)
    )
  }

  public func deleteCommandProfile(id: UUID) throws {
    try deleteSecureRecord(id: id, kind: .commandProfile)
  }

  public func resolveSet(name: String?, workingDirectory: String) throws -> EnvironmentSet {
    let rootKey = try rootKeyStore.loadExisting(reason: "Authorize command environment")
    let sets = try listSets(using: rootKey)
    if let name {
      guard let set = sets.first(where: { $0.name == name }) else {
        throw EnvStoreStorageError.setNotFound(UUID())
      }
      return set
    }
    let bindings: [ProjectBinding] = try listSecureRecords(
      kind: .projectBinding,
      using: try domainKey(from: rootKey, kind: .projectBinding)
    )
    guard
      let binding = ProjectBindingResolver().resolve(
        workingDirectory: workingDirectory,
        bindings: bindings
      ), let set = sets.first(where: { $0.id == binding.setID })
    else {
      throw EnvStoreStorageError.projectNotLinked
    }
    return set
  }

  public func resolveProfile(name: String) throws -> ResolvedProfile {
    let rootKey = try rootKeyStore.loadExisting(reason: "Authorize command profile")
    let profiles: [CommandProfile] = try listSecureRecords(
      kind: .commandProfile,
      using: try domainKey(from: rootKey, kind: .commandProfile)
    )
    guard let profile = profiles.first(where: { $0.name == name }) else {
      throw EnvStoreStorageError.profileNotFound
    }
    let sets = try listSets(using: rootKey)
    guard let set = sets.first(where: { $0.id == profile.setID }) else {
      throw EnvStoreStorageError.setNotFound(profile.setID)
    }
    return ResolvedProfile(profile: profile, set: set)
  }

  private func listSets(using rootKey: VaultKey) throws -> [EnvironmentSet] {
    let statement = try connection.prepare(
      "SELECT id, revision, wrapped_nonce, wrapped_ciphertext, wrapped_tag, manifest_nonce, manifest_ciphertext, manifest_tag FROM environment_sets"
    )
    var sets: [EnvironmentSet] = []
    while try statement.step() {
      sets.append(try decryptSet(row: try setRow(from: statement), rootKey: rootKey))
    }
    return sets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public func loadSet(id: UUID) throws -> EnvironmentSet {
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    return try decryptSet(row: try loadSetRow(id: id), rootKey: rootKey)
  }

  public func updateSet(id: UUID, draft: EnvironmentSetDraft) throws -> EnvironmentSet {
    try draft.validate()
    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")

    return try connection.transaction {
      let row = try loadSetRow(id: id)
      let previous = try decryptSet(row: row, rootKey: rootKey)
      let setKey = try cipher.unwrap(
        row.wrappedKey,
        using: rootKey,
        context: context(id: id, kind: .wrappedSetKey)
      )
      let updated = EnvironmentSet(
        id: id,
        name: draft.name,
        note: draft.note,
        variables: draft.variables,
        revision: previous.revision + 1,
        createdAt: previous.createdAt,
        updatedAt: Date()
      )
      let manifest = try sealManifest(for: updated, key: setKey)
      try updateSetRow(updated, manifest: manifest)
      try replaceVariables(for: updated, key: setKey)
      try insertRevision(updated, key: setKey)
      try pruneRevisions(setID: id, retaining: 20)
      return updated
    }
  }

  public func deleteSet(id: UUID) throws {
    let statement = try connection.prepare("DELETE FROM environment_sets WHERE id = ?")
    try statement.bind(id.uuidString.lowercased(), at: 1)
    _ = try statement.step()
  }

  public func revisions(for setID: UUID) throws -> [EnvironmentSet] {
    let countStatement = try connection.prepare(
      "SELECT COUNT(*) FROM revisions WHERE set_id = ?"
    )
    try countStatement.bind(setID.uuidString.lowercased(), at: 1)
    guard try countStatement.step(), countStatement.integer(at: 0) > 0 else {
      return []
    }

    let rootKey = try rootKeyStore.loadExisting(reason: "Unlock EnvStore vault")
    let row = try loadSetRow(id: setID)
    let setKey = try cipher.unwrap(
      row.wrappedKey,
      using: rootKey,
      context: context(id: setID, kind: .wrappedSetKey)
    )
    let statement = try connection.prepare(
      "SELECT record_id, nonce, ciphertext, tag FROM revisions WHERE set_id = ? ORDER BY revision DESC"
    )
    try statement.bind(setID.uuidString.lowercased(), at: 1)
    var snapshots: [EnvironmentSet] = []
    while try statement.step() {
      guard let recordID = UUID(uuidString: try statement.text(at: 0)) else {
        throw EnvStoreStorageError.invalidStoredData
      }
      let payload = SealedPayload(
        nonce: statement.data(at: 1),
        ciphertext: statement.data(at: 2),
        tag: statement.data(at: 3)
      )
      let data = try cipher.open(
        payload,
        using: setKey,
        context: context(id: recordID, kind: .revisionSnapshot)
      )
      snapshots.append(try decoder.decode(EnvironmentSet.self, from: data))
    }
    return snapshots
  }

  public func close() {
    connection.close()
  }

  private func decryptSet(row: SetRow, rootKey: VaultKey) throws -> EnvironmentSet {
    let setKey = try cipher.unwrap(
      row.wrappedKey,
      using: rootKey,
      context: context(id: row.id, kind: .wrappedSetKey)
    )
    let manifestData = try cipher.open(
      row.manifest,
      using: setKey,
      context: context(id: row.id, kind: .setManifest)
    )
    let manifest = try decoder.decode(SetManifest.self, from: manifestData)
    let values = try loadVariableValues(setID: row.id, headers: manifest.variables, key: setKey)
    return EnvironmentSet(
      id: row.id,
      name: manifest.name,
      note: manifest.note,
      variables: values,
      revision: row.revision,
      createdAt: manifest.createdAt,
      updatedAt: manifest.updatedAt
    )
  }

  private func sealManifest(for set: EnvironmentSet, key: VaultKey) throws -> SealedPayload {
    let manifest = SetManifest(
      name: set.name,
      note: set.note,
      variables: set.variables.map { VariableHeader(id: $0.id, key: $0.key) },
      createdAt: set.createdAt,
      updatedAt: set.updatedAt
    )
    return try cipher.seal(
      encoder.encode(manifest),
      using: key,
      context: context(id: set.id, kind: .setManifest)
    )
  }

  private func insertSetRow(
    _ set: EnvironmentSet,
    wrappedKey: SealedPayload,
    manifest: SealedPayload
  ) throws {
    let statement = try connection.prepare(
      "INSERT INTO environment_sets (id, revision, wrapped_nonce, wrapped_ciphertext, wrapped_tag, manifest_nonce, manifest_ciphertext, manifest_tag) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    )
    try statement.bind(set.id.uuidString.lowercased(), at: 1)
    try statement.bind(set.revision, at: 2)
    try bind(wrappedKey, to: statement, startingAt: 3)
    try bind(manifest, to: statement, startingAt: 6)
    _ = try statement.step()
  }

  private func updateSetRow(_ set: EnvironmentSet, manifest: SealedPayload) throws {
    let statement = try connection.prepare(
      "UPDATE environment_sets SET revision = ?, manifest_nonce = ?, manifest_ciphertext = ?, manifest_tag = ? WHERE id = ?"
    )
    try statement.bind(set.revision, at: 1)
    try bind(manifest, to: statement, startingAt: 2)
    try statement.bind(set.id.uuidString.lowercased(), at: 5)
    _ = try statement.step()
  }

  private func replaceVariables(for set: EnvironmentSet, key: VaultKey) throws {
    let delete = try connection.prepare("DELETE FROM variable_values WHERE set_id = ?")
    try delete.bind(set.id.uuidString.lowercased(), at: 1)
    _ = try delete.step()

    for (position, variable) in set.variables.enumerated() {
      let payload = try cipher.seal(
        Data(variable.value.utf8),
        using: key,
        context: context(id: variable.id, kind: .variableValue)
      )
      let insert = try connection.prepare(
        "INSERT INTO variable_values (id, set_id, position, nonce, ciphertext, tag) VALUES (?, ?, ?, ?, ?, ?)"
      )
      try insert.bind(variable.id.uuidString.lowercased(), at: 1)
      try insert.bind(set.id.uuidString.lowercased(), at: 2)
      try insert.bind(position, at: 3)
      try bind(payload, to: insert, startingAt: 4)
      _ = try insert.step()
    }
  }

  private func loadVariableValues(
    setID: UUID,
    headers: [VariableHeader],
    key: VaultKey
  ) throws -> [EnvironmentVariable] {
    let statement = try connection.prepare(
      "SELECT id, nonce, ciphertext, tag FROM variable_values WHERE set_id = ? ORDER BY position"
    )
    try statement.bind(setID.uuidString.lowercased(), at: 1)
    var encryptedByID: [UUID: SealedPayload] = [:]
    while try statement.step() {
      guard let id = UUID(uuidString: try statement.text(at: 0)) else {
        throw EnvStoreStorageError.invalidStoredData
      }
      encryptedByID[id] = SealedPayload(
        nonce: statement.data(at: 1),
        ciphertext: statement.data(at: 2),
        tag: statement.data(at: 3)
      )
    }

    return try headers.map { header in
      guard let payload = encryptedByID[header.id] else {
        throw EnvStoreStorageError.invalidStoredData
      }
      let valueData = try cipher.open(
        payload,
        using: key,
        context: context(id: header.id, kind: .variableValue)
      )
      guard let value = String(data: valueData, encoding: .utf8) else {
        throw EnvStoreStorageError.invalidStoredData
      }
      return EnvironmentVariable(id: header.id, key: header.key, value: value)
    }
  }

  private func insertRevision(_ set: EnvironmentSet, key: VaultKey) throws {
    let recordID = UUID()
    let payload = try cipher.seal(
      encoder.encode(set),
      using: key,
      context: context(id: recordID, kind: .revisionSnapshot)
    )
    let statement = try connection.prepare(
      "INSERT INTO revisions (set_id, revision, record_id, nonce, ciphertext, tag) VALUES (?, ?, ?, ?, ?, ?)"
    )
    try statement.bind(set.id.uuidString.lowercased(), at: 1)
    try statement.bind(set.revision, at: 2)
    try statement.bind(recordID.uuidString.lowercased(), at: 3)
    try bind(payload, to: statement, startingAt: 4)
    _ = try statement.step()
  }

  private func pruneRevisions(setID: UUID, retaining count: Int) throws {
    let statement = try connection.prepare(
      "DELETE FROM revisions WHERE set_id = ? AND revision NOT IN (SELECT revision FROM revisions WHERE set_id = ? ORDER BY revision DESC LIMIT ?)"
    )
    let id = setID.uuidString.lowercased()
    try statement.bind(id, at: 1)
    try statement.bind(id, at: 2)
    try statement.bind(count, at: 3)
    _ = try statement.step()
  }

  private func loadSetRow(id: UUID) throws -> SetRow {
    let statement = try connection.prepare(
      "SELECT id, revision, wrapped_nonce, wrapped_ciphertext, wrapped_tag, manifest_nonce, manifest_ciphertext, manifest_tag FROM environment_sets WHERE id = ?"
    )
    try statement.bind(id.uuidString.lowercased(), at: 1)
    guard try statement.step() else {
      throw EnvStoreStorageError.setNotFound(id)
    }
    return try setRow(from: statement)
  }

  private func setRow(from statement: SQLiteStatement) throws -> SetRow {
    guard let id = UUID(uuidString: try statement.text(at: 0)) else {
      throw EnvStoreStorageError.invalidStoredData
    }
    return SetRow(
      id: id,
      revision: statement.integer(at: 1),
      wrappedKey: SealedPayload(
        nonce: statement.data(at: 2),
        ciphertext: statement.data(at: 3),
        tag: statement.data(at: 4)
      ),
      manifest: SealedPayload(
        nonce: statement.data(at: 5),
        ciphertext: statement.data(at: 6),
        tag: statement.data(at: 7)
      )
    )
  }

  private func bind(
    _ payload: SealedPayload,
    to statement: SQLiteStatement,
    startingAt index: Int32
  ) throws {
    try statement.bind(payload.nonce, at: index)
    try statement.bind(payload.ciphertext, at: index + 1)
    try statement.bind(payload.tag, at: index + 2)
  }

  private func context(id: UUID, kind: RecordKind) -> RecordContext {
    RecordContext(vaultID: vaultID, recordID: id, kind: kind, schemaVersion: 1)
  }

  private func domainKey(from rootKey: VaultKey, kind: RecordKind) throws -> VaultKey {
    try cipher.deriveDomainKey(from: rootKey, vaultID: vaultID, kind: kind)
  }

  private func saveSecureRecord<Value: Encodable>(
    _ value: Value,
    id: UUID,
    kind: RecordKind,
    using rootKey: VaultKey
  ) throws {
    let payload = try cipher.seal(
      encoder.encode(value),
      using: rootKey,
      context: context(id: id, kind: kind)
    )
    let statement = try connection.prepare(
      "INSERT INTO secure_records (id, record_kind, nonce, ciphertext, tag) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id, record_kind) DO UPDATE SET nonce = excluded.nonce, ciphertext = excluded.ciphertext, tag = excluded.tag"
    )
    try statement.bind(id.uuidString.lowercased(), at: 1)
    try statement.bind(kind.rawValue, at: 2)
    try bind(payload, to: statement, startingAt: 3)
    _ = try statement.step()
  }

  private func listSecureRecords<Value: Decodable>(
    kind: RecordKind,
    using rootKey: VaultKey
  ) throws -> [Value] {
    let statement = try connection.prepare(
      "SELECT id, nonce, ciphertext, tag FROM secure_records WHERE record_kind = ?"
    )
    try statement.bind(kind.rawValue, at: 1)
    var values: [Value] = []
    while try statement.step() {
      guard let id = UUID(uuidString: try statement.text(at: 0)) else {
        throw EnvStoreStorageError.invalidStoredData
      }
      let payload = SealedPayload(
        nonce: statement.data(at: 1),
        ciphertext: statement.data(at: 2),
        tag: statement.data(at: 3)
      )
      let data = try cipher.open(
        payload,
        using: rootKey,
        context: context(id: id, kind: kind)
      )
      values.append(try decoder.decode(Value.self, from: data))
    }
    return values
  }

  private func deleteSecureRecord(id: UUID, kind: RecordKind) throws {
    let statement = try connection.prepare(
      "DELETE FROM secure_records WHERE id = ? AND record_kind = ?"
    )
    try statement.bind(id.uuidString.lowercased(), at: 1)
    try statement.bind(kind.rawValue, at: 2)
    _ = try statement.step()
  }

  private static func migrate(_ connection: SQLiteConnection) throws {
    try connection.transaction {
      try connection.execute(
        "CREATE TABLE IF NOT EXISTS vault_meta (schema_version INTEGER NOT NULL, vault_id TEXT NOT NULL)"
      )
      try connection.execute(
        "CREATE TABLE IF NOT EXISTS environment_sets (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, wrapped_nonce BLOB NOT NULL, wrapped_ciphertext BLOB NOT NULL, wrapped_tag BLOB NOT NULL, manifest_nonce BLOB NOT NULL, manifest_ciphertext BLOB NOT NULL, manifest_tag BLOB NOT NULL)"
      )
      try connection.execute(
        "CREATE TABLE IF NOT EXISTS variable_values (id TEXT PRIMARY KEY, set_id TEXT NOT NULL REFERENCES environment_sets(id) ON DELETE CASCADE, position INTEGER NOT NULL, nonce BLOB NOT NULL, ciphertext BLOB NOT NULL, tag BLOB NOT NULL)"
      )
      try connection.execute(
        "CREATE TABLE IF NOT EXISTS revisions (set_id TEXT NOT NULL REFERENCES environment_sets(id) ON DELETE CASCADE, revision INTEGER NOT NULL, record_id TEXT NOT NULL, nonce BLOB NOT NULL, ciphertext BLOB NOT NULL, tag BLOB NOT NULL, PRIMARY KEY (set_id, revision))"
      )
      try connection.execute(
        "CREATE TABLE IF NOT EXISTS secure_records (id TEXT NOT NULL, record_kind TEXT NOT NULL, nonce BLOB NOT NULL, ciphertext BLOB NOT NULL, tag BLOB NOT NULL, PRIMARY KEY (id, record_kind))"
      )
    }
  }

  private static func loadOrCreateVaultID(
    _ connection: SQLiteConnection,
    canCreate: Bool
  ) throws -> UUID {
    let query = try connection.prepare("SELECT vault_id FROM vault_meta LIMIT 1")
    if try query.step() {
      guard let id = UUID(uuidString: try query.text(at: 0)) else {
        throw EnvStoreStorageError.invalidStoredData
      }
      return id
    }
    guard canCreate else {
      throw EnvStoreStorageError.invalidStoredData
    }

    let id = UUID()
    let insert = try connection.prepare(
      "INSERT INTO vault_meta (schema_version, vault_id) VALUES (1, ?)")
    try insert.bind(id.uuidString.lowercased(), at: 1)
    _ = try insert.step()
    return id
  }
}
