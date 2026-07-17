import AppKit
import CryptoKit
import Darwin
import EnvStoreAppCore
import EnvStoreCore
import SwiftUI

struct SetListView: View {
    @ObservedObject var model: VaultViewModel
    @Binding var showingCreateSet: Bool

    var body: some View {
        List(selection: $model.selectedSetID) {
            ForEach(model.sets) { set in
                VStack(alignment: .leading, spacing: 3) {
                    Text(set.name)
                        .lineLimit(1)
                    Text("\(set.variables.count) variables")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(set.id)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay {
            if model.sets.isEmpty {
                ContentUnavailableView(
                    "No Environment Sets",
                    systemImage: "key.horizontal",
                    description: Text("Create a set or paste a .env file to begin.")
                )
            }
        }
        .navigationTitle("Sets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateSet = true
                } label: {
                    Label("New Set", systemImage: "plus")
                }
                .help("New Set (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

struct SetDetailView: View {
    @ObservedObject var model: VaultViewModel
    let set: EnvironmentSet
    @State private var revealedIDs: Set<UUID> = []
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var showingRevisions = false
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                variablePanel
                if !set.note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTE").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        Text(set.note).textSelection(.enabled)
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle(set.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingEditor) {
            SetEditorSheet(mode: .edit(set)) { draft in
                await model.update(id: set.id, draft: draft)
            }
        }
        .sheet(isPresented: $showingRevisions) {
            RevisionHistoryView(model: model, set: set)
        }
        .confirmationDialog(
            "Delete \(set.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Set", role: .destructive) {
                Task { _ = await model.delete(id: set.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The encrypted set and its local revision history will be removed.")
        }
        .alert("Export Failed", isPresented: exportErrorIsPresented) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "The file could not be created.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(set.name)
                    .font(.system(size: 25, weight: .semibold))
                HStack(spacing: 12) {
                    Label("Revision \(set.revision)", systemImage: "clock.arrow.circlepath")
                    Text("Updated \(set.updatedAt, style: .relative)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            Button("Edit") { showingEditor = true }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: .command)
        }
    }

    private var variablePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ENVIRONMENT VARIABLES")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(set.variables.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            Divider()
            ForEach(Array(set.variables.enumerated()), id: \.element.id) { index, variable in
                VariableRow(
                    variable: variable,
                    revealed: revealedIDs.contains(variable.id),
                    onReveal: { toggleReveal(variable) },
                    onCopy: { copy(variable) }
                )
                if index < set.variables.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .envStorePanel()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingRevisions = true
            } label: {
                Label("Revisions", systemImage: "clock.arrow.circlepath")
            }
            .help("Revision History")

            Menu {
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    Task { _ = await model.duplicate(id: set.id) }
                }
                Button("Export .env…", systemImage: "square.and.arrow.up") {
                    exportSet()
                }
                Divider()
                Button("Delete Set…", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .help("More Actions")
        }
    }

    private func toggleReveal(_ variable: EnvironmentVariable) {
        if revealedIDs.remove(variable.id) != nil {
            return
        }
        revealedIDs.insert(variable.id)
        model.recordReveal(setName: set.name, key: variable.key)
        Task {
            try? await Task.sleep(for: .seconds(15))
            await MainActor.run { _ = revealedIDs.remove(variable.id) }
        }
    }

    private func copy(_ variable: EnvironmentVariable) {
        ClipboardGuard.copy(variable.value)
        model.recordCopy(setName: set.name, key: variable.key)
    }

    private func exportSet() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(set.name.replacingOccurrences(of: " ", with: "-" )).env"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "Choose a new file. EnvStore never overwrites an existing plaintext file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard PlaintextExportConfirmation.confirm(for: url) else { return }

        Task {
            guard let dotenv = await model.dotenvForExport(id: set.id) else { return }
            do {
                try PlaintextFileWriter.writeNewFile(Data(dotenv.utf8), to: url)
            } catch {
                exportError = "EnvStore could not create a new 0600 file at that location. Existing files are never overwritten."
            }
        }
    }

    private var exportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }
}

private struct VariableRow: View {
    let variable: EnvironmentVariable
    let revealed: Bool
    let onReveal: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(variable.key)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .textSelection(.enabled)
                    if EnvironmentKeyRisk.classify(variable.key) != nil {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("High-risk environment key")
                    }
                }
                Text(revealed ? variable.value : "••••••••••••")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(revealed ? .primary : .secondary)
                    .lineLimit(revealed ? 4 : 1)
                    .textSelection(.enabled)
                    .accessibilityLabel(revealed ? "Value \(variable.value)" : "Value hidden")
            }
            Spacer(minLength: 12)
            Button(action: onReveal) {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? "Hide \(variable.key)" : "Reveal \(variable.key) for 15 seconds")
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(variable.key); clipboard clears after 30 seconds")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

@MainActor
private enum ClipboardGuard {
    static func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        let changeCount = pasteboard.changeCount
        let digest = SHA256.hash(data: Data(value.utf8))

        Task {
            try? await Task.sleep(for: .seconds(30))
            guard pasteboard.changeCount == changeCount,
                  let current = pasteboard.string(forType: .string),
                  SHA256.hash(data: Data(current.utf8)) == digest else {
                return
            }
            pasteboard.clearContents()
        }
    }
}

private enum PlaintextFileWriter {
    static func writeNewFile(_ data: Data, to url: URL) throws {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw CocoaError(.fileWriteFileExists) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }
}

@MainActor
private enum PlaintextExportConfirmation {
    static func confirm(for url: URL) -> Bool {
        let path = url.path.lowercased()
        let synchronized = ["icloud", "dropbox", "onedrive", "google drive"]
            .contains { path.contains($0) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = synchronized
            ? "Export plaintext to a synchronized location?"
            : "Export plaintext .env file?"
        alert.informativeText = synchronized
            ? "This location may upload the file. The export is unencrypted and can be indexed, backed up, or read by other processes."
            : "The export is unencrypted and can be indexed, backed up, or read by other processes."
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
