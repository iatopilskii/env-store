import AppKit
import CryptoKit
import Darwin
import EnvStoreAppCore
import EnvStoreCore
import SwiftUI

struct SetsWorkspaceView: View {
  @ObservedObject var model: VaultViewModel
  @Binding var showingCreateSet: Bool

  var body: some View {
    VStack(spacing: 0) {
      AppPageHeader(
        "Environment Sets",
        subtitle: "Encrypted variables grouped by project or workflow."
      ) {
        Button("New Set", systemImage: "plus") {
          showingCreateSet = true
        }
        .buttonStyle(.envPrimary)
        .help("New Set (⌘N)")
        .keyboardShortcut("n", modifiers: .command)
      }

      HStack(spacing: 0) {
        SetListView(model: model)
          .frame(width: 286)

        Rectangle()
          .fill(AppColor.border)
          .frame(width: AppMetrics.hairline)

        Group {
          if let set = model.selectedSet {
            SetDetailView(model: model, set: set)
              .id(set.id.uuidString + "-\(set.revision)")
          } else {
            AppEmptyState(
              title: "Select an environment set",
              message: "Choose a set to inspect variables, revisions, and export options.",
              symbol: "key.horizontal"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .background(AppColor.canvas)
      }
    }
    .background(AppColor.canvas)
  }
}

struct SetListView: View {
  @ObservedObject var model: VaultViewModel
  @State private var query = ""

  var body: some View {
    VStack(spacing: 0) {
      searchField
      AppDivider()

      if filteredSets.isEmpty {
        AppEmptyState(
          title: query.isEmpty ? "No environment sets" : "No matching sets",
          message: query.isEmpty
            ? "Create a set or paste a .env file to begin."
            : "Try a different search term.",
          symbol: query.isEmpty ? "key.horizontal" : "magnifyingglass"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(filteredSets) { set in
              setButton(set)
              AppDivider()
            }
          }
        }
      }
    }
    .background(AppColor.surface)
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.tertiary)
      TextField("Search sets", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 12))
    }
    .padding(.horizontal, 10)
    .frame(height: 32)
    .background(AppColor.subtle)
    .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
    .padding(12)
  }

  private func setButton(_ set: EnvironmentSet) -> some View {
    let selected = model.selectedSetID == set.id
    return Button {
      model.selectedSetID = set.id
    } label: {
      HStack(spacing: 11) {
        Rectangle()
          .fill(selected ? Color.primary : Color.clear)
          .frame(width: 2, height: 30)
        VStack(alignment: .leading, spacing: 5) {
          Text(set.name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
          HStack(spacing: 5) {
            Text("\(set.variables.count) variables")
            Text("·")
            Text("rev \(set.revision)")
          }
          .font(.system(size: 10).monospacedDigit())
          .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(selected ? .secondary : .tertiary)
      }
      .padding(.horizontal, 12)
      .frame(height: 60)
      .contentShape(Rectangle())
      .background(selected ? AppColor.subtle : Color.clear)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
  }

  private var filteredSets: [EnvironmentSet] {
    guard !query.isEmpty else { return model.sets }
    return model.sets.filter { $0.name.localizedCaseInsensitiveContains(query) }
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
        metadata
        variablePanel
        if !set.note.isEmpty { notePanel }
      }
      .frame(maxWidth: 920, alignment: .leading)
      .padding(AppMetrics.pageHorizontalPadding)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(AppColor.canvas)
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
    HStack(alignment: .top, spacing: 20) {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 9) {
          Text(set.name)
            .font(.system(size: 24, weight: .semibold))
          AppStatusBadge(text: "Encrypted", tone: .success)
        }
        Text("Manage values, inspect revisions, or export a guarded plaintext copy.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 20)
      HStack(spacing: 8) {
        Button("Edit", systemImage: "pencil") { showingEditor = true }
          .buttonStyle(.envSecondary)
          .keyboardShortcut("e", modifiers: .command)
        actionsMenu
      }
    }
  }

  private var actionsMenu: some View {
    Menu {
      Button("Revision History", systemImage: "clock.arrow.circlepath") {
        showingRevisions = true
      }
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
      Image(systemName: "ellipsis")
        .frame(width: AppMetrics.controlHeight, height: AppMetrics.controlHeight)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cornerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: AppMetrics.cornerRadius)
            .stroke(AppColor.border, lineWidth: AppMetrics.hairline)
        }
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("More Actions")
  }

  private var metadata: some View {
    HStack(spacing: 0) {
      metadataItem("Variables", value: "\(set.variables.count)")
      AppDivider(.vertical).frame(height: 42)
      metadataItem("Revision", value: "\(set.revision)")
      AppDivider(.vertical).frame(height: 42)
      metadataItem("Updated", value: set.updatedAt.formatted(date: .abbreviated, time: .shortened))
    }
    .padding(.vertical, 12)
    .envStorePanel()
  }

  private func metadataItem(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title.uppercased())
        .font(.system(size: 9, weight: .semibold))
        .tracking(0.4)
        .foregroundStyle(.tertiary)
      Text(value)
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
  }

  private var variablePanel: some View {
    VStack(spacing: 0) {
      AppSectionHeader(
        "Environment variables",
        detail: "\(set.variables.count) total"
      ) {
        Text("Values hidden by default")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 16)
      .frame(height: 42)
      .background(AppColor.subtle)

      AppDivider()

      if set.variables.isEmpty {
        AppEmptyState(
          title: "No variables",
          message: "Edit this set to add values or paste .env content.",
          symbol: "text.badge.plus"
        )
        .frame(maxWidth: .infinity, minHeight: 190)
      } else {
        ForEach(Array(set.variables.enumerated()), id: \.element.id) { index, variable in
          VariableRow(
            variable: variable,
            revealed: revealedIDs.contains(variable.id),
            onReveal: { toggleReveal(variable) },
            onCopy: { copy(variable) }
          )
          if index < set.variables.count - 1 {
            AppDivider()
          }
        }
      }
    }
    .envStorePanel()
  }

  private var notePanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      AppSectionHeader("Note") { EmptyView() }
      Text(set.note)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding(16)
    .envStorePanel()
  }

  private func toggleReveal(_ variable: EnvironmentVariable) {
    if revealedIDs.remove(variable.id) != nil { return }
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
    panel.nameFieldStringValue = "\(set.name.replacingOccurrences(of: " ", with: "-")).env"
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
        exportError =
          "EnvStore could not create a new 0600 file at that location. Existing files are never overwritten."
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
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 7) {
          Text(variable.key)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .textSelection(.enabled)
          if EnvironmentKeyRisk.classify(variable.key) != nil {
            AppStatusBadge(text: "Sensitive", tone: .warning)
              .accessibilityLabel("High-risk environment key")
          }
        }
        Text(revealed ? variable.value : "••••••••••••••••")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(revealed ? .primary : .tertiary)
          .lineLimit(revealed ? 4 : 1)
          .textSelection(.enabled)
          .accessibilityLabel(revealed ? "Value \(variable.value)" : "Value hidden")
      }
      Spacer(minLength: 12)
      Button(action: onReveal) {
        Image(systemName: revealed ? "eye.slash" : "eye")
      }
      .buttonStyle(.envIcon)
      .accessibilityLabel(
        revealed ? "Hide \(variable.key)" : "Reveal \(variable.key) for 15 seconds")
      Button(action: onCopy) {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.envIcon)
      .accessibilityLabel("Copy \(variable.key); clipboard clears after 30 seconds")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
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
        SHA256.hash(data: Data(current.utf8)) == digest
      else {
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
    alert.messageText =
      synchronized
      ? "Export plaintext to a synchronized location?"
      : "Export plaintext .env file?"
    alert.informativeText =
      synchronized
      ? "This location may upload the file. The export is unencrypted and can be indexed, backed up, or read by other processes."
      : "The export is unencrypted and can be indexed, backed up, or read by other processes."
    alert.addButton(withTitle: "Export")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}
