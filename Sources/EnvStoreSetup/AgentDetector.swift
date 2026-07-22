import Foundation

public struct AgentDetector: Sendable {
  struct Definition: Sendable {
    let skillRoot: String
    let homeEvidence: [String]
    let executableNames: [String]
    let applicationNames: [String]
  }

  private let definitions: [Definition]

  public init() {
    definitions = [
      Definition(
        skillRoot: ".codex/skills",
        homeEvidence: [".codex"],
        executableNames: ["codex"],
        applicationNames: ["Codex.app"]
      ),
      Definition(
        skillRoot: ".claude/skills",
        homeEvidence: [".claude"],
        executableNames: ["claude"],
        applicationNames: ["Claude.app"]
      ),
      Definition(
        skillRoot: ".cursor/skills",
        homeEvidence: [".cursor"],
        executableNames: ["cursor"],
        applicationNames: ["Cursor.app"]
      ),
      Definition(
        skillRoot: ".gemini/skills",
        homeEvidence: [".gemini"],
        executableNames: ["gemini"],
        applicationNames: []
      ),
      Definition(
        skillRoot: ".copilot/skills",
        homeEvidence: [".copilot"],
        executableNames: ["copilot"],
        applicationNames: ["GitHub Copilot for Xcode.app"]
      ),
      Definition(
        skillRoot: ".config/opencode/skills",
        homeEvidence: [".config/opencode"],
        executableNames: ["opencode"],
        applicationNames: ["OpenCode.app"]
      ),
      Definition(
        skillRoot: ".agents/skills",
        homeEvidence: [".agents", ".cline", ".dexto", ".kimi", ".loaf", ".warp", ".zed"],
        executableNames: ["cline", "dexto", "kimi", "loaf", "warp", "zed"],
        applicationNames: ["Warp.app", "Zed.app"]
      ),
    ]
  }

  public func detectedSkillRoots(
    homeDirectory: URL,
    pathEnvironment: String,
    applicationDirectories: [URL]
  ) -> [URL] {
    let pathDirectories = pathEnvironment.split(separator: ":", omittingEmptySubsequences: true)
      .map { URL(filePath: String($0), directoryHint: .isDirectory) }
    return definitions.compactMap { definition in
      guard
        isDetected(
          definition,
          homeDirectory: homeDirectory,
          pathDirectories: pathDirectories,
          applicationDirectories: applicationDirectories
        )
      else {
        return nil
      }
      return homeDirectory.appending(path: definition.skillRoot, directoryHint: .isDirectory)
    }
  }

  private func isDetected(
    _ definition: Definition,
    homeDirectory: URL,
    pathDirectories: [URL],
    applicationDirectories: [URL]
  ) -> Bool {
    if definition.homeEvidence.contains(where: {
      FileManager.default.fileExists(atPath: homeDirectory.appending(path: $0).path)
    }) {
      return true
    }
    if definition.executableNames.contains(where: { executable in
      pathDirectories.contains {
        FileManager.default.isExecutableFile(atPath: $0.appending(path: executable).path)
      }
    }) {
      return true
    }
    return definition.applicationNames.contains { application in
      applicationDirectories.contains {
        FileManager.default.fileExists(atPath: $0.appending(path: application).path)
      }
    }
  }
}
