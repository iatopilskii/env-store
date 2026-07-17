import Darwin
import EnvStoreIPC
import Foundation

public enum ProcessExecutionError: Error, Equatable, Sendable {
    case argumentListTooLarge
    case executableMustBeAbsolute
    case executableNotFound
    case spawnFailed(Int32)
    case waitFailed(Int32)
}

public struct ProcessIO: Sendable {
    public let standardInput: Int32
    public let standardOutput: Int32
    public let standardError: Int32

    public init(standardInput: Int32, standardOutput: Int32, standardError: Int32) {
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public static let inherited = ProcessIO(
        standardInput: STDIN_FILENO,
        standardOutput: STDOUT_FILENO,
        standardError: STDERR_FILENO
    )
}

public struct ProcessExecutor: Sendable {
    public init() {}

    public func run(
        command: RunCommandPayload,
        injectedEnvironment: [String: String],
        io: ProcessIO = .inherited
    ) throws -> Int32 {
        guard command.executablePath.hasPrefix("/") else {
            throw ProcessExecutionError.executableMustBeAbsolute
        }
        guard FileManager.default.isExecutableFile(atPath: command.executablePath) else {
            throw ProcessExecutionError.executableNotFound
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: command.workingDirectory,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw ProcessExecutionError.spawnFailed(ENOENT)
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in injectedEnvironment {
            environment[key] = value
        }
        let arguments = [command.executablePath] + command.arguments
        let environmentEntries = environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        try preflight(arguments: arguments, environment: environmentEntries)

        let argv = CStringVector(arguments)
        let envp = CStringVector(environmentEntries)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        try addDuplication(from: io.standardInput, to: STDIN_FILENO, actions: &actions)
        try addDuplication(from: io.standardOutput, to: STDOUT_FILENO, actions: &actions)
        try addDuplication(from: io.standardError, to: STDERR_FILENO, actions: &actions)
        let changeDirectoryStatus = command.workingDirectory.withCString { directory in
            posix_spawn_file_actions_addchdir_np(&actions, directory)
        }
        guard changeDirectoryStatus == 0 else {
            throw ProcessExecutionError.spawnFailed(changeDirectoryStatus)
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        guard posix_spawnattr_setflags(&attributes, flags) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            throw ProcessExecutionError.spawnFailed(EINVAL)
        }

        var processID: pid_t = 0
        let spawnStatus = argv.withUnsafeMutablePointer { argvPointer in
            envp.withUnsafeMutablePointer { environmentPointer in
                posix_spawn(
                    &processID,
                    command.executablePath,
                    &actions,
                    &attributes,
                    argvPointer,
                    environmentPointer
                )
            }
        }
        guard spawnStatus == 0 else {
            throw ProcessExecutionError.spawnFailed(spawnStatus)
        }

        var status: Int32 = 0
        while waitpid(processID, &status, 0) == -1 {
            guard errno == EINTR else {
                throw ProcessExecutionError.waitFailed(errno)
            }
        }
        return decodedExitStatus(status)
    }

    private func preflight(arguments: [String], environment: [String]) throws {
        let byteCount = (arguments + environment).reduce(0) { $0 + $1.utf8.count + 1 }
        let maximum = sysconf(_SC_ARG_MAX)
        guard maximum > 0, byteCount < maximum else {
            throw ProcessExecutionError.argumentListTooLarge
        }
    }

    private func addDuplication(
        from source: Int32,
        to destination: Int32,
        actions: inout posix_spawn_file_actions_t?
    ) throws {
        guard source != destination else { return }
        let result = posix_spawn_file_actions_adddup2(&actions, source, destination)
        guard result == 0 else {
            throw ProcessExecutionError.spawnFailed(result)
        }
    }

    private func decodedExitStatus(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        if signal == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + signal
    }
}

private final class CStringVector {
    private var pointers: [UnsafeMutablePointer<CChar>?]

    init(_ strings: [String]) {
        pointers = strings.map { string in
            string.withCString { strdup($0) }
        }
        pointers.append(nil)
    }

    deinit {
        for pointer in pointers where pointer != nil {
            free(pointer)
        }
    }

    func withUnsafeMutablePointer<Result>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) rethrows -> Result {
        try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }
}
