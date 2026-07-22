import AppKit
import EnvStoreCore
import SwiftUI

struct SetEditorSheet: View {
  enum Mode {
    case create
    case edit(EnvironmentSet)
  }

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var note: String
  @State private var variables: [EnvironmentVariable]
  @State private var showingDotenvInput = false
  @State private var isSaving = false
  @State private var localError: String?
  private let mode: Mode
  private let save: (EnvironmentSetDraft) async -> Bool

  init(mode: Mode, save: @escaping (EnvironmentSetDraft) async -> Bool) {
    self.mode = mode
    self.save = save
    switch mode {
    case .create:
      _name = State(initialValue: "")
      _note = State(initialValue: "")
      _variables = State(initialValue: [])
    case .edit(let set):
      _name = State(initialValue: set.name)
      _note = State(initialValue: set.note)
      _variables = State(initialValue: set.variables)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      AppSheetHeader(
        title: isEditing ? "Edit environment set" : "New environment set",
        subtitle: "Values stay local and are encrypted before they reach disk.",
        dismiss: dismiss.callAsFunction
      )
      AppDivider()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          metadataFields
          variablesSection
          if let localError {
            Label(localError, systemImage: "exclamationmark.circle")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(AppColor.danger)
          }
        }
        .padding(28)
      }
      .background(AppColor.canvas)
      AppDivider()
      footer
    }
    .frame(width: 780, height: 650)
    .background(AppColor.canvas)
    .sheet(isPresented: $showingDotenvInput) {
      DotenvInputSheet(existing: variables) { parsed in
        variables = parsed
      }
    }
  }

  private var metadataFields: some View {
    VStack(alignment: .leading, spacing: 16) {
      AppSectionHeader("Set details") { EmptyView() }
      VStack(spacing: 0) {
        HStack(alignment: .center, spacing: 20) {
          AppFieldLabel("Name", hint: "Used by the CLI and agent skill")
            .frame(width: 190, alignment: .leading)
          TextField("Development", text: $name)
            .envStoreField()
        }
        .padding(16)
        AppDivider()
        HStack(alignment: .center, spacing: 20) {
          AppFieldLabel("Note", hint: "Optional non-secret context")
            .frame(width: 190, alignment: .leading)
          TextField("Optional context; never put a secret here", text: $note)
            .envStoreField()
        }
        .padding(16)
      }
      .envStorePanel()
    }
  }

  private var variablesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        AppSectionHeader("Environment variables", detail: "\(variables.count) total") {
          EmptyView()
        }
        Spacer()
        Button("Paste or Import .env…", systemImage: "doc.text") {
          showingDotenvInput = true
        }
        .buttonStyle(.envSecondary)
        Button("Add Variable", systemImage: "plus") {
          variables.append(EnvironmentVariable(key: "", value: ""))
        }
        .buttonStyle(.envSecondary)
      }

      VStack(spacing: 0) {
        if variables.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "text.badge.plus")
              .font(.system(size: 18))
            Text("Paste a .env file or add your first variable.")
              .font(.system(size: 12))
          }
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 140)
        } else {
          ForEach(Array(variables.enumerated()), id: \.element.id) { index, variable in
            HStack(spacing: 12) {
              TextField(
                "KEY",
                text: binding(for: variable.id, keyPath: \.key)
              )
              .font(.system(size: 12, weight: .medium, design: .monospaced))
              .envStoreField()
              .accessibilityLabel("Variable name")
              SecureField(
                "Value",
                text: binding(for: variable.id, keyPath: \.value)
              )
              .font(.system(size: 12, design: .monospaced))
              .envStoreField()
              .accessibilityLabel("Value for \(variable.key)")
              Button {
                variables.removeAll { $0.id == variable.id }
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.envIcon)
              .accessibilityLabel("Remove \(variable.key.isEmpty ? "variable" : variable.key)")
            }
            .padding(12)
            if index < variables.count - 1 { AppDivider() }
          }
        }
      }
      .envStorePanel()
    }
  }

  private var footer: some View {
    HStack {
      Label("Encrypted locally before storage", systemImage: "lock.shield")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Spacer()
      Button("Cancel") { dismiss() }
        .buttonStyle(.envSecondary)
      Button(isSaving ? "Saving…" : "Save") { submit() }
        .buttonStyle(.envPrimary)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(isSaving)
    }
    .padding(.horizontal, 20)
    .frame(height: 64)
    .background(AppColor.surface)
  }

  private var isEditing: Bool {
    if case .edit = mode { true } else { false }
  }

  private func binding(
    for id: UUID,
    keyPath: WritableKeyPath<MutableVariable, String>
  ) -> Binding<String> {
    Binding(
      get: {
        guard let variable = variables.first(where: { $0.id == id }) else { return "" }
        return keyPath == \MutableVariable.key ? variable.key : variable.value
      },
      set: { newValue in
        guard let index = variables.firstIndex(where: { $0.id == id }) else { return }
        let current = variables[index]
        if keyPath == \MutableVariable.key {
          variables[index] = EnvironmentVariable(
            id: current.id, key: newValue, value: current.value)
        } else {
          variables[index] = EnvironmentVariable(id: current.id, key: current.key, value: newValue)
        }
      }
    )
  }

  private func submit() {
    let draft = EnvironmentSetDraft(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      note: note,
      variables: variables
    )
    do {
      try draft.validate()
      localError = nil
    } catch {
      localError = validationMessage(error)
      return
    }
    isSaving = true
    Task {
      let didSave = await save(draft)
      isSaving = false
      if didSave {
        dismiss()
      }
    }
  }

  private func validationMessage(_ error: Error) -> String {
    switch error {
    case EnvironmentSetValidationError.emptyName: "Enter a set name."
    case EnvironmentSetValidationError.duplicateVariableKey(let key):
      "\(key) appears more than once."
    case EnvironmentSetValidationError.invalidVariableKey(let key):
      "\(key.isEmpty ? "An empty key" : key) is invalid."
    case EnvironmentSetValidationError.nullByte(let key): "\(key) contains an unsupported NUL byte."
    default: "Review the set and try again."
    }
  }
}

private struct MutableVariable {
  var key: String
  var value: String
}
