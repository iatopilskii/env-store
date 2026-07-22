import Foundation

public struct CLIInstaller: Sendable {
  private let sourceURL: URL
  private let destinationURL: URL
  private let homeDirectory: URL
  private let version: String
  private let manifestStore: InstallationManifestStore
  private let lockURL: URL

  public init(
    sourceURL: URL,
    destinationURL: URL,
    homeDirectory: URL,
    version: String,
    manifestStore: InstallationManifestStore,
    lockURL: URL
  ) {
    self.sourceURL = sourceURL
    self.destinationURL = destinationURL
    self.homeDirectory = homeDirectory
    self.version = version
    self.manifestStore = manifestStore
    self.lockURL = lockURL
  }

  public func install(force: Bool = false) throws -> ComponentInstallationResult {
    try FileInstallation.ensureSafeDestination(destinationURL, below: homeDirectory)
    try FileInstallation.ensureSafeDestination(manifestStore.url, below: homeDirectory)
    try FileInstallation.ensureSafeDestination(lockURL, below: homeDirectory)
    return try InstallationFileLock.withLock(at: lockURL) {
      var manifest = try manifestStore.load()
      if !force,
        manifest.componentVersions[InstallationComponent.commandLineTool.rawValue] == version,
        FileManager.default.isExecutableFile(atPath: destinationURL.path)
      {
        return installedResult(detail: "Command-line tool is already installed.")
      }
      guard FileManager.default.isExecutableFile(atPath: sourceURL.path) else {
        throw EnvStoreSetupError.invalidBundledResource(sourceURL.path)
      }
      try FileInstallation.atomicallyInstallFile(from: sourceURL, to: destinationURL, mode: 0o755)
      manifest.componentVersions[InstallationComponent.commandLineTool.rawValue] = version
      try manifestStore.save(manifest)
      return installedResult(detail: "Command-line tool installed.")
    }
  }

  private func installedResult(detail: String) -> ComponentInstallationResult {
    ComponentInstallationResult(
      component: .commandLineTool,
      state: .installed,
      detail: detail,
      installedLocations: [destinationURL]
    )
  }
}
