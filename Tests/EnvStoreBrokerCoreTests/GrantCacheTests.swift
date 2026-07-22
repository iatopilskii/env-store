import EnvStoreIPC
import Foundation
import Testing

@testable import EnvStoreBrokerCore

struct GrantCacheTests {
  private let now = Date(timeIntervalSince1970: 10_000)

  @Test
  func onlyConsumesExactCommandAndUseCount() throws {
    let cache = GrantCache()
    let command = sampleCommand(arguments: ["test"])
    _ = try cache.insert(
      command: command,
      setID: UUID(),
      displaySetName: "Development",
      environment: ["TOKEN": "value"],
      expiresAt: now.addingTimeInterval(60),
      maximumUses: 1,
      now: now
    )

    #expect(cache.consume(matching: sampleCommand(arguments: ["changed"]), now: now) == nil)
    let sameScopeNewExecution = sampleCommand(arguments: ["test"])
    #expect(sameScopeNewExecution.executionID != command.executionID)
    #expect(cache.consume(matching: sameScopeNewExecution, now: now) == ["TOKEN": "value"])
    #expect(cache.consume(matching: command, now: now) == nil)
  }

  @Test
  func executableSearchPathIsPartOfTheGrantScope() throws {
    let cache = GrantCache()
    let grantedCommand = sampleCommand(arguments: ["test"], searchPath: ["/toolchain/one"])
    _ = try cache.insert(
      command: grantedCommand,
      setID: UUID(),
      displaySetName: "Development",
      environment: ["TOKEN": "value"],
      expiresAt: now.addingTimeInterval(60),
      maximumUses: 1,
      now: now
    )

    let changedPath = sampleCommand(arguments: ["test"], searchPath: ["/toolchain/two"])
    #expect(cache.consume(matching: changedPath, now: now) == nil)
    #expect(cache.consume(matching: grantedCommand, now: now) == ["TOKEN": "value"])
  }

  @Test
  func removesExpiredGrantWithoutReturningSecrets() throws {
    let cache = GrantCache()
    _ = try cache.insert(
      command: sampleCommand(arguments: []),
      setID: UUID(),
      displaySetName: "Development",
      environment: ["TOKEN": "never-returned"],
      expiresAt: now.addingTimeInterval(1),
      maximumUses: 2,
      now: now
    )

    #expect(cache.summaries(now: now.addingTimeInterval(2)).isEmpty)
  }

  @Test
  func revokeAllClearsCachedEnvironment() throws {
    let cache = GrantCache()
    _ = try cache.insert(
      command: sampleCommand(arguments: []),
      setID: UUID(),
      displaySetName: "Development",
      environment: ["TOKEN": "cleared"],
      expiresAt: now.addingTimeInterval(60),
      maximumUses: 2,
      now: now
    )

    cache.revokeAll()

    #expect(cache.summaries(now: now).isEmpty)
  }

  private func sampleCommand(
    arguments: [String],
    searchPath: [String]? = nil
  ) -> RunCommandPayload {
    RunCommandPayload(
      setName: "Development",
      workingDirectory: "/tmp/project",
      executablePath: "/usr/bin/true",
      arguments: arguments,
      executableSearchPath: searchPath
    )
  }
}
