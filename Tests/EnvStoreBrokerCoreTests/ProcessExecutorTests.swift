import EnvStoreIPC
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
}
