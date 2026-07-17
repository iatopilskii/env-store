import EnvStoreCore
import EnvStoreIPC
import EnvStoreStorage
@preconcurrency import Foundation

public final class BrokerService: Sendable {
    private let store: EncryptedVaultStore?
    private let vaultAvailable: Bool
    private let grants: GrantCache
    private let executor: ProcessExecutor

    public init(
        store: EncryptedVaultStore?,
        vaultAvailable: Bool,
        grants: GrantCache = GrantCache(),
        executor: ProcessExecutor = ProcessExecutor()
    ) {
        self.store = store
        self.vaultAvailable = vaultAvailable
        self.grants = grants
        self.executor = executor
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
                    message: vaultAvailable ? "Broker and vault are available" : "Broker is available; vault is not initialized"
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
                let set = try await loadSet(named: payload.command.setName)
                let environment = Dictionary(
                    uniqueKeysWithValues: set.variables.map { ($0.key, $0.value) }
                )
                let summary = try grants.insert(
                    command: payload.command,
                    setID: set.id,
                    environment: environment,
                    expiresAt: payload.expiresAt,
                    maximumUses: payload.maximumUses
                )
                return BrokerResponse(success: true, grants: [summary])
            case .run:
                guard let command = request.run else {
                    return failure(.invalidRequest, "Run payload is required")
                }
                let environment: [String: String]
                if let granted = grants.consume(matching: command) {
                    environment = granted
                } else {
                    let set = try await loadSet(named: command.setName)
                    environment = Dictionary(
                        uniqueKeysWithValues: set.variables.map { ($0.key, $0.value) }
                    )
                }
                let exitCode = try executor.run(
                    command: command,
                    injectedEnvironment: environment,
                    io: io
                )
                return BrokerResponse(success: true, exitCode: exitCode)
            }
        } catch EnvStoreStorageError.setNotFound(_) {
            return failure(.profileNotFound, "Environment set was not found")
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

    private func loadSet(named name: String) async throws -> EnvironmentSet {
        guard let store else {
            throw EnvStoreStorageError.vaultNotFound
        }
        let sets = try await store.listSets()
        guard let set = sets.first(where: { $0.name == name }) else {
            throw EnvStoreStorageError.setNotFound(UUID())
        }
        return set
    }

    private func failure(_ code: EnvStoreErrorCode, _ message: String) -> BrokerResponse {
        BrokerResponse(success: false, errorCode: code, message: message)
    }
}
