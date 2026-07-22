import EnvStoreAppCore
import EnvStoreCore
import EnvStoreSetup
import SwiftUI

struct ActivityView: View {
  let events: [SafeActivityEvent]

  var body: some View {
    VStack(spacing: 0) {
      AppPageHeader(
        "Activity",
        subtitle: "Security-relevant actions without secret values."
      ) {
        AppStatusBadge(text: "Local log", tone: .neutral)
      }

      ScrollView {
        Group {
          if events.isEmpty {
            AppEmptyState(
              title: "No activity yet",
              message: "Unlocks, edits, reveals, copies, and exports appear here safely.",
              symbol: "clock"
            )
            .frame(maxWidth: .infinity, minHeight: 340)
            .envStorePanel()
          } else {
            activityTable
          }
        }
        .frame(maxWidth: 900)
        .padding(AppMetrics.pageHorizontalPadding)
        .frame(maxWidth: .infinity)
      }
      .background(AppColor.canvas)
    }
  }

  private var activityTable: some View {
    VStack(spacing: 0) {
      HStack {
        Text("EVENT").frame(maxWidth: .infinity, alignment: .leading)
        Text("TIME").frame(width: 190, alignment: .leading)
      }
      .font(.system(size: 10, weight: .semibold))
      .tracking(0.35)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .frame(height: 42)
      .background(AppColor.subtle)
      AppDivider()

      ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
        HStack(spacing: 12) {
          Image(systemName: symbol(for: event.kind))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(AppColor.subtle)
            .clipShape(Circle())
          Text(title(for: event))
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(event.date.formatted(date: .abbreviated, time: .standard))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 190, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        if index < events.count - 1 { AppDivider() }
      }
    }
    .envStorePanel()
  }

  private func title(for event: SafeActivityEvent) -> String {
    let subject = [event.setName, event.variableKey]
      .compactMap { $0 }
      .joined(separator: " · ")
    let action: String
    switch event.kind {
    case .copied: action = "Copied value"
    case .created: action = "Created set"
    case .deleted: action = "Deleted set"
    case .exported: action = "Exported plaintext"
    case .imported: action = "Imported dotenv"
    case .locked: action = "Locked vault"
    case .revealed: action = "Revealed value"
    case .updated: action = "Updated set"
    case .unlocked: action = "Unlocked vault"
    }
    return subject.isEmpty ? action : "\(action) · \(subject)"
  }

  private func symbol(for kind: SafeActivityEvent.Kind) -> String {
    switch kind {
    case .copied: "doc.on.doc"
    case .created: "plus"
    case .deleted: "trash"
    case .exported: "square.and.arrow.up"
    case .imported: "square.and.arrow.down"
    case .locked: "lock"
    case .revealed: "eye"
    case .updated: "pencil"
    case .unlocked: "lock.open"
    }
  }
}

struct SettingsView: View {
  @ObservedObject var setupModel: SetupViewModel
  @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
  @AppStorage("lockAfterMinutes") private var lockAfterMinutes = 10

