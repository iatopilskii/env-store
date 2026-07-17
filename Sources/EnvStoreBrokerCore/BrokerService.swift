import CryptoKit
import EnvStoreCore
import EnvStoreIPC
import EnvStoreStorage
@preconcurrency import Foundation

public final class BrokerService: Sendable {
  private let store: EncryptedVaultStore?
  private let vaultAvailable: Bool
  private let grants: GrantCache
  private let executor: ProcessExecutor
  private let executions: ExecutionRegistry

  public init(
    store: EncryptedVaultStore?,
    vaultAvailable: Bool,
    grants: GrantCache = GrantCache(),
    executor: ProcessExecutor = ProcessExecutor(),
    executions: ExecutionRegistry = ExecutionRegistry()
  ) {
    self.store = store
    self.vaultAvailable = vaultAvailable
    self.grants = grants
    self.executor = executor
    self.executions = executions
  }

  public func revokeAllGrants() {
    grants.revokeAll()
  }

  public func handle(
    _ request: BrokerRequest,
    io: ProcessIO = .inherited
  ) async -> BrokerResponse {
    guard request.protocolVersion == EnvStoreIPC.protocolVersion else {
      return failure(.incompatibleProtocol, "Incompatible EnvStore protocol")
    }

    do {
      switch request.operation {
      case .doctor:
        return BrokerResponse(
          success: true,
          message: vaultAvailable
            ? "Broker and vault are available" : "Broker is available; vault is not initialized"
        )
      case .context:
        let setNames = Array(Set(grants.summaries().map(\.setName))).sorted()
        return BrokerResponse(
          success: true,
          context: BrokerContext(
            vaultAvailable: vaultAvailable,
            setNames: setNames,
            activeGrantCount: grants.summaries().count
          )
        )
      case .grantList:
        return BrokerResponse(success: true, grants: grants.summaries())
      case .grantRevoke:
        guard let identifier = request.identifier else {
          return failure(.invalidRequest, "Grant identifier is required")
        }
        let revoked = grants.revoke(id: identifier)
        return BrokerResponse(
          success: revoked,
          errorCode: revoked ? nil : .invalidRequest,
          message: revoked ? "Grant revoked" : "Grant was not found"
        )
      case .grantRequest:
        guard let payload = request.grant else {
          return failure(.invalidRequest, "Grant payload is required")
        }
        let set = try await resolveSet(for: payload.command)
        let environment = Dictionary(
          uniqueKeysWithValues: set.variables.map { ($0.key, $0.value) }
        )
        let summary = try grants.insert(
          command: payload.command,
          setID: set.id,
          displaySetName: set.name,
          environment: environment,
          expiresAt: payload.expiresAt,
          maximumUses: payload.maximumUses
        )
        return BrokerResponse(success: true, grants: [summary])
      case .profileGrantRequest:
        guard let payload = request.profileGrant else {
          return failure(.invalidRequest, "Profile grant payload is required")
        }
        let resolved = try await resolveProfile(payload.profile)
        let command = command(for: resolved.profile, setName: resolved.set.name)
        let environment = Dictionary(
          uniqueKeysWithValues: resolved.set.variables.map { ($0.key, $0.value) }
        )
        let summary = try grants.insert(
          command: command,
          setID: resolved.set.id,
          displaySetName: resolved.set.name,
          environment: environment,
          expiresAt: payload.expiresAt
            ?? Date().addingTimeInterval(resolved.profile.defaultTTL),
          maximumUses: payload.maximumUses ?? resolved.profile.defaultUses
        )
        return BrokerResponse(success: true, grants: [summary])
      case .profileRun:
        guard let payload = request.profileRun else {
          return failure(.invalidRequest, "Profile payload is required")
        }
        let resolved = try await resolveProfile(payload)
        let command = command(
          for: resolved.profile,
          setName: resolved.set.name,
          executionID: payload.executionID
        )
        let environment =
          grants.consume(matching: command)
          ?? Dictionary(uniqueKeysWithValues: resolved.set.variables.map { ($0.key, $0.value) })
        let exitCode = try execute(command, environment: environment, io: io)
        return BrokerResponse(success: true, exitCode: exitCode)
      case .run:
        guard let command = request.run else {
          return failure(.invalidRequest, "Run payload is required")
        }
        let environment: [String: String]
        if let granted = grants.consume(matching: command) {
          environment = granted
        } else {
          let set = try await resolveSet(for: command)
          environment = Dictionary(
            uniqueKeysWithValues: set.variables.map { ($0.key, $0.value) }
          )
        }
        let exitCode = try execute(command, environment: environment, io: io)
        return BrokerResponse(success: true, exitCode: exitCode)
      case .signal:
        guard let payload = request.processSignal else {
          return failure(.invalidRequest, "Signal payload is required")
        }
        let forwarded = executions.forward(signal: payload.signal, to: payload.executionID)
        return BrokerResponse(
          success: forwarded,
          errorCode: forwarded ? nil : .invalidRequest,
          message: forwarded ? nil : "Execution is no longer active"
        )
      }
    } catch EnvStoreStorageError.setNotFound(_) {
      return failure(.profileNotFound, "Environment set was not found")
    } catch EnvStoreStorageError.projectNotLinked {
      return failure(.projectNotLinked, "No environment set is linked to this directory")
    } catch EnvStoreStorageError.profileNotFound {
      return failure(.profileNotFound, "Command profile was not found")
    } catch EnvStoreErrorCode.commandChanged {
      return failure(.commandChanged, "Strict profile executable digest changed")
    } catch ProcessExecutionError.executableNotFound {
      return failure(.commandNotFound, "Executable was not found or is not executable")
    } catch is ProcessExecutionError {
      return failure(.invalidRequest, "Command could not be started")
    } catch GrantValidationError.invalidExpiration {
      return failure(.invalidRequest, "Grant expiration must be in the future")
    } catch GrantValidationError.invalidMaximumUses {
      return failure(.invalidRequest, "Grant use count must be positive")
    } catch {
      return failure(.vaultUnavailable, "Vault could not be unlocked")
    }
  }

