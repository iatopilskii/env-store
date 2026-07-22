import EnvStoreCore
import EnvStoreIPC
import Foundation

struct CachedGrant: Sendable {
  var policy: ExecutionGrant
  let command: RunCommandPayload
  let setName: String
  let environment: [String: String]
}

public final class GrantCache: @unchecked Sendable {
  private let lock = NSLock()
  private var grants: [UUID: CachedGrant] = [:]

  public init() {}

  func insert(
    command: RunCommandPayload,
    setID: UUID,
    displaySetName: String,
    environment: [String: String],
    expiresAt: Date,
    maximumUses: Int,
    now: Date = Date()
  ) throws -> GrantSummary {
    let request = commandRequest(for: command, setID: setID)
    let policy = try ExecutionGrant.validated(
      request: request,
      expiresAt: expiresAt,
      maximumUses: maximumUses,
      now: now
    )
    let cached = CachedGrant(
      policy: policy,
      command: command,
      setName: displaySetName,
      environment: environment
    )
    lock.withLock { grants[policy.id] = cached }
    return summary(for: cached)
  }

  func consume(
    matching command: RunCommandPayload,
    now: Date = Date()
  ) -> [String: String]? {
    lock.withLock {
      removeExpired(at: now)
      for id in grants.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
        guard var cached = grants[id], sameScope(cached.command, command) else {
          continue
        }
        let candidate = commandRequest(for: command, setID: cached.policy.request.setID)
        guard cached.policy.authorization(for: candidate, at: now) == .allowed else {
          continue
        }
        cached.policy.recordUse()
        let environment = cached.environment
        if cached.policy.consumedUses >= cached.policy.maximumUses {
          grants.removeValue(forKey: id)
        } else {
          grants[id] = cached
        }
        return environment
      }
      return nil
    }
  }

  public func summaries(now: Date = Date()) -> [GrantSummary] {
    lock.withLock {
      removeExpired(at: now)
      return grants.values
        .map(summary(for:))
        .sorted { $0.expiresAt < $1.expiresAt }
    }
  }

  public func revoke(id: UUID) -> Bool {
    lock.withLock { grants.removeValue(forKey: id) != nil }
  }

  public func revokeAll() {
    lock.withLock { grants.removeAll(keepingCapacity: false) }
  }

  private func removeExpired(at date: Date) {
    grants = grants.filter { _, cached in
      cached.policy.expiresAt > date
        && cached.policy.consumedUses < cached.policy.maximumUses
    }
  }

  private func commandRequest(for command: RunCommandPayload, setID: UUID) -> CommandRequest {
    CommandRequest(
      setID: setID,
      workingDirectory: command.workingDirectory,
      executablePath: command.executablePath,
      arguments: command.arguments,
      executableSearchPath: command.executableSearchPath
    )
  }

  private func sameScope(_ first: RunCommandPayload, _ second: RunCommandPayload) -> Bool {
    first.setName == second.setName
      && first.workingDirectory == second.workingDirectory
      && first.executablePath == second.executablePath
      && first.arguments == second.arguments
      && first.executableSearchPath == second.executableSearchPath
  }

  private func summary(for cached: CachedGrant) -> GrantSummary {
    GrantSummary(
      id: cached.policy.id,
      setName: cached.setName,
      executablePath: cached.command.executablePath,
      arguments: cached.command.arguments,
      workingDirectory: cached.command.workingDirectory,
      expiresAt: cached.policy.expiresAt,
      remainingUses: cached.policy.maximumUses - cached.policy.consumedUses
    )
  }
}
