import Foundation

public struct AgentSkillInstaller: Sendable {
  public static let skillsPackageVersion = "1.5.17"

  private let agentSkillsRoot: URL
  private let homeDirectory: URL
  private let temporaryDirectory: URL
  private let applicationDirectories: [URL]
  private let pathEnvironment: String
  private let version: String
  private let processRunner: any SetupProcessRunning
  private let manifestStore: InstallationManifestStore
  private let lockURL: URL
  private let npxLocator: NpxLocator
  private let agentDetector = AgentDetector()

  public init(
    agentSkillsRoot: URL,
    homeDirectory: URL,
    temporaryDirectory: URL,
    applicationDirectories: [URL],
    pathEnvironment: String,
    version: String,
    processRunner: any SetupProcessRunning = FoundationProcessRunner(),
    manifestStore: InstallationManifestStore,
    lockURL: URL,
    npxLocator: NpxLocator = NpxLocator()
  ) {
    self.agentSkillsRoot = agentSkillsRoot
    self.homeDirectory = homeDirectory
    self.temporaryDirectory = temporaryDirectory
    self.applicationDirectories = applicationDirectories
    self.pathEnvironment = pathEnvironment
    self.version = version
    self.processRunner = processRunner
    self.manifestStore = manifestStore
    self.lockURL = lockURL
    self.npxLocator = npxLocator
  }

  public func install(force: Bool = false) throws -> ComponentInstallationResult {
    try FileInstallation.ensureSafeDestination(manifestStore.url, below: homeDirectory)
    try FileInstallation.ensureSafeDestination(lockURL, below: homeDirectory)
    return try InstallationFileLock.withLock(at: lockURL) {
      let sourceSkill = agentSkillsRoot.appending(path: "envstore", directoryHint: .isDirectory)
      try FileInstallation.validateSkill(at: sourceSkill)
      var manifest = try manifestStore.load()
      if let npx = npxLocator.locate(
        homeDirectory: homeDirectory,
        pathEnvironment: pathEnvironment
      ) {
        return try installWithNpx(npx, manifest: &manifest, force: force)
      }
      return try installNatively(sourceSkill: sourceSkill, manifest: &manifest, force: force)
    }
  }

  private func installWithNpx(
    _ npx: URL,
    manifest: inout InstallationManifest,
    force: Bool
  ) throws -> ComponentInstallationResult {
    if !force,
      manifest.componentVersions[InstallationComponent.agentSkill.rawValue] == version,
      manifest.agentSkillMethod == .npx
    {
      return ComponentInstallationResult(
        component: .agentSkill,
        state: .installed,
        detail: "Agent skill is already installed.",
        method: .npx
      )
    }

    let invocation = npxInvocation(executableURL: npx)
    let result: ProcessResult
    do {
      result = try processRunner.run(invocation)
    } catch {
      return ComponentInstallationResult(
        component: .agentSkill,
        state: .warning,
        detail: "Agent skill was not installed because the skills CLI could not start.",
        method: .npx,
        recoveryCommand: manualCommand(npxURL: npx)
      )
    }
    guard result.exitCode == 0 else {
      return ComponentInstallationResult(
        component: .agentSkill,
        state: .warning,
        detail: "Agent skill was not installed. skills CLI exited with status \(result.exitCode).",
        method: .npx,
        recoveryCommand: manualCommand(npxURL: npx)
      )
    }

    manifest.componentVersions[InstallationComponent.agentSkill.rawValue] = version
    manifest.agentSkillMethod = .npx
    try manifestStore.save(manifest)
    return ComponentInstallationResult(
      component: .agentSkill,
      state: .installed,
      detail: "Agent skill installed for detected agents.",
      method: .npx
    )
  }

