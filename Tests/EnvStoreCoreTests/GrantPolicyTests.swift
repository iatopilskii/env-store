import Foundation
import Testing

@testable import EnvStoreCore

struct GrantPolicyTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test
  func matchingGrantCanBeConsumedUntilUseLimit() {
    let request = commandRequest()
    var grant = ExecutionGrant(
      request: request,
      expiresAt: now.addingTimeInterval(600),
      maximumUses: 2
    )

    #expect(grant.authorization(for: request, at: now) == .allowed)
    grant.recordUse()
    #expect(grant.authorization(for: request, at: now) == .allowed)
    grant.recordUse()
    #expect(grant.authorization(for: request, at: now) == .denied(.grantExhausted))
  }

  @Test
  func expiredGrantIsDenied() {
    let request = commandRequest()
    let grant = ExecutionGrant(
      request: request,
      expiresAt: now.addingTimeInterval(-1),
      maximumUses: 1
    )

    #expect(grant.authorization(for: request, at: now) == .denied(.grantExpired))
  }

  @Test
  func changedArgumentsDirectoryExecutableSearchPathOrSetAreDenied() {
    let original = commandRequest()
    let grant = ExecutionGrant(
      request: original,
      expiresAt: now.addingTimeInterval(60),
      maximumUses: 1
    )

    let changedArguments = original.replacing(arguments: ["test", "--watch"])
    let changedDirectory = original.replacing(workingDirectory: "/workspace/other")
    let changedExecutable = original.replacing(executablePath: "/usr/bin/env")
    let changedSearchPath = original.replacing(executableSearchPath: ["/other/toolchain/bin"])
    let changedSet = original.replacing(setID: UUID())

    #expect(grant.authorization(for: changedArguments, at: now) == .denied(.grantScopeMismatch))
    #expect(grant.authorization(for: changedDirectory, at: now) == .denied(.grantScopeMismatch))
    #expect(grant.authorization(for: changedExecutable, at: now) == .denied(.grantScopeMismatch))
    #expect(grant.authorization(for: changedSearchPath, at: now) == .denied(.grantScopeMismatch))
    #expect(grant.authorization(for: changedSet, at: now) == .denied(.grantScopeMismatch))
  }

  @Test
  func invalidGrantLimitsAreRejected() {
    #expect(throws: GrantValidationError.invalidMaximumUses) {
      try ExecutionGrant.validated(
        request: commandRequest(),
        expiresAt: now.addingTimeInterval(60),
        maximumUses: 0,
        now: now
      )
    }

    #expect(throws: GrantValidationError.invalidExpiration) {
      try ExecutionGrant.validated(
        request: commandRequest(),
        expiresAt: now,
        maximumUses: 1,
        now: now
      )
    }
  }

  private func commandRequest() -> CommandRequest {
    CommandRequest(
      setID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      workingDirectory: "/workspace/api",
      executablePath: "/usr/bin/npm",
      arguments: ["test"],
      executableSearchPath: ["/toolchain/bin", "/usr/bin"]
    )
  }
}

extension CommandRequest {
  fileprivate func replacing(
    setID: UUID? = nil,
    workingDirectory: String? = nil,
    executablePath: String? = nil,
    arguments: [String]? = nil,
    executableSearchPath: [String]? = nil
  ) -> CommandRequest {
    CommandRequest(
      setID: setID ?? self.setID,
      workingDirectory: workingDirectory ?? self.workingDirectory,
      executablePath: executablePath ?? self.executablePath,
      arguments: arguments ?? self.arguments,
      executableSearchPath: executableSearchPath ?? self.executableSearchPath
    )
  }
}
