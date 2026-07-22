import Darwin
import Foundation

public struct ManagedSkillInstallation: Codable, Equatable, Sendable {
  public let version: String
  public let installedAt: Date

  public init(version: String, installedAt: Date = Date()) {
    self.version = version
    self.installedAt = installedAt
  }
}

public struct InstallationManifest: Codable, Equatable, Sendable {
  public var schemaVersion = 1
  public var componentVersions: [String: String] = [:]
  public var agentSkillMethod: AgentSkillInstallationMethod?
  public var managedSkillDestinations: [String: ManagedSkillInstallation] = [:]

  public init() {}
}

public struct InstallationManifestStore: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func load() throws -> InstallationManifest {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return InstallationManifest()
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(InstallationManifest.self, from: Data(contentsOf: url))
  }

  public func save(_ manifest: InstallationManifest) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

enum InstallationFileLock {
  static func withLock<Result>(at url: URL, operation: () throws -> Result) throws -> Result {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let descriptor = url.path.withCString {
      Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
      throw EnvStoreSetupError.posixFailure(operation: "open setup lock", code: errno)
    }
    defer { Darwin.close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else {
      throw EnvStoreSetupError.posixFailure(operation: "lock setup", code: errno)
    }
    defer { flock(descriptor, LOCK_UN) }
    return try operation()
  }
}