  var body: some View {
    VStack(spacing: 0) {
      AppPageHeader(
        "Settings",
        subtitle: "Appearance, local security, and command-line integrations."
      ) {
        Button("Verify Setup") { setupModel.refreshStatuses() }
          .buttonStyle(.envSecondary)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          appearanceSection
          securitySection
          integrationsSection
          distributionSection
        }
        .frame(maxWidth: 820)
        .padding(AppMetrics.pageHorizontalPadding)
        .frame(maxWidth: .infinity)
      }
      .background(AppColor.canvas)
    }
    .onAppear { setupModel.refreshStatuses() }
  }

  private var appearanceSection: some View {
    settingsSection("Appearance") {
      AppSettingsRow("Theme", detail: "Choose how EnvStore follows macOS appearance") {
        Picker("Theme", selection: $appearance) {
          ForEach(AppAppearance.allCases) { theme in
            Text(theme.title).tag(theme.rawValue)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 240)
      }
    }
  }

  private var securitySection: some View {
    settingsSection("Security") {
      VStack(spacing: 0) {
        AppSettingsRow("Automatic lock", detail: "After inactivity") {
          Stepper(
            "\(lockAfterMinutes) min",
            value: $lockAfterMinutes,
            in: 1...60
          )
          .font(.system(size: 12).monospacedDigit())
        }
        AppDivider()
        AppSettingsRow("Vault", detail: "No cloud synchronization") {
          AppStatusBadge(text: "Local only", tone: .success)
        }
        AppDivider()
        AppSettingsRow("Authentication", detail: "Owned and presented by macOS") {
          Text("Touch ID or password")
            .font(.system(size: 12, weight: .medium))
        }
        AppDivider()
        AppSettingsRow("Key protection", detail: "Root key stored by macOS") {
          Text("Login Keychain")
            .font(.system(size: 12, weight: .medium))
        }
      }
    }
  }

  private var integrationsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      AppSectionHeader("Integrations") { EmptyView() }
      VStack(spacing: 0) {
        ForEach(Array(InstallationComponent.allCases.enumerated()), id: \.element.rawValue) {
          index, component in
          IntegrationStatusRow(
            result: setupModel.result(for: component),
            openApproval: setupModel.openLoginItemsSettings,
            retrySkill: { Task { await setupModel.reinstallAgentSkill() } },
            copyRecovery: setupModel.copyRecoveryCommand
          )
          if index < InstallationComponent.allCases.count - 1 {
            AppDivider()
          }
        }
        AppDivider()
        HStack(spacing: 8) {
          Button("Repair Setup") {
            Task { await setupModel.retryAll() }
          }
          .buttonStyle(.envSecondary)
          .disabled(setupModel.isRunning || !setupModel.isPackagedApplication)
          Button("Reinstall Agent Skill") {
            Task { await setupModel.reinstallAgentSkill() }
          }
          .buttonStyle(.envSecondary)
          .disabled(setupModel.isRunning || !setupModel.isPackagedApplication)
          Spacer()
        }
        .padding(16)
      }
      .envStorePanel()
      if setupModel.shouldShowTerminalPathNotice {
        TerminalPathNotice(
          copyCommand: setupModel.copyTerminalPathSetupCommand,
          dismiss: setupModel.dismissTerminalPathNotice
        )
      }
    }
  }

  private var distributionSection: some View {
    settingsSection("Distribution") {
      AppSettingsRow(
        "Build",
        detail: "Developer ID signing can be enabled without changing the app architecture"
      ) {
        AppStatusBadge(text: "Unsigned preview", tone: .warning)
      }
    }
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      AppSectionHeader(title) { EmptyView() }
      content().envStorePanel()
    }
  }
}

struct RevisionHistoryView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: VaultViewModel
  let set: EnvironmentSet
  @State private var revisions: [EnvironmentSet] = []
  @State private var restoringID: UUID?

  var body: some View {
    VStack(spacing: 0) {
      AppSheetHeader(
        title: "Revision history",
        subtitle: set.name,
        dismiss: dismiss.callAsFunction
      )
      AppDivider()

      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(revisions.enumerated()), id: \.element.revision) { index, revision in
            revisionRow(revision)
            if index < revisions.count - 1 { AppDivider() }
          }
        }
        .envStorePanel()
        .padding(24)
      }
      .background(AppColor.canvas)
    }
    .frame(width: 600, height: 520)
    .task { revisions = await model.revisions(for: set.id) }
  }

  private func revisionRow(_ revision: EnvironmentSet) -> some View {
    HStack(spacing: 16) {
      Image(systemName: "clock.arrow.circlepath")
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)
        .background(AppColor.subtle)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 5) {
        Text("Revision \(revision.revision)")
          .font(.system(size: 12, weight: .medium).monospacedDigit())
        Text("\(revision.variables.count) variables · \(revision.updatedAt.formatted())")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      Spacer()
      if revision.revision == set.revision {
        AppStatusBadge(text: "Current", tone: .success)
      } else {
        Button(restoringID == revision.id ? "Restoring…" : "Restore") {
          restoringID = revision.id
          Task {
            if await model.restore(revision) { dismiss() }
            restoringID = nil
          }
        }
        .buttonStyle(.envSecondary)
        .disabled(restoringID != nil)
      }
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 66)
  }
}
