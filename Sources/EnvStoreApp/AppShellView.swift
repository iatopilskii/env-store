import EnvStoreAppCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case sets = "Environment Sets"
  case projects = "Projects"
  case profiles = "Command Profiles"
  case activity = "Activity"
  case settings = "Settings"

  var id: String { rawValue }

  var navigationTitle: String {
    switch self {
    case .sets: "Sets"
    case .projects: "Projects"
    case .profiles: "Profiles"
    case .activity: "Activity"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .sets: "key.horizontal"
    case .projects: "folder"
    case .profiles: "terminal"
    case .activity: "clock.arrow.circlepath"
    case .settings: "gearshape"
    }
  }
}

struct AppShellView: View {
  @ObservedObject var model: VaultViewModel
  @ObservedObject var setupModel: SetupViewModel
  @ObservedObject var shellModel: AppShellModel
  @State private var section = AppSection.sets
  @State private var showingCreateSet = false

  var body: some View {
    Group {
      if setupModel.shouldPresentOnboarding {
        FirstRunSetupView(model: setupModel)
      } else if model.lockState == .unlocked {
        unlockedContent
      } else {
        LockView(model: model)
      }
    }
    .background(AppColor.canvas)
    .background {
      WindowChromeConfigurator()
        .frame(width: 0, height: 0)
    }
    .alert("EnvStore", isPresented: errorIsPresented) {
      Button("OK") { model.clearError() }
    } message: {
      Text(model.errorMessage ?? "Unknown error")
    }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.sessionDidResignActiveNotification
      )
    ) { _ in
      Task { await model.lock() }
    }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.willSleepNotification
      )
    ) { _ in
      Task { await model.lock() }
    }
  }

  private var unlockedContent: some View {
    HStack(spacing: 0) {
      if shellModel.isSidebarVisible {
        HStack(spacing: 0) {
          sidebar
            .frame(width: AppMetrics.sidebarWidth)

          Rectangle()
            .fill(AppColor.border)
            .frame(width: AppMetrics.hairline)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
      }

      sectionContent
        .environment(\.showsAppSidebarControl, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(AppColor.canvas)
    .animation(.easeInOut(duration: 0.18), value: shellModel.isSidebarVisible)
    .sheet(isPresented: $showingCreateSet) {
      SetEditorSheet(mode: .create) { draft in
        await model.create(draft)
      }
    }
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      sidebarHeader

      VStack(spacing: 4) {
        Text("WORKSPACE")
          .font(.system(size: 10, weight: .semibold))
          .tracking(0.45)
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.bottom, 6)

        ForEach(AppSection.allCases) { item in
          sidebarButton(for: item)
        }
      }
      .padding(10)

      Spacer(minLength: 16)

      VStack(spacing: 10) {
        AppDivider()
        Button {
          Task { await model.lock() }
        } label: {
          HStack(spacing: 9) {
            Image(systemName: "lock")
              .frame(width: 16)
            Text("Lock Vault")
            Spacer()
            Text("⇧⌘L")
              .font(.system(size: 10))
              .foregroundStyle(.tertiary)
          }
          .font(.system(size: 12, weight: .medium))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 13)
        .keyboardShortcut("l", modifiers: [.command, .shift])
      }
    }
    .background(AppColor.sidebar)
  }

  private var sidebarHeader: some View {
    HStack(spacing: 10) {
      BrandMark(size: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text("EnvStore")
          .font(.system(size: 14, weight: .semibold))

        HStack(spacing: 4) {
          Circle()
            .fill(AppColor.success)
            .frame(width: 5, height: 5)
          Text("LOCAL VAULT")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.35)
        }
        .foregroundStyle(.secondary)
      }

      Spacer()
      AppSidebarToggleButton()
    }
    .padding(.horizontal, 14)
    .appShellHeader(background: AppColor.sidebar)
  }

  private func sidebarButton(for item: AppSection) -> some View {
    Button {
      section = item
    } label: {
      HStack(spacing: 9) {
        Image(systemName: item.symbol)
          .font(.system(size: 12, weight: .medium))
          .frame(width: 17)
        Text(item.navigationTitle)
          .font(.system(size: 12, weight: .medium))
        Spacer()
      }
      .foregroundStyle(section == item ? .primary : .secondary)
      .padding(.horizontal, 10)
      .frame(height: 34)
      .contentShape(Rectangle())
      .background(section == item ? AppColor.surface : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
      .overlay {
        if section == item {
          RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
            .stroke(AppColor.border, lineWidth: AppMetrics.hairline)
        }
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var sectionContent: some View {
    switch section {
    case .sets:
      SetsWorkspaceView(model: model, showingCreateSet: $showingCreateSet)
    case .projects:
      ProjectsView(model: model)
    case .profiles:
      ProfilesView(model: model)
    case .activity:
      ActivityView(events: model.activity)
    case .settings:
      SettingsView(setupModel: setupModel)
    }
  }

  private var errorIsPresented: Binding<Bool> {
    Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.clearError() } }
    )
  }
}

private struct LockView: View {
  @ObservedObject var model: VaultViewModel

  var body: some View {
    ZStack {
      AppColor.canvas.ignoresSafeArea()

      VStack(spacing: 0) {
        VStack(spacing: 20) {
          BrandMark(size: 52)
          VStack(spacing: 7) {
            Text("Welcome back")
              .font(.system(size: 22, weight: .semibold))
            Text("Unlock your local environment vault to continue.")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }

          Button {
            Task { await model.unlock() }
          } label: {
            HStack(spacing: 8) {
              if model.lockState == .unlocking {
                ProgressView()
                  .controlSize(.small)
                  .colorScheme(.dark)
              } else {
                Image(systemName: "touchid")
              }
              Text(model.lockState == .unlocking ? "Unlocking…" : "Unlock EnvStore")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.envPrimary)
          .disabled(model.lockState == .unlocking)
          .keyboardShortcut(.defaultAction)
        }
        .padding(32)

        AppDivider()

        HStack(spacing: 8) {
          Image(systemName: "lock.shield")
          Text("Touch ID or macOS password · Nothing leaves this Mac")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .frame(height: 48)
      }
      .frame(width: 420)
      .envStoreRaisedPanel()
    }
  }
}
