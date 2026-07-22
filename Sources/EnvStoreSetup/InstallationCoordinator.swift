import Foundation

public struct LocalSetupConfiguration: Sendable {
  public let bundledCLIURL: URL
  public let agentSkillsRoot: URL
  public let homeDirectory: URL
  public let applicationSupportDirectory: URL
  public let temporaryDirectory: URL
  public let applicationDirectories: [URL]
  public let pathEnvironment: String
  public let version: String

  public init(
    bundledCLIURL: URL,
    agentSkillsRoot: URL,
    homeDirectory: URL,
    applicationSupportDirectory: URL,
    temporaryDirectory: URL,
    applicationDirectories: [URL],
    pathEnvironment: String,
    version: String
  ) {
    self.bundledCLIURL = bundledCLIURL
    self.agentSkillsRoot = agentSkillsRoot
    self.homeDirectory = homeDirectory
    self.applicationSupportDirectory = applicationSupportDirectory
    self.temporaryDirectory = temporaryDirectory
    self.applicationDirectories = applicationDirectories
    self.pathEnvironment = pathEnvironment
    self.version = version
  }

  public var manifestStore: InstallationManifestStore {
    InstallationManifestStore(url: applicationSupportDirectory.appending(path: "installation.json"))
  }

  public var lockURL: URL {
    applicationSupportDirectory.appending(path: "setup.lock")
  }
}

public struct LocalInstallationEngine: Sendable {
  private let configuration: LocalSetupConfiguration
  private let processRunner: any SetupProcessRunning

  public init(
    configuration: LocalSetupConfiguration,
    processRunner: any SetupProcessRunning = FoundationProcessRunner()
  ) {
    self.configuration = configuration
    self.processRunner = processRunner
  }

  public func installCommandLineTool(force: Bool = false) throws -> ComponentInstallationResult {
    try CLIInstaller(
      sourceURL: configuration.bundledCLIURL,
      destinationURL: configuration.homeDirectory.appending(path: ".local/bin/envstore"),
      homeDirectory: configuration.homeDirectory,
      version: configuration.version,
      manifestStore: configuration.manifestStore,
      lockURL: configuration.lockURL
    ).install(force: force)
  }

  public func installAgentSkill(force: Bool = false) throws -> ComponentInstallationResult {
    try AgentSkillInstaller(
      agentSkillsRoot: configuration.agentSkillsRoot,
      homeDirectory: configuration.homeDirectory,
      temporaryDirectory: configuration.temporaryDirectory,
      applicationDirectories: configuration.applicationDirectories,
      pathEnvironment: configuration.pathEnvironment,
      version: configuration.version,
      processRunner: processRunner,
      manifestStore: configuration.manifestStore,
      lockURL: configuration.lockURL
    ).install(force: force)
  }

  public func commandLineToolStatus() -> ComponentInstallationResult {
    let destination = configuration.homeDirectory.appending(path: ".local/bin/envstore")
    guard
      let manifest = try? configuration.manifestStore.load(),
      manifest.componentVersions[InstallationComponent.commandLineTool.rawValue]
        == configuration.version,
      FileManager.default.isExecutableFile(atPath: destination.path)
    else {
      return ComponentInstallationResult(
        component: .commandLineTool,
        state: .waiting,
        detail: "Command-line tool is not installed."
      )
    }
    return ComponentInstallationResult(
      component: .commandLineTool,
      state: .installed,
      detail: "Command-line tool is installed.",
      installedLocations: [destination]
    )
  }

  public func agentSkillStatus() -> ComponentInstallationResult {
    guard
      let manifest = try? configuration.manifestStore.load(),
      manifest.componentVersions[InstallationComponent.agentSkill.rawValue] == configuration.version
    else {
      return ComponentInstallationResult(
        component: .agentSkill,
        state: .waiting,
        detail: "Agent skill is not installed."
      )
    }
    let locations = verifiedSkillLocations(from: manifest)
    guard !locations.isEmpty else {
      return ComponentInstallationResult(
        component: .agentSkill,
        state: .waiting,
        detail: "The recorded agent skill installation could not be verified.",
        method: manifest.agentSkillMethod
      )
    }
    return ComponentInstallationResult(
      component: .agentSkill,
      state: .installed,
      detail: "Agent skill is installed.",
      method: manifest.agentSkillMethod,
      installedLocations: locations
    )
  }

