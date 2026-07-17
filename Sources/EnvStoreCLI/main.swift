import Darwin
import EnvStoreCore
import EnvStoreIPC
@preconcurrency import Foundation

private enum CLIError: Error, CustomStringConvertible {
  case invalidArguments(String)

  var description: String {
    switch self {
    case .invalidArguments(let message): message
    }
  }
}

enum EnvStoreCLI {
  static func main() {
    do {
      let exitCode = try execute(arguments: Array(CommandLine.arguments.dropFirst()))
      Darwin.exit(exitCode)
    } catch let error as CLIError {
      writeError("envstore: \(error.description)\n\n\(usage)\n")
      Darwin.exit(64)
    } catch let error as BrokerTransportError {
      writeError("envstore: broker unavailable (\(error))\n")
      Darwin.exit(69)
    } catch {
      writeError("envstore: \(error)\n")
      Darwin.exit(70)
    }
  }

  private static func execute(arguments: [String]) throws -> Int32 {
    guard let command = arguments.first else {
      throw CLIError.invalidArguments("a command is required")
    }
    if command == "--version" || command == "version" {
      print(EnvStoreCore.version)
      return 0
    }

    let json = arguments.contains("--json")
    let transport = XPCBrokerTransport()
    let response: BrokerResponse
    switch command {
    case "doctor":
      response = try transport.send(BrokerRequest(operation: .doctor))
    case "context":
      response = try transport.send(BrokerRequest(operation: .context))
    case "run":
      let payload = try parseRun(Array(arguments.dropFirst()))
      writeError(
        "EnvStore requests access to '\(payload.setName ?? "linked project set")' for \(displayedCommand(payload)).\n"
      )
      response = try withSignalForwarding(executionID: payload.executionID) {
        try transport.send(BrokerRequest(operation: .run, run: payload))
      }
    case "profile":
      guard arguments.count == 3, arguments[1] == "run" else {
        throw CLIError.invalidArguments("use profile run NAME")
      }
      let payload = ProfileRunPayload(
        name: arguments[2],
        workingDirectory: FileManager.default.currentDirectoryPath
      )
      writeError("EnvStore requests profile '\(payload.name)'.\n")
      response = try withSignalForwarding(executionID: payload.executionID) {
        try transport.send(BrokerRequest(operation: .profileRun, profileRun: payload))
      }
    case "grant":
      response = try executeGrant(Array(arguments.dropFirst()), transport: transport)
    default:
      throw CLIError.invalidArguments("unknown command '\(command)'")
    }

    if json {
      FileHandle.standardOutput.write(try BrokerCodec.encode(response))
      FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
      printHuman(response, operation: command)
    }
    guard response.success else {
      return 77
    }
    return response.exitCode ?? 0
  }

  private static func executeGrant(
    _ arguments: [String],
    transport: XPCBrokerTransport
  ) throws -> BrokerResponse {
    guard let action = arguments.first else {
      throw CLIError.invalidArguments("grant requires request, list, or revoke")
    }
    switch action {
    case "list":
      return try transport.send(BrokerRequest(operation: .grantList))
    case "revoke":
      guard arguments.count == 2, let id = UUID(uuidString: arguments[1]) else {
        throw CLIError.invalidArguments("grant revoke requires a UUID")
      }
      return try transport.send(BrokerRequest(operation: .grantRevoke, identifier: id))
    case "request":
      let ttl = try option("--ttl", in: arguments).map(parseDuration) ?? 300
      let uses = try option("--uses", in: arguments).map(parsePositiveInteger) ?? 1
      if let profileName = try option("--profile", in: arguments) {
        let profile = ProfileRunPayload(
          name: profileName,
          workingDirectory: FileManager.default.currentDirectoryPath
        )
        writeError(
          "EnvStore requests profile grant '\(profileName)'; ttl \(Int(ttl))s; uses \(uses).\n"
        )
        return try transport.send(
          BrokerRequest(
            operation: .profileGrantRequest,
            profileGrant: ProfileGrantPayload(
              profile: profile,
              expiresAt: Date().addingTimeInterval(ttl),
              maximumUses: uses
            )
          )
        )
      }
      let command = try parseRun(Array(arguments.dropFirst()))
      let payload = GrantRequestPayload(
        command: command,
        expiresAt: Date().addingTimeInterval(ttl),
        maximumUses: uses
      )
      writeError(
        "EnvStore requests a grant for '\(command.setName ?? "linked project set")': \(displayedCommand(command)); ttl \(Int(ttl))s; uses \(uses).\n"
      )
      return try transport.send(BrokerRequest(operation: .grantRequest, grant: payload))
    default:
      throw CLIError.invalidArguments("unknown grant command '\(action)'")
    }
  }

