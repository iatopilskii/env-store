import Foundation
import Testing
@testable import EnvStoreCore

struct CommandProfileTests {
    @Test
    func rejectsRelativePathsAndMissingStrictDigest() {
        let relativeExecutable = profile(projectRoot: "/tmp/project", executable: "bin/tool")
        let relativeRoot = profile(projectRoot: "project", executable: "/usr/bin/true")
        let strict = CommandProfile(
            name: "Strict",
            setID: UUID(),
            projectRoot: "/tmp/project",
            executablePath: "/usr/bin/true",
            arguments: [],
            trustMode: .strict
        )

        #expect(throws: CommandProfileValidationError.invalidExecutable) {
            try relativeExecutable.validate()
        }
        #expect(throws: CommandProfileValidationError.invalidProjectRoot) {
            try relativeRoot.validate()
        }
        #expect(throws: CommandProfileValidationError.strictDigestRequired) {
            try strict.validate()
        }
    }

    private func profile(projectRoot: String, executable: String) -> CommandProfile {
        CommandProfile(
            name: "Test",
            setID: UUID(),
            projectRoot: projectRoot,
            executablePath: executable,
            arguments: [],
            trustMode: .development
        )
    }
}
