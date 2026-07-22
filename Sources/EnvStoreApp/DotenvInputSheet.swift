import AppKit
import EnvStoreCore
import SwiftUI

struct DotenvInputSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var input = ""
  @State private var importedFileName: String?
  @FocusState private var editorFocused: Bool
  let existing: [EnvironmentVariable]
  let apply: ([EnvironmentVariable]) -> Void

  private var result: DotenvParseResult {
    DotenvParser().parse(input)
  }

  var body: some View {
    VStack(spacing: 0) {
      AppSheetHeader(
        title: "Import .env content",
        subtitle: importedFileName
          ?? "Values are parsed literally; shell syntax is never evaluated.",
        dismiss: dismiss.callAsFunction
      )
      AppDivider()
      HStack(alignment: .top, spacing: 16) {
        editor
        preview
      }
      .padding(20)
      .background(AppColor.canvas)
      AppDivider()
      footer
    }
    .frame(width: 860, height: 620)
    .background(AppColor.canvas)
    .onAppear { editorFocused = true }
  }

  private var editor: some View {
    VStack(spacing: 0) {
      AppSectionHeader("Dotenv input") {
        Button("Import File…", systemImage: "folder") { importFile() }
          .buttonStyle(.envSecondary)
      }
      .padding(.horizontal, 14)
      .frame(height: 46)
      .background(AppColor.subtle)
      AppDivider()
      TextEditor(text: $input)
        .font(.system(size: 12, design: .monospaced))
        .focused($editorFocused)
        .scrollContentBackground(.hidden)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surface)
        .accessibilityLabel("Dotenv content")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .envStorePanel()
  }

  private var preview: some View {
    VStack(spacing: 0) {
      AppSectionHeader("Preview") {
        AppStatusBadge(
          text: result.errors.isEmpty
            ? "\(result.variables.count) parsed"
            : "\(result.errors.count) errors",
          tone: result.errors.isEmpty ? .success : .danger
        )
      }
      .padding(.horizontal, 14)
      .frame(height: 46)
      .background(AppColor.subtle)
      AppDivider()

      if result.variables.isEmpty && result.issues.isEmpty {
        AppEmptyState(
          title: "Live preview",
          message: "Parsed variables and validation issues appear here as you type.",
          symbol: "text.magnifyingglass"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(result.variables, id: \.key) { variable in
              HStack(spacing: 10) {
                Text(variable.key)
                  .font(.system(.callout, design: .monospaced, weight: .medium))
                Text(changeLabel(for: variable))
                  .font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 6)
                  .frame(height: 20)
                  .background(AppColor.subtle, in: Capsule())
                Spacer()
                Text("••••••••")
                  .font(.system(size: 10, design: .monospaced))
                  .foregroundStyle(.tertiary)
              }
              .padding(.horizontal, 14)
              .frame(minHeight: 38)
              AppDivider()
            }
            ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
              HStack {
                Image(
                  systemName: issue.severity == .error ? "xmark.circle" : "exclamationmark.triangle"
                )
                Text(
                  "Line \(issue.line): \(issue.code.rawValue.replacingOccurrences(of: "_", with: " "))"
                )
                Spacer()
              }
              .font(.system(size: 11))
              .foregroundStyle(issue.severity == .error ? AppColor.danger : .secondary)
              .padding(.horizontal, 14)
              .frame(minHeight: 36)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .envStorePanel()
  }

  private var footer: some View {
    HStack {
      Label("$ and command substitutions remain literal", systemImage: "shield")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Spacer()
      Button("Cancel") { dismiss() }
        .buttonStyle(.envSecondary)
      Button("Apply \(result.variables.count) Variables") {
        apply(mergedVariables())
        dismiss()
      }
      .buttonStyle(.envPrimary)
      .disabled(result.variables.isEmpty || !result.errors.isEmpty)
      .keyboardShortcut(.return, modifiers: .command)
    }
    .padding(.horizontal, 20)
    .frame(height: 64)
    .background(AppColor.surface)
  }

  private func changeLabel(for variable: DotenvVariable) -> String {
    guard let current = existing.first(where: { $0.key == variable.key }) else {
      return "ADDED"
    }
    return current.value == variable.value ? "UNCHANGED" : "UPDATED"
  }

  private func mergedVariables() -> [EnvironmentVariable] {
    result.variables.map { parsed in
      if let current = existing.first(where: { $0.key == parsed.key }) {
        return EnvironmentVariable(id: current.id, key: parsed.key, value: parsed.value)
      }
      return EnvironmentVariable(key: parsed.key, value: parsed.value)
    }
  }

  private func importFile() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message =
      "Select a dotenv text file. Nothing is stored until you apply the preview and save the set."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      input = try String(contentsOf: url, encoding: .utf8)
      importedFileName = url.lastPathComponent
    } catch {
      importedFileName = "Could not read that UTF-8 file"
    }
  }
}
