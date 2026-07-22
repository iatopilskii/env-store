import AppKit
import EnvStoreCore
import EnvStoreSetup
import Foundation
import SwiftUI

@MainActor
final class SetupViewModel: ObservableObject {
  @Published private(set) var results: [InstallationComponent: ComponentInstallationResult]
  @Published private(set) var isRunning = false
  @Published private(set) var shouldPresentOnboarding: Bool
  @Published private(set) var terminalPathNoticeDismissed: Bool

  let isPackagedApplication: Bool
  let requiresRelocation: Bool
  private let version: String
  private let coordinator: InstallationCoordinator?
  private let defaults: UserDefaults
  private let shellPathAdvisor: ShellPathAdvisor
  private let completionKey = "completedSetupVersion"
  private static let terminalPathNoticeKey = "terminalPathGuidanceCompleted"

  init(
    bundle: Bundle = .main,
    fileManager: FileManager = .default,
    defaults: UserDefaults = .standard,
    processEnvironment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let resources = SetupBundleResources(bundleURL: bundle.bundleURL)
    let resolvedVersion =
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? EnvStoreCore.version
    version = resolvedVersion
    self.defaults = defaults
    terminalPathNoticeDismissed = defaults.bool(forKey: Self.terminalPathNoticeKey)
    isPackagedApplication = resources.isPackagedApplication
    requiresRelocation = resources.isPackagedApplication && resources.isOnReadOnlyVolume
    let home = fileManager.homeDirectoryForCurrentUser
    shellPathAdvisor = ShellPathAdvisor(
      homeDirectory: home,
      pathEnvironment: processEnvironment["PATH"] ?? ""
    )

    let waitingResults = InstallationComponent.allCases.map {
      (
        $0,
        ComponentInstallationResult(
          component: $0,
          state: .waiting,
          detail: "Waiting for setup."
        )
      )
    }
    results = Dictionary(uniqueKeysWithValues: waitingResults)

    guard resources.isPackagedApplication else {
      coordinator = nil
      shouldPresentOnboarding = false
      return
    }

    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0].appending(path: "EnvStore", directoryHint: .isDirectory)
    let configuration = LocalSetupConfiguration(
      bundledCLIURL: resources.bundledCLIURL,
      agentSkillsRoot: resources.agentSkillsRoot,
      homeDirectory: home,
      applicationSupportDirectory: applicationSupport,
      temporaryDirectory: fileManager.temporaryDirectory,
      applicationDirectories: [
        URL(filePath: "/Applications", directoryHint: .isDirectory),
        home.appending(path: "Applications", directoryHint: .isDirectory),
      ],
      pathEnvironment: processEnvironment["PATH"] ?? "",
      version: resolvedVersion
    )
    let resolvedCoordinator = InstallationCoordinator(
      localEngine: LocalInstallationEngine(configuration: configuration),
      brokerRegistrar: SMAppServiceBrokerRegistrar()
    )
    coordinator = resolvedCoordinator
    let report = resolvedCoordinator.inspect()
    results = Self.results(from: report)
    shouldPresentOnboarding = defaults.string(forKey: completionKey) != resolvedVersion
  }

  var mandatoryComponentsReady: Bool {
    results[.commandLineTool]?.state == .installed
      && results[.backgroundBroker]?.state == .installed
  }

  var agentSkillRecoveryCommand: String? {
    results[.agentSkill]?.recoveryCommand
  }

  var shouldShowTerminalPathNotice: Bool {
    results[.commandLineTool]?.state == .installed
      && shellPathAdvisor.shouldShowNotice
      && !terminalPathNoticeDismissed
  }

  func result(for component: InstallationComponent) -> ComponentInstallationResult {
    results[component]
      ?? ComponentInstallationResult(
        component: component,
        state: .waiting,
        detail: "Waiting for setup."
      )
  }

  func beginIfNeeded() async {
    guard shouldPresentOnboarding, !requiresRelocation else { return }
    await install(force: false)
  }

  func retryAll() async {
    await install(force: true)
  }

  func reinstallAgentSkill() async {
    guard let coordinator, !isRunning else { return }
    isRunning = true
    results[.agentSkill] = ComponentInstallationResult(
      component: .agentSkill,
      state: .installing,
      detail: "Installing…"
    )
    results[.agentSkill] = await coordinator.reinstallAgentSkill()
    isRunning = false
  }

  func refreshStatuses() {
    guard let coordinator else { return }
    results = Self.results(from: coordinator.inspect())
  }

  func openLoginItemsSettings() {
    coordinator?.openLoginItemsSettings()
  }

  func copyRecoveryCommand() {
    guard let command = agentSkillRecoveryCommand else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)
  }

  func copyTerminalPathSetupCommand() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(shellPathAdvisor.zshSetupCommand, forType: .string)
  }

  func dismissTerminalPathNotice() {
    terminalPathNoticeDismissed = true
    defaults.set(true, forKey: Self.terminalPathNoticeKey)
  }

  func completeOnboarding() {
    guard mandatoryComponentsReady else { return }
    defaults.set(version, forKey: completionKey)
    shouldPresentOnboarding = false
  }

  private func install(force: Bool) async {
    guard let coordinator, !isRunning else { return }
    isRunning = true
    let report = await coordinator.install(force: force) { [weak self] result in
      self?.results[result.component] = result
    }
    results = Self.results(from: report)
    isRunning = false
  }

  private static func results(
    from report: InstallationReport
  ) -> [InstallationComponent: ComponentInstallationResult] {
    [
      .commandLineTool: report.commandLineTool,
      .backgroundBroker: report.backgroundBroker,
      .agentSkill: report.agentSkill,
    ]
  }
}

