@preconcurrency import Foundation

public struct ProcessInvocation: Equatable, Sendable {
  public let executableURL: URL
  public let arguments: [String]
  public let environment: [String: String]
  public let currentDirectoryURL: URL?
  public let outputLimit: Int

  public init(
    executableURL: URL,
    arguments: [String],
    environment: [String: String],
    currentDirectoryURL: URL? = nil,
    outputLimit: Int = 64 * 1_024
  ) {
    self.executableURL = executableURL
    self.arguments = arguments
    self.environment = environment
    self.currentDirectoryURL = currentDirectoryURL
    self.outputLimit = outputLimit
  }
}

public struct ProcessResult: Equatable, Sendable {
  public let exitCode: Int32
  public let output: String

  public init(exitCode: Int32, output: String) {
    self.exitCode = exitCode
    self.output = output
  }
}

public protocol SetupProcessRunning: Sendable {
  func run(_ invocation: ProcessInvocation) throws -> ProcessResult
}

public struct FoundationProcessRunner: SetupProcessRunning {
  public init() {}

  public func run(_ invocation: ProcessInvocation) throws -> ProcessResult {
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = invocation.executableURL
    process.arguments = invocation.arguments
    process.environment = invocation.environment
    process.currentDirectoryURL = invocation.currentDirectoryURL
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    do {
      try process.run()
    } catch {
      throw EnvStoreSetupError.processLaunchFailed(error.localizedDescription)
    }

    let output = try readBoundedOutput(
      from: outputPipe.fileHandleForReading,
      limit: invocation.outputLimit
    )
    process.waitUntilExit()
    return ProcessResult(exitCode: process.terminationStatus, output: output)
  }

  private func readBoundedOutput(from handle: FileHandle, limit: Int) throws -> String {
    var retained = Data()
    while let chunk = try handle.read(upToCount: 8_192), !chunk.isEmpty {
      let available = max(0, limit - retained.count)
      if available > 0 {
        retained.append(chunk.prefix(available))
      }
    }
    return String(decoding: retained, as: UTF8.self)
  }
}
