import Foundation

public struct CommandRequest: Codable, Equatable, Sendable {
  public let setID: UUID
  public let workingDirectory: String
  public let executablePath: String
  public let arguments: [String]
  public let executableSearchPath: [String]?

  public init(
    setID: UUID,
    workingDirectory: String,
    executablePath: String,
    arguments: [String],
    executableSearchPath: [String]? = nil
  ) {
    self.setID = setID
    self.workingDirectory = workingDirectory.standardizedAbsolutePath
    self.executablePath = executablePath.standardizedAbsolutePath
    self.arguments = arguments
    self.executableSearchPath = executableSearchPath
  }
}

public enum EnvStoreErrorCode: String, Codable, Error, Sendable {
  case authorizationRequired = "authorization_required"
  case authorizationDenied = "authorization_denied"
  case grantExpired = "grant_expired"
  case grantExhausted = "grant_exhausted"
  case grantScopeMismatch = "grant_scope_mismatch"
  case profileNotFound = "profile_not_found"
  case projectNotLinked = "project_not_linked"
  case commandChanged = "command_changed"
  case brokerUnavailable = "broker_unavailable"
  case vaultUnavailable = "vault_unavailable"
  case commandNotFound = "command_not_found"
  case invalidRequest = "invalid_request"
  case incompatibleProtocol = "incompatible_protocol"
}

public enum GrantAuthorization: Equatable, Sendable {
  case allowed
  case denied(EnvStoreErrorCode)
}

public enum GrantValidationError: Error, Equatable, Sendable {
  case invalidExpiration
  case invalidMaximumUses
}

public struct ExecutionGrant: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let request: CommandRequest
  public let expiresAt: Date
  public let maximumUses: Int
  public private(set) var consumedUses: Int

  public init(
    id: UUID = UUID(),
    request: CommandRequest,
    expiresAt: Date,
    maximumUses: Int,
    consumedUses: Int = 0
  ) {
    self.id = id
    self.request = request
    self.expiresAt = expiresAt
    self.maximumUses = maximumUses
    self.consumedUses = consumedUses
  }

  public static func validated(
    request: CommandRequest,
    expiresAt: Date,
    maximumUses: Int,
    now: Date = Date()
  ) throws -> ExecutionGrant {
    guard expiresAt > now else {
      throw GrantValidationError.invalidExpiration
    }

    guard maximumUses > 0 else {
      throw GrantValidationError.invalidMaximumUses
    }

    return ExecutionGrant(request: request, expiresAt: expiresAt, maximumUses: maximumUses)
  }

  public func authorization(for candidate: CommandRequest, at date: Date = Date())
    -> GrantAuthorization
  {
    guard expiresAt > date else {
      return .denied(.grantExpired)
    }

    guard consumedUses < maximumUses else {
      return .denied(.grantExhausted)
    }

    guard candidate == request else {
      return .denied(.grantScopeMismatch)
    }

    return .allowed
  }

  public mutating func recordUse() {
    consumedUses += 1
  }
}