struct FirstRunSetupView: View {
  @ObservedObject var model: SetupViewModel

  var body: some View {
    ZStack {
      AppColor.canvas.ignoresSafeArea()

      VStack(spacing: 0) {
        VStack(spacing: 16) {
          BrandMark(size: 48)
          VStack(spacing: 6) {
            Text("Set up EnvStore")
              .font(.system(size: 22, weight: .semibold))
            Text("Connect the local vault to your terminal and coding agents.")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
        }
        .padding(28)

        AppDivider()

        Group {
          if model.requiresRelocation {
            relocationPanel
          } else {
            VStack(spacing: 16) {
              VStack(spacing: 0) {
                AppSectionHeader("Local components") {
                  AppStatusBadge(
                    text: model.mandatoryComponentsReady ? "Ready" : "Installing",
                    tone: model.mandatoryComponentsReady ? .success : .neutral
                  )
                }
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(AppColor.subtle)
                AppDivider()

                ForEach(
                  Array(InstallationComponent.allCases.enumerated()),
                  id: \.element.rawValue
                ) { index, component in
                  IntegrationStatusRow(
                    result: model.result(for: component),
                    openApproval: model.openLoginItemsSettings,
                    retrySkill: { Task { await model.reinstallAgentSkill() } },
                    copyRecovery: model.copyRecoveryCommand
                  )
                  if index < InstallationComponent.allCases.count - 1 {
                    AppDivider()
                  }
                }
              }
              .envStorePanel()

              if model.shouldShowTerminalPathNotice {
                TerminalPathNotice(
                  copyCommand: model.copyTerminalPathSetupCommand,
                  dismiss: model.dismissTerminalPathNotice
                )
              }
            }
            .padding(24)
          }
        }

        AppDivider()

        HStack(spacing: 8) {
          if !model.requiresRelocation {
            if !model.mandatoryComponentsReady, !model.isRunning {
              Button("Retry Setup") { Task { await model.retryAll() } }
                .buttonStyle(.envSecondary)
            }
            Spacer()
            Button("Continue") { model.completeOnboarding() }
              .buttonStyle(.envPrimary)
              .disabled(!model.mandatoryComponentsReady || model.isRunning)
              .keyboardShortcut(.defaultAction)
          } else {
            Spacer()
            AppStatusBadge(text: "Action required", tone: .warning)
          }
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(AppColor.surface)
      }
      .frame(width: 640)
      .envStoreRaisedPanel()
    }
    .task { await model.beginIfNeeded() }
  }

  private var relocationPanel: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "arrow.right.square")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(AppColor.warning)
        .frame(width: 34, height: 34)
        .background(AppColor.warning.opacity(0.1))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 7) {
        Text("Move EnvStore to Applications")
          .font(.system(size: 13, weight: .semibold))
        Text(
          "EnvStore is running from a read-only disk image. Drag it to Applications, eject the DMG, and open the installed copy before setup."
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 12)
    }
    .padding(16)
    .background(AppColor.warning.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: AppMetrics.largeCornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: AppMetrics.largeCornerRadius)
        .stroke(AppColor.warning.opacity(0.25), lineWidth: AppMetrics.hairline)
    }
    .padding(24)
  }
}