  private static func parseRun(_ arguments: [String]) throws -> RunCommandPayload {
    let setName = try option("--set", in: arguments)
    guard let separator = arguments.firstIndex(of: "--"), separator + 1 < arguments.count else {
      throw CLIError.invalidArguments("use -- before the executable")
    }
    let rawExecutable = arguments[separator + 1]
    let executable = try resolveExecutable(rawExecutable)
    let commandArguments = Array(arguments.dropFirst(separator + 2))
    return RunCommandPayload(
      setName: setName,
      workingDirectory: FileManager.default.currentDirectoryPath,
      executablePath: executable,
      arguments: commandArguments
    )
  }

  private static func option(_ name: String, in arguments: [String]) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count, arguments[index + 1] != "--" else {
      throw CLIError.invalidArguments("\(name) requires a value")
    }
    return arguments[index + 1]
  }

  private static func parseDuration(_ value: String) throws -> TimeInterval {
    guard let suffix = value.last else {
      throw CLIError.invalidArguments("invalid duration")
    }
    let multiplier: Double
    let number: String
    switch suffix {
    case "s":
      multiplier = 1
      number = String(value.dropLast())
    case "m":
      multiplier = 60
      number = String(value.dropLast())
    case "h":
      multiplier = 3_600
      number = String(value.dropLast())
    default:
      multiplier = 1
      number = value
    }
    guard let amount = Double(number), amount > 0, amount * multiplier <= 86_400 else {
      throw CLIError.invalidArguments("duration must be between 1s and 24h")
    }
    return amount * multiplier
  }

  private static func parsePositiveInteger(_ value: String) throws -> Int {
    guard let number = Int(value), number > 0, number <= 1_000 else {
      throw CLIError.invalidArguments("uses must be between 1 and 1000")
    }
    return number
  }

  private static func resolveExecutable(_ executable: String) throws -> String {
    if executable.hasPrefix("/") {
      return executable.standardizedAbsolutePath
    }
    let searchPaths =
      ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":")
      .map(String.init) ?? ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    for directory in searchPaths {
      let candidate = URL(fileURLWithPath: directory)
        .appending(path: executable)
        .standardizedFileURL.path
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    throw CLIError.invalidArguments("executable '\(executable)' was not found")
  }

  private static func displayedCommand(_ payload: RunCommandPayload) -> String {
    ([payload.executablePath] + payload.arguments)
      .map { $0.contains(" ") ? "“\($0)”" : $0 }
      .joined(separator: " ")
  }

  private static func printHuman(_ response: BrokerResponse, operation: String) {
    if let message = response.message {
      let target = response.success ? FileHandle.standardOutput : FileHandle.standardError
      target.write(Data("\(message)\n".utf8))
    }
    if let context = response.context {
      print("vault: \(context.vaultAvailable ? "available" : "not initialized")")
      print("active grants: \(context.activeGrantCount)")
      if !context.setNames.isEmpty {
        print("granted sets: \(context.setNames.joined(separator: ", "))")
      }
    }
    if let grants = response.grants {
      for grant in grants {
        print(
          "\(grant.id.uuidString)  \(grant.setName)  uses=\(grant.remainingUses)  expires=\(grant.expiresAt.formatted(.iso8601))"
        )
      }
      if grants.isEmpty, operation == "grant" {
        print("No active grants")
      }
    }
    if !response.success, response.message == nil {
      writeError("envstore: \(response.errorCode?.rawValue ?? "unknown_error")\n")
    }
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }

  private static func withSignalForwarding<Result>(
    executionID: UUID,
    operation: () throws -> Result
  ) rethrows -> Result {
    let forwarder = SignalForwarder(executionID: executionID)
    return try withExtendedLifetime(forwarder, operation)
  }

  private static let usage = """
    Usage:
      envstore doctor [--json]
      envstore context [--json]
      envstore run --set NAME -- EXECUTABLE [ARG...]
      envstore run -- EXECUTABLE [ARG...]  # nearest linked project
      envstore profile run NAME
      envstore grant request --profile NAME [--ttl 5m] [--uses 1] [--wait]
      envstore grant request [--set NAME] [--ttl 5m] [--uses 1] -- EXECUTABLE [ARG...]
      envstore grant list [--json]
      envstore grant revoke UUID
    """
}

private final class SignalForwarder: @unchecked Sendable {
  private let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGWINCH]
  private var sources: [DispatchSourceSignal] = []

  init(executionID: UUID) {
    for signalNumber in signals {
      Darwin.signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(
        signal: signalNumber,
        queue: DispatchQueue.global(qos: .userInitiated)
      )
      source.setEventHandler {
        let request = BrokerRequest(
          operation: .signal,
          processSignal: ProcessSignalPayload(
            executionID: executionID,
            signal: signalNumber
          )
        )
        _ = try? XPCBrokerTransport(timeout: 5).send(request)
      }
      source.resume()
      sources.append(source)
    }
  }

  deinit {
    for source in sources {
      source.cancel()
    }
    for signalNumber in signals {
      Darwin.signal(signalNumber, SIG_DFL)
    }
  }
}

EnvStoreCLI.main()