  private func verifiedSkillLocations(from manifest: InstallationManifest) -> [URL] {
    let candidates: [URL]
    if manifest.agentSkillMethod == .native {
      candidates = manifest.managedSkillDestinations.keys.map {
        URL(filePath: $0, directoryHint: .isDirectory)
      }
    } else {
      let detectedRoots = AgentDetector().detectedSkillRoots(
        homeDirectory: configuration.homeDirectory,
        pathEnvironment: configuration.pathEnvironment,
        applicationDirectories: configuration.applicationDirectories
      )
      candidates =
        detectedRoots.map {
          $0.appending(path: "envstore", directoryHint: .isDirectory)
        } + [
          configuration.homeDirectory.appending(
            path: ".agents/skills/envstore",
            directoryHint: .isDirectory
          )
        ]
    }
    let verified = candidates.filter {
      FileManager.default.fileExists(atPath: $0.appending(path: "SKILL.md").path)
        && !FileInstallation.isSymbolicLink($0)
        && (manifest.agentSkillMethod != .native
          || FileManager.default.fileExists(
            atPath: $0.appending(path: ".envstore-managed.json").path
          ))
    }.sorted { $0.path < $1.path }
    if manifest.agentSkillMethod == .native, verified.count != candidates.count {
      return []
    }
    return verified
  }
}

public struct InstallationReport: Equatable, Sendable {
  public let commandLineTool: ComponentInstallationResult
  public let backgroundBroker: ComponentInstallationResult
  public let agentSkill: ComponentInstallationResult

  public var mandatoryComponentsReady: Bool {
    commandLineTool.state == .installed && backgroundBroker.state == .installed
  }
}

@MainActor
public final class InstallationCoordinator {
  private let localEngine: LocalInstallationEngine
  private let brokerRegistrar: any BrokerRegistering

  public init(
    localEngine: LocalInstallationEngine,
    brokerRegistrar: any BrokerRegistering
  ) {
    self.localEngine = localEngine
    self.brokerRegistrar = brokerRegistrar
  }

  public func inspect() -> InstallationReport {
    InstallationReport(
      commandLineTool: localEngine.commandLineToolStatus(),
      backgroundBroker: brokerResult(for: brokerRegistrar.status),
      agentSkill: localEngine.agentSkillStatus()
    )
  }

  public func install(
    force: Bool = false,
    progress: @MainActor @Sendable (ComponentInstallationResult) -> Void
  ) async -> InstallationReport {
    progress(installingResult(for: .commandLineTool))
    let engine = localEngine
    let commandLineTool = await Task.detached(priority: .userInitiated) {
      do {
        return try engine.installCommandLineTool(force: force)
      } catch {
        return Self.warningResult(for: .commandLineTool, error: error)
      }
    }.value
    progress(commandLineTool)

    progress(installingResult(for: .backgroundBroker))
    let backgroundBroker = registerBrokerIfNeeded()
    progress(backgroundBroker)

    progress(installingResult(for: .agentSkill))
    let agentSkill = await Task.detached(priority: .utility) {
      do {
        return try engine.installAgentSkill(force: force)
      } catch {
        return Self.warningResult(for: .agentSkill, error: error)
      }
    }.value
    progress(agentSkill)

    return InstallationReport(
      commandLineTool: commandLineTool,
      backgroundBroker: backgroundBroker,
      agentSkill: agentSkill
    )
  }

  public func reinstallAgentSkill() async -> ComponentInstallationResult {
    let engine = localEngine
    return await Task.detached(priority: .utility) {
      do {
        return try engine.installAgentSkill(force: true)
      } catch {
        return Self.warningResult(for: .agentSkill, error: error)
      }
    }.value
  }

  public func openLoginItemsSettings() {
    brokerRegistrar.openSystemSettings()
  }

  private func registerBrokerIfNeeded() -> ComponentInstallationResult {
    if brokerRegistrar.status == .notRegistered {
      do {
        try brokerRegistrar.register()
      } catch {
        let currentStatus = brokerRegistrar.status
        if currentStatus == .requiresApproval {
          return brokerResult(for: currentStatus)
        }
        return Self.warningResult(for: .backgroundBroker, error: error)
      }
    }
    return brokerResult(for: brokerRegistrar.status)
  }

  private func brokerResult(for status: BrokerRegistrationStatus) -> ComponentInstallationResult {
    switch status {
    case .enabled:
      ComponentInstallationResult(
        component: .backgroundBroker,
        state: .installed,
        detail: "Background broker is registered."
      )
    case .requiresApproval:
      ComponentInstallationResult(
        component: .backgroundBroker,
        state: .needsApproval,
        detail: "Allow EnvStore in System Settings > General > Login Items."
      )
    case .notRegistered:
      ComponentInstallationResult(
        component: .backgroundBroker,
        state: .waiting,
        detail: "Background broker is not registered."
      )
    case .notFound:
      ComponentInstallationResult(
        component: .backgroundBroker,
        state: .warning,
        detail: "The bundled background broker was not found."
      )
    case .unknown:
      ComponentInstallationResult(
        component: .backgroundBroker,
        state: .warning,
        detail: "macOS returned an unknown broker status."
      )
    }
  }

  private func installingResult(for component: InstallationComponent) -> ComponentInstallationResult
  {
    ComponentInstallationResult(
      component: component,
      state: .installing,
      detail: "Installing…"
    )
  }

  private nonisolated static func warningResult(
    for component: InstallationComponent,
    error: Error
  ) -> ComponentInstallationResult {
    ComponentInstallationResult(
      component: component,
      state: .warning,
      detail: error.localizedDescription
    )
  }
}
