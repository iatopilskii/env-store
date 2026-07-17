import AppKit
import EnvStoreAppCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case sets = "Sets"
    case projects = "Projects"
    case profiles = "Profiles"
    case activity = "Activity"
    case settings = "Settings"

    var id: String { rawValue }

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
    @State private var section: AppSection? = .sets
    @State private var showingCreateSet = false

    var body: some View {
        Group {
            if model.lockState == .unlocked {
                unlockedContent
            } else {
                LockView(model: model)
            }
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
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    BrandMark(size: 28)
                    Text("EnvStore")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(12)

                List(AppSection.allCases, selection: $section) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Button {
                    Task { await model.lock() }
                } label: {
                    Label("Lock Vault", systemImage: "lock")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(14)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } content: {
            sectionContent
        } detail: {
            sectionDetail
        }
        .sheet(isPresented: $showingCreateSet) {
            SetEditorSheet(mode: .create) { draft in
                await model.create(draft)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section ?? .sets {
        case .sets:
            SetListView(model: model, showingCreateSet: $showingCreateSet)
        case .projects:
            ProjectsView(model: model)
        case .profiles:
            ProfilesView(model: model)
        case .activity:
            ActivityView(events: model.activity)
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var sectionDetail: some View {
        if section == .sets, let set = model.selectedSet {
            SetDetailView(model: model, set: set)
                .id(set.id.uuidString + "-\(set.revision)")
        } else {
            ContentUnavailableView(
                section?.rawValue ?? "EnvStore",
                systemImage: section?.symbol ?? "lock.shield",
                description: Text(detailDescription)
            )
        }
    }

    private var detailDescription: String {
        switch section ?? .sets {
        case .sets: "Select a set to inspect its variables."
        case .projects: "Project bindings resolve a set from the current directory."
        case .profiles: "Profiles constrain commands used by agents."
        case .activity: "Activity records actions, never secret values."
        case .settings: "Security and integration settings."
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
        VStack(spacing: 18) {
            BrandMark(size: 64)
            VStack(spacing: 6) {
                Text("EnvStore")
                    .font(.system(size: 24, weight: .semibold))
                Text("Local secrets. Exact commands. Nothing synced.")
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await model.unlock() }
            } label: {
                HStack(spacing: 8) {
                    if model.lockState == .unlocking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "touchid")
                    }
                    Text(model.lockState == .unlocking ? "Unlocking…" : "Unlock Vault")
                }
                .frame(minWidth: 150, minHeight: AppMetrics.controlHeight)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.lockState == .unlocking)
            .keyboardShortcut(.defaultAction)
            Text("Touch ID or your macOS login password")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
