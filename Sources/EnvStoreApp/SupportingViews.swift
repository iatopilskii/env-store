import AppKit
import CryptoKit
import EnvStoreAppCore
import EnvStoreCore
import SwiftUI

struct ProjectsView: View {
    @ObservedObject var model: VaultViewModel
    @State private var showingEditor = false

    var body: some View {
        List {
            ForEach(model.projectBindings) { binding in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(binding.path)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                        Text(model.sets.first(where: { $0.id == binding.setID })?.name ?? "Missing set")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await model.deleteProjectBinding(id: binding.id) }
                    } label: {
                        Image(systemName: "trash").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete project binding for \(binding.path)")
                }
            }
        }
        .overlay {
            if model.projectBindings.isEmpty {
                ContentUnavailableView(
                    "No Project Bindings",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Link a directory to resolve its nearest environment set.")
                )
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            Button("Link Project", systemImage: "plus") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor) {
            ProjectBindingEditor(model: model)
        }
    }
}

struct ProfilesView: View {
    @ObservedObject var model: VaultViewModel
    @State private var showingEditor = false

    var body: some View {
        List {
            ForEach(model.profiles) { profile in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Text(profile.trustMode.rawValue.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(([profile.executablePath] + profile.arguments).joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack {
                        Text("TTL \(Int(profile.defaultTTL))s · \(profile.defaultUses) uses")
                            .font(.caption2.monospacedDigit())
                        Spacer()
                        Button(role: .destructive) {
                            Task { await model.deleteProfile(id: profile.id) }
                        } label: {
                            Image(systemName: "trash").frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete profile \(profile.name)")
                    }
                }
            }
        }
        .overlay {
            if model.profiles.isEmpty {
                ContentUnavailableView(
                    "No Command Profiles",
                    systemImage: "terminal",
                    description: Text("Pin an exact executable and arguments for agent grants.")
                )
            }
        }
        .navigationTitle("Profiles")
        .toolbar {
            Button("New Profile", systemImage: "plus") { showingEditor = true }
        }
        .sheet(isPresented: $showingEditor) {
            CommandProfileEditor(model: model)
        }
    }
}

private struct ProjectBindingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: VaultViewModel
    @State private var path = ""
    @State private var setID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Link Project").font(.headline)
            LabeledContent("Directory") {
                HStack {
                    TextField("/path/to/project", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseDirectory() }
                }
            }
            LabeledContent("Environment Set") {
                Picker("Environment Set", selection: $setID) {
                    Text("Select…").tag(nil as UUID?)
                    ForEach(model.sets) { set in
                        Text(set.name).tag(set.id as UUID?)
                    }
                }
                .labelsHidden()
            }
            Text("The nearest linked ancestor wins. Paths are encrypted in the vault.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Link") {
                    guard let setID else { return }
                    Task {
                        if await model.saveProjectBinding(path: path, setID: setID) { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(path.isEmpty || setID == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 280)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private struct CommandProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: VaultViewModel
    @State private var name = ""
    @State private var setID: UUID?
    @State private var projectRoot = ""
    @State private var executable = ""
    @State private var argumentsText = ""
    @State private var trustMode = ProfileTrustMode.development
    @State private var ttl = 300
    @State private var uses = 1
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Command Profile").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(20)
            Divider()
            Form {
                TextField("Profile name", text: $name)
                Picker("Environment set", selection: $setID) {
                    Text("Select…").tag(nil as UUID?)
                    ForEach(model.sets) { set in Text(set.name).tag(set.id as UUID?) }
                }
                pathField("Project root", text: $projectRoot, directories: true)
                pathField("Executable", text: $executable, directories: false)
                TextField("Arguments (one per line)", text: $argumentsText, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(.body, design: .monospaced))
                Picker("Trust mode", selection: $trustMode) {
                    Text("Development").tag(ProfileTrustMode.development)
                    Text("Strict (pin executable digest)").tag(ProfileTrustMode.strict)
                }
                Stepper("Grant TTL: \(ttl) seconds", value: $ttl, in: 30...3600, step: 30)
                Stepper("Maximum uses: \(uses)", value: $uses, in: 1...100)
                if let localError {
                    Text(localError).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Strict mode rejects a changed executable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save Profile") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || setID == nil || projectRoot.isEmpty || executable.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
        }
        .frame(width: 640, height: 590)
    }

    private func pathField(
        _ label: String,
        text: Binding<String>,
        directories: Bool
    ) -> some View {
        LabeledContent(label) {
            HStack {
                TextField(label, text: text)
                    .font(.system(.body, design: .monospaced))
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = directories
                    panel.canChooseFiles = !directories
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    text.wrappedValue = url.resolvingSymlinksInPath().standardizedFileURL.path
                }
            }
        }
    }

    private func submit() {
        guard let setID else { return }
        let digest: Data?
        if trustMode == .strict {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: executable)) else {
                localError = "The executable could not be read for strict digest pinning."
                return
            }
            digest = Data(SHA256.hash(data: data))
        } else {
            digest = nil
        }
        let profile = CommandProfile(
            name: name,
            setID: setID,
            projectRoot: projectRoot,
            executablePath: executable,
            arguments: argumentsText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
            trustMode: trustMode,
            executableDigest: digest,
            defaultTTL: TimeInterval(ttl),
            defaultUses: uses
        )
        do {
            try profile.validate()
        } catch {
            localError = "Review the profile constraints and try again."
            return
        }
        Task {
            if await model.saveProfile(profile) { dismiss() }
        }
    }
}

struct ActivityView: View {
    let events: [SafeActivityEvent]

    var body: some View {
        List(events) { event in
            HStack(spacing: 10) {
                Image(systemName: symbol(for: event.kind))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: event))
                    Text(event.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
        .overlay {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "clock",
                    description: Text("Security-relevant actions appear here without values.")
                )
            }
        }
        .navigationTitle("Activity")
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
        case .created: "plus.circle"
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
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("lockAfterMinutes") private var lockAfterMinutes = 10

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Security") {
                Stepper(
                    "Lock after \(lockAfterMinutes) minutes of inactivity",
                    value: $lockAfterMinutes,
                    in: 1...60
                )
                LabeledContent("Vault") {
                    Label("Local only", systemImage: "checkmark.shield")
                }
                LabeledContent("Authentication") {
                    Text("Touch ID or macOS password")
                }
            }
            Section("Distribution") {
                LabeledContent("Build") {
                    Text("Unsigned preview")
                }
                Text("Unsigned previews are for local development. Developer ID signing and notarization can be enabled later in the release workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .padding()
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
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Revision History").font(.headline)
                    Text(set.name).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            List(revisions, id: \.revision) { revision in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Revision \(revision.revision)")
                            .font(.body.monospacedDigit())
                        Text("\(revision.variables.count) variables · \(revision.updatedAt.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if revision.revision == set.revision {
                        Text("CURRENT").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Button(restoringID == revision.id ? "Restoring…" : "Restore") {
                            restoringID = revision.id
                            Task {
                                if await model.restore(revision) { dismiss() }
                                restoringID = nil
                            }
                        }
                        .disabled(restoringID != nil)
                    }
                }
            }
        }
        .frame(width: 560, height: 480)
        .task { revisions = await model.revisions(for: set.id) }
    }
}
