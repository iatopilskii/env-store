import Foundation
import EnvStoreIPC
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

    private func sampleCommand(arguments: [String]) -> RunCommandPayload {
        RunCommandPayload(
            setName: "Development",
            workingDirectory: "/tmp/project",
            executablePath: "/usr/bin/true",
            arguments: arguments
        )
    }
}
