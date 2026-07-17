import EnvStoreCore
@preconcurrency import Foundation

public enum EnvStoreIPC {
  public static let protocolVersion = 1
  public static let machServiceName = "dev.envstore.broker"
}

public enum BrokerOperation: String, Codable, Sendable {
  case context
  case doctor
  case grantList
  case grantRequest
  case profileGrantRequest
  case profileRun
  case grantRevoke
  case run
  case signal
}

public struct ProfileRunPayload: Codable, Equatable, Sendable {
  public let executionID: UUID
  public let name: String
  public let workingDirectory: String

  public init(executionID: UUID = UUID(), name: String, workingDirectory: String) {
    self.executionID = executionID
    self.name = name
    self.workingDirectory = workingDirectory.standardizedAbsolutePath
  }
}

public struct ProfileGrantPayload: Codable, Equatable, Sendable {
  public let profile: ProfileRunPayload
  public let expiresAt: Date?
  public let maximumUses: Int?

  public init(profile: ProfileRunPayload, expiresAt: Date? = nil, maximumUses: Int? = nil) {
    self.profile = profile
    self.expiresAt = expiresAt
    self.maximumUses = maximumUses
  }
}

public struct RunCommandPayload: Codable, Equatable, Sendable {
  public let executionID: UUID
  public let setName: String?
  public let workingDirectory: String
  public let executablePath: String
  public let arguments: [String]

  public init(
    executionID: UUID = UUID(),
    setName: String?,
    workingDirectory: String,
    executablePath: String,
    arguments: [String]
  ) {
    self.executionID = executionID
    self.setName = setName
    self.workingDirectory = workingDirectory.standardizedAbsolutePath
    self.executablePath =
      executablePath.hasPrefix("/")
      ? executablePath.standardizedAbsolutePath
      : executablePath
    self.arguments = arguments
  }
}

public struct ProcessSignalPayload: Codable, Equatable, Sendable {
  public let executionID: UUID
  public let signal: Int32

  public init(executionID: UUID, signal: Int32) {
    self.executionID = executionID
    self.signal = signal
  }
}

public struct GrantRequestPayload: Codable, Equatable, Sendable {
  public let command: RunCommandPayload
  public let expiresAt: Date
  public let maximumUses: Int

  public init(command: RunCommandPayload, expiresAt: Date, maximumUses: Int) {
    self.command = command
    self.expiresAt = expiresAt
    self.maximumUses = maximumUses
  }
}

public struct BrokerRequest: Codable, Equatable, Sendable {
  public let protocolVersion: Int
  public let operation: BrokerOperation
  public let run: RunCommandPayload?
  public let grant: GrantRequestPayload?
  public let profileRun: ProfileRunPayload?
  public let profileGrant: ProfileGrantPayload?
  public let identifier: UUID?
  public let processSignal: ProcessSignalPayload?

  public init(
    protocolVersion: Int = EnvStoreIPC.protocolVersion,
    operation: BrokerOperation,
    run: RunCommandPayload? = nil,
    grant: GrantRequestPayload? = nil,
    profileRun: ProfileRunPayload? = nil,
    profileGrant: ProfileGrantPayload? = nil,
    identifier: UUID? = nil,
    processSignal: ProcessSignalPayload? = nil
  ) {
    self.protocolVersion = protocolVersion
    self.operation = operation
    self.run = run
    self.grant = grant
    self.profileRun = profileRun
    self.profileGrant = profileGrant
    self.identifier = identifier
    self.processSignal = processSignal
  }
}

public struct GrantSummary: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let setName: String
  public let executablePath: String
  public let arguments: [String]
  public let workingDirectory: String
  public let expiresAt: Date
  public let remainingUses: Int

  public init(
    id: UUID,
    setName: String,
    executablePath: String,
    arguments: [String],
    workingDirectory: String,
    expiresAt: Date,
    remainingUses: Int
  ) {
    self.id = id
    self.setName = setName
    self.executablePath = executablePath
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.expiresAt = expiresAt
    self.remainingUses = remainingUses
  }
}

public struct BrokerContext: Codable, Equatable, Sendable {
  public let vaultAvailable: Bool
  public let setNames: [String]
  public let activeGrantCount: Int

  public init(vaultAvailable: Bool, setNames: [String], activeGrantCount: Int) {
    self.vaultAvailable = vaultAvailable
    self.setNames = setNames
    self.activeGrantCount = activeGrantCount
  }
}

public struct BrokerResponse: Codable, Equatable, Sendable {
  public let protocolVersion: Int
  public let success: Bool
  public let errorCode: EnvStoreErrorCode?
  public let message: String?
  public let exitCode: Int32?
  public let context: BrokerContext?
  public let grants: [GrantSummary]?

  public init(
    success: Bool,
    errorCode: EnvStoreErrorCode? = nil,
    message: String? = nil,
    exitCode: Int32? = nil,
    context: BrokerContext? = nil,
    grants: [GrantSummary]? = nil
  ) {
    protocolVersion = EnvStoreIPC.protocolVersion
    self.success = success
    self.errorCode = errorCode
    self.message = message
    self.exitCode = exitCode
    self.context = context
    self.grants = grants
  }
}

public enum BrokerCodec {
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
  }

  public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
  }
}

@objc public protocol EnvStoreBrokerXPCProtocol {
  func perform(
    _ request: NSData,
    standardInput: FileHandle,
    standardOutput: FileHandle,
    standardError: FileHandle,
    withReply reply: @escaping (NSData) -> Void
  )
}