  private func resolveSet(for command: RunCommandPayload) async throws -> EnvironmentSet {
    guard let store else {
      throw EnvStoreStorageError.vaultNotFound
    }
    return try await store.resolveSet(
      name: command.setName,
      workingDirectory: command.workingDirectory
    )
  }

  private func failure(_ code: EnvStoreErrorCode, _ message: String) -> BrokerResponse {
    BrokerResponse(success: false, errorCode: code, message: message)
  }

  private func resolveProfile(
    _ payload: ProfileRunPayload
  ) async throws -> EncryptedVaultStore.ResolvedProfile {
    guard let store else { throw EnvStoreStorageError.vaultNotFound }
    let resolved = try await store.resolveProfile(name: payload.name)
    let rootComponents = URL(fileURLWithPath: resolved.profile.projectRoot).pathComponents
    let workingComponents = URL(fileURLWithPath: payload.workingDirectory).pathComponents
    guard rootComponents.count <= workingComponents.count,
      Array(workingComponents.prefix(rootComponents.count)) == rootComponents
    else {
      throw EnvStoreStorageError.projectNotLinked
    }
    if resolved.profile.trustMode == .strict {
      guard let expected = resolved.profile.executableDigest,
        let data = try? Data(contentsOf: URL(fileURLWithPath: resolved.profile.executablePath)),
        Data(SHA256.hash(data: data)) == expected
      else {
        throw EnvStoreErrorCode.commandChanged
      }
    }
    return resolved
  }

  private func command(
    for profile: CommandProfile,
    setName: String,
    executionID: UUID = UUID()
  ) -> RunCommandPayload {
    RunCommandPayload(
      executionID: executionID,
      setName: setName,
      workingDirectory: profile.projectRoot,
      executablePath: profile.executablePath,
      arguments: profile.arguments
    )
  }

  private func execute(
    _ command: RunCommandPayload,
    environment: [String: String],
    io: ProcessIO
  ) throws -> Int32 {
    defer { executions.unregister(executionID: command.executionID) }
    return try executor.run(
      command: command,
      injectedEnvironment: environment,
      io: io
    ) { [executions] processID in
      executions.register(executionID: command.executionID, processID: processID)
    }
  }
}
