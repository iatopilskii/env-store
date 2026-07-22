import ServiceManagement

public enum BrokerRegistrationStatus: Equatable, Sendable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
  case unknown
}

@MainActor
public protocol BrokerRegistering: AnyObject {
  var status: BrokerRegistrationStatus { get }
  func register() throws
  func openSystemSettings()
}

@MainActor
public final class SMAppServiceBrokerRegistrar: BrokerRegistering {
  private let service: SMAppService
  private let legacyPlistURL: URL

  public init(
    plistName: String = "dev.envstore.broker.plist",
    legacyPlistURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/LaunchAgents/dev.envstore.broker.plist")
  ) {
    service = SMAppService.agent(plistName: plistName)
    self.legacyPlistURL = legacyPlistURL
  }

  public var status: BrokerRegistrationStatus {
    let serviceStatus: SMAppService.Status
    if service.status == .notRegistered,
      FileManager.default.fileExists(atPath: legacyPlistURL.path)
    {
      serviceStatus = SMAppService.statusForLegacyPlist(at: legacyPlistURL)
    } else {
      serviceStatus = service.status
    }
    return switch serviceStatus {
    case .notRegistered: .notRegistered
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .notFound
    @unknown default: .unknown
    }
  }

  public func register() throws {
    try service.register()
  }

  public func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
