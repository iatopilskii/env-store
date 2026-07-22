import Foundation

public struct SetupBundleResources: Equatable, Sendable {
  public let bundleURL: URL
  public let bundledCLIURL: URL
  public let agentSkillsRoot: URL
  public let launchAgentPlistURL: URL

  public init(bundleURL: URL) {
    self.bundleURL = bundleURL
    bundledCLIURL = bundleURL.appending(path: "Contents/SharedSupport/envstore")
    agentSkillsRoot = bundleURL.appending(
      path: "Contents/Resources/AgentSkills",
      directoryHint: .isDirectory
    )
    launchAgentPlistURL = bundleURL.appending(
      path: "Contents/Library/LaunchAgents/dev.envstore.broker.plist"
    )
  }

  public var isPackagedApplication: Bool {
    bundleURL.pathExtension == "app"
      && FileManager.default.fileExists(
        atPath: bundleURL.appending(path: "Contents/Info.plist").path
      )
      && FileManager.default.isExecutableFile(atPath: bundledCLIURL.path)
      && FileManager.default.fileExists(
        atPath: agentSkillsRoot.appending(path: "envstore/SKILL.md").path
      )
      && FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
  }

  public var isOnReadOnlyVolume: Bool {
    (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
  }
}
