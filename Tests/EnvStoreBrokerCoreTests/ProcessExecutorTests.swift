import Darwin
import EnvStoreIPC
import Foundation
import Testing

@testable import EnvStoreBrokerCore

struct ProcessExecutorTests {
  @Test
  func injectsEnvironmentIntoExactChildProcess() throws {
    let command = RunCommandPayload(
      setName: "Test",
      workingDirectory: "/tmp",
      executablePath: "/bin/sh",
      arguments: ["-c", "test \"$ENVSTORE_TEST_TOKEN\" = expected"]
    )

    let exitCode = try ProcessExecutor().run(
      command: command,
      injectedEnvironment: ["ENVSTORE_TEST_TOKEN": "expected"]
    )

    #expect(exitCode == 0)
  }

  @Test
  func preservesChildExitCode() throws {
    let command = RunCommandPayload(
      setName: "Test",
      workingDirectory: "/tmp",
      executablePath: "/bin/sh",
      arguments: ["-c", "exit 23"]
    )

    #expect(try ProcessExecutor().run(command: command, injectedEnvironment: [:]) == 23)
  }

  @Test
  func suppliesTerminalExecutableSearchPathToTheChild() throws {
    let command = RunCommandPayload(
      setName: "Test",
      workingDirectory: "/tmp",
      executablePath: "/bin/sh",
      arguments: ["-c", "test \"$PATH\" = /custom/bin:/usr/bin"],
      executableSearchPath: ["/custom/bin", "/usr/bin"]
    )

    #expect(try ProcessExecutor().run(command: command, injectedEnvironment: [:]) == 0)
  }

  @Test
  func duplicatedIOOutlivesTheOriginalFileHandle() throws {
    let outputPipe = Pipe()
    var ioLease: ProcessIOLease? = try ProcessIOLease(
      duplicating: ProcessIO(
        standardInput: STDIN_FILENO,
        standardOutput: outputPipe.fileHandleForWriting.fileDescriptor,
        standardError: STDERR_FILENO
      )
    )
    try outputPipe.fileHandleForWriting.close()

    let command = RunCommandPayload(
      setName: "Test",
      workingDirectory: "/tmp",
      executablePath: "/bin/echo",
      arguments: ["leased output"]
    )
    let exitCode = try ProcessExecutor().run(
      command: command,
      injectedEnvironment: [:],
      io: ioLease!.io
    )
    ioLease = nil

    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    #expect(exitCode == 0)
    #expect(String(decoding: output, as: UTF8.self) == "leased output\n")
  }

  @Test
  func rejectsRelativeExecutable() {
    let command = RunCommandPayload(
      setName: "Test",
      workingDirectory: "/tmp",
      executablePath: "bin/tool",
      arguments: []
    )

    #expect(throws: ProcessExecutionError.executableMustBeAbsolute) {
      try ProcessExecutor().run(command: command, injectedEnvironment: [:])
    }
  }

  @Test
  func terminatesChildProcessGroupWhenSignalIsForwarded() throws {
    let registry = ExecutionRegistry()
    let executionID = UUID()
    let command = RunCommandPayload(
      executionID: executionID,
      setName: "Test",
      workingDirectory: "/tmp",
      executablePath: "/bin/sleep",
      arguments: ["10"]
    )

    let exitCode = try ProcessExecutor().run(
      command: command,
      injectedEnvironment: [:]
    ) { processID in
      registry.register(executionID: executionID, processID: processID)
      usleep(50_000)
      _ = registry.forward(signal: SIGTERM, to: executionID)
    }

    #expect(exitCode == 128 + SIGTERM)
  }
}