struct TerminalPathNotice: View {
  let copyCommand: () -> Void
  let dismiss: () -> Void
  @State private var copied = false

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "terminal.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppColor.warning)
        .frame(width: 32, height: 32)
        .background(AppColor.warning.opacity(0.1))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 6) {
        Text("Terminal PATH may need setup")
          .font(.system(size: 12, weight: .semibold))
        Text(
          "This app's PATH does not include ~/.local/bin. Copy and run the zsh command, then open a new terminal window."
        )
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 14) {
          Button(copied ? "Command copied" : "Copy zsh command") {
            copyCommand()
            copied = true
          }
          .buttonStyle(.link)
          Button("I've configured it", action: dismiss)
            .buttonStyle(.link)
        }
        .font(.caption)
      }
      Spacer(minLength: 12)
    }
    .padding(16)
    .background(AppColor.warning.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: AppMetrics.largeCornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: AppMetrics.largeCornerRadius)
        .stroke(AppColor.warning.opacity(0.25), lineWidth: AppMetrics.hairline)
    }
  }
}

struct IntegrationStatusRow: View {
  let result: ComponentInstallationResult
  var openApproval: () -> Void = {}
  var retrySkill: () -> Void = {}
  var copyRecovery: () -> Void = {}

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      statusIcon
        .frame(width: 32, height: 32)
        .background(AppColor.subtle)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 5) {
        Text(result.component.title)
          .font(.system(size: 12, weight: .medium))
        Text(result.detail)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        actions
      }
      Spacer(minLength: 12)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch result.state {
    case .waiting:
      Image(systemName: "circle").foregroundStyle(.tertiary)
    case .installing:
      ProgressView().controlSize(.small)
    case .installed:
      Image(systemName: "checkmark").foregroundStyle(AppColor.success)
    case .needsApproval:
      Image(systemName: "exclamationmark").foregroundStyle(AppColor.warning)
    case .warning:
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppColor.warning)
    }
  }

  @ViewBuilder
  private var actions: some View {
    if result.component == .backgroundBroker, result.state == .needsApproval {
      Button("Open Login Items", action: openApproval)
        .buttonStyle(.link)
        .font(.caption)
    }
    if result.component == .agentSkill, result.state == .warning {
      HStack(spacing: 12) {
        Button("Retry", action: retrySkill)
          .buttonStyle(.link)
        if result.recoveryCommand != nil {
          Button("Copy manual command", action: copyRecovery)
            .buttonStyle(.link)
        }
      }
      .font(.caption)
    }
  }
}

extension InstallationComponent {
  fileprivate var title: String {
    switch self {
    case .commandLineTool: "Command-line tool"
    case .backgroundBroker: "Background broker"
    case .agentSkill: "Agent skill"
    }
  }
}
