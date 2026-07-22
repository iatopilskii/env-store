import Foundation

public enum InstallationComponent: String, Codable, CaseIterable, Sendable {
  case commandLineTool
  case backgroundBroker
  case agentSkill
}

public enum ComponentInstallationState: String, Codable, Sendable {
  case waiting
  case installing
  case installed
  case needsApproval
  case warning
}

public enum AgentSkillInstallationMethod: String, Codable, Sendable {
  case npx
  case native
}

public struct ComponentInstallationResult: Equatable, Sendable {
  public let component: InstallationComponent
  public let state: ComponentInstallationState
  public let detail: String
  public let method: AgentSkillInstallationMethod?
  public let installedLocations: [URL]
  public let recoveryCommand: String?

  public init(
    component: InstallationComponent,
    state: ComponentInstallationState,
    detail: String,
    method: AgentSkillInstallationMethod? = nil,
    installedLocations: [URL] = [],
    recoveryCommand: String? = nil
  ) {
    self.component = component
    self.state = state
    self.detail = detail
    self.method = method
    self.installedLocations = installedLocations
    self.recoveryCommand = recoveryCommand
  }
}

public enum EnvStoreSetupError: Error, LocalizedError, Sendable {
  case invalidBundledResource(String)
  case unsafeDestination(String)
  case unownedDestination(String)
  case processLaunchFailed(String)
  case posixFailure(operation: String, code: Int32)

  public var errorDescription: String? {
    switch self {
    case .invalidBundledResource(let resource):
      "Required bundled resource is missing or invalid: \(resource)"
    case .unsafeDestination(let path):
      "Refusing to write through an unsafe path: \(path)"
    case .unownedDestination(let path):
      "An existing agent skill is not managed by EnvStore: \(path)"
    case .processLaunchFailed(let reason):
      "Could not launch the installer: \(reason)"
    case .posixFailure(let operation, let code):
      "\(operation) failed with POSIX error \(code)"
    }
  }
}
