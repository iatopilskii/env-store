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
            header
            Divider()
            VStack(spacing: 16) {
                TextEditor(text: $input)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 210)
                    .envStorePanel()
                    .accessibilityLabel("Dotenv content")

                preview
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 760, height: 640)
        .onAppear { editorFocused = true }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Paste .env Content").font(.headline)
                Text(importedFileName ?? "Values are parsed literally; shell syntax is never evaluated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Import File…", systemImage: "folder") { importFile() }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PREVIEW")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(result.variables.count) parsed · \(result.errors.count) errors")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(result.errors.isEmpty ? Color.secondary : Color.red)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider()

            if result.variables.isEmpty && result.issues.isEmpty {
                Text("Parsed variables appear here as you type.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(result.variables, id: \.key) { variable in
                            HStack(spacing: 10) {
                                Text(variable.key)
                                    .font(.system(.callout, design: .monospaced, weight: .medium))
                                Text(changeLabel(for: variable))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                Spacer()
                                Text("••••••••")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            Divider().padding(.leading, 12)
                        }
                        ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                            HStack {
                                Image(systemName: issue.severity == .error ? "xmark.circle" : "exclamationmark.triangle")
                                Text("Line \(issue.line): \(issue.code.rawValue.replacingOccurrences(of: "_", with: " "))")
                                Spacer()
                            }
                            .font(.caption)
                            .foregroundStyle(issue.severity == .error ? .red : .secondary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .envStorePanel()
    }

    private var footer: some View {
        HStack {
            Label("$ and command substitutions remain literal", systemImage: "shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Apply \(result.variables.count) Variables") {
                apply(mergedVariables())
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(result.variables.isEmpty || !result.errors.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(16)
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
        panel.message = "Select a dotenv text file. Nothing is stored until you apply the preview and save the set."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            input = try String(contentsOf: url, encoding: .utf8)
            importedFileName = url.lastPathComponent
        } catch {
            importedFileName = "Could not read that UTF-8 file"
        }
    }
}
