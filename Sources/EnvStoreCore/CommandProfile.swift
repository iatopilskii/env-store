import Foundation

public enum ProfileTrustMode: String, Codable, CaseIterable, Sendable {
  case development
  case strict
}

public struct CommandProfile: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let setID: UUID
  public let projectRoot: String
  public let executablePath: String
  public let arguments: [String]
  public let trustMode: ProfileTrustMode
  public let executableDigest: Data?
  public let defaultTTL: TimeInterval
  public let defaultUses: Int

  public init(
    id: UUID = UUID(),
    name: String,
    setID: UUID,
    projectRoot: String,
    executablePath: String,
    arguments: [String],
    trustMode: ProfileTrustMode,
    executableDigest: Data? = nil,
    defaultTTL: TimeInterval = 300,
    defaultUses: Int = 1
  ) {
    self.id = id
    self.name = name
    self.setID = setID
    self.projectRoot =
      projectRoot.hasPrefix("/")
      ? projectRoot.standardizedAbsolutePath
      : projectRoot
    self.executablePath =
      executablePath.hasPrefix("/")
      ? executablePath.standardizedAbsolutePath
      : executablePath
    self.arguments = arguments
    self.trustMode = trustMode
    self.executableDigest = executableDigest
    self.defaultTTL = defaultTTL
    self.defaultUses = defaultUses
  }
}

public enum CommandProfileValidationError: Error, Equatable, Sendable {
  case emptyName
  case invalidExecutable
  case invalidProjectRoot
  case invalidGrantDefaults
  case strictDigestRequired
}

extension CommandProfile {
  public func validate() throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommandProfileValidationError.emptyName
    }
    guard executablePath.hasPrefix("/") else {
      throw CommandProfileValidationError.invalidExecutable
    }
    guard projectRoot.hasPrefix("/") else {
      throw CommandProfileValidationError.invalidProjectRoot
    }
    guard defaultTTL > 0, defaultTTL <= 86_400, defaultUses > 0, defaultUses <= 1_000 else {
      throw CommandProfileValidationError.invalidGrantDefaults
    }
    if trustMode == .strict, executableDigest == nil {
      throw CommandProfileValidationError.strictDigestRequired
    }
  }
}