  private func installNatively(
    sourceSkill: URL,
    manifest: inout InstallationManifest,
    force: Bool
  ) throws -> ComponentInstallationResult {
    var roots = agentDetector.detectedSkillRoots(
      homeDirectory: homeDirectory,
      pathEnvironment: pathEnvironment,
      applicationDirectories: applicationDirectories
    )
    if roots.isEmpty {
      roots = [homeDirectory.appending(path: ".agents/skills", directoryHint: .isDirectory)]
    }

    var installedLocations: [URL] = []
    var warnings: [String] = []
    for root in roots {
      do {
        installedLocations.append(
          try installNativeCopy(
            sourceSkill: sourceSkill,
            skillRoot: root,
            manifest: &manifest,
            force: force
          )
        )
      } catch let error as EnvStoreSetupError {
        warnings.append(error.localizedDescription)
      } catch {
        warnings.append("Could not install the agent skill at \(root.path).")
      }
    }

    manifest.agentSkillMethod = .native
    if warnings.isEmpty {
      manifest.componentVersions[InstallationComponent.agentSkill.rawValue] = version
    } else {
      manifest.componentVersions.removeValue(forKey: InstallationComponent.agentSkill.rawValue)
    }
    try manifestStore.save(manifest)

    if !warnings.isEmpty {
      return ComponentInstallationResult(
        component: .agentSkill,
        state: .warning,
        detail: warnings.joined(separator: " "),
        method: .native,
        installedLocations: installedLocations
      )
    }
    return ComponentInstallationResult(
      component: .agentSkill,
      state: .installed,
      detail: "Agent skill installed with the native fallback.",
      method: .native,
      installedLocations: installedLocations
    )
  }

  private func installNativeCopy(
    sourceSkill: URL,
    skillRoot: URL,
    manifest: inout InstallationManifest,
    force: Bool
  ) throws -> URL {
    let destination = skillRoot.appending(path: "envstore", directoryHint: .isDirectory)
    try FileInstallation.ensureSafeDestination(destination, below: homeDirectory)

    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destination.path) {
      guard
        !FileInstallation.isSymbolicLink(destination),
        manifest.managedSkillDestinations[destination.path] != nil,
        hasOwnershipMarker(at: destination)
      else {
        throw EnvStoreSetupError.unownedDestination(destination.path)
      }
      if !force,
        manifest.managedSkillDestinations[destination.path]?.version == version,
        fileManager.fileExists(atPath: destination.appending(path: "SKILL.md").path)
      {
        return destination
      }
    }

    try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)
    let staging = skillRoot.appending(
      path: ".envstore.staging-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: staging) }
    try fileManager.copyItem(at: sourceSkill, to: staging)
    try writeOwnershipMarker(at: staging)
    try FileInstallation.validateSkill(at: staging)
    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
    } else {
      try fileManager.moveItem(at: staging, to: destination)
    }
    manifest.managedSkillDestinations[destination.path] = ManagedSkillInstallation(version: version)
    return destination
  }

  private func npxInvocation(executableURL: URL) -> ProcessInvocation {
    ProcessInvocation(
      executableURL: executableURL,
      arguments: [
        "--yes", "skills@\(Self.skillsPackageVersion)", "add", agentSkillsRoot.path,
        "--skill", "envstore", "--global", "--copy", "--yes",
      ],
      environment: [
        "HOME": homeDirectory.path,
        "PATH": npxLocator.controlledPath(homeDirectory: homeDirectory, npxURL: executableURL),
        "TMPDIR": temporaryDirectory.path,
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8",
        "DISABLE_TELEMETRY": "1",
        "DO_NOT_TRACK": "1",
        "NO_COLOR": "1",
      ],
      currentDirectoryURL: agentSkillsRoot
    )
  }

  private func manualCommand(npxURL: URL) -> String {
    let arguments = npxInvocation(executableURL: npxURL).arguments.map(shellQuote).joined(
      separator: " ")
    return "DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 \(shellQuote(npxURL.path)) \(arguments)"
  }

  private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }

  private func hasOwnershipMarker(at destination: URL) -> Bool {
    guard
      let data = try? Data(contentsOf: destination.appending(path: ".envstore-managed.json")),
      let marker = try? JSONDecoder().decode(OwnershipMarker.self, from: data)
    else {
      return false
    }
    return marker.owner == OwnershipMarker.expectedOwner
  }

  private func writeOwnershipMarker(at destination: URL) throws {
    let data = try JSONEncoder().encode(OwnershipMarker(version: version))
    try data.write(to: destination.appending(path: ".envstore-managed.json"), options: .atomic)
  }
}

private struct OwnershipMarker: Codable {
  static let expectedOwner = "dev.envstore.app"

  let owner: String
  let version: String

  init(version: String) {
    owner = Self.expectedOwner
    self.version = version
  }
}
