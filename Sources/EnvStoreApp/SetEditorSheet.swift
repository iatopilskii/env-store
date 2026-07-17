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
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          metadataFields
          variablesSection
          if let localError {
            Label(localError, systemImage: "exclamationmark.circle")
              .font(.callout)
              .foregroundStyle(.red)
          }
        }
        .padding(24)
      }
      Divider()
      footer
    }
    .frame(width: 760, height: 620)
    .sheet(isPresented: $showingDotenvInput) {
      DotenvInputSheet(existing: variables) { parsed in
        variables = parsed
      }
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(isEditing ? "Edit Set" : "New Environment Set")
          .font(.headline)
        Text("Values remain local and encrypted at rest.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
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

  private var metadataFields: some View {
    VStack(alignment: .leading, spacing: 14) {
      LabeledContent("Name") {
        TextField("Development", text: $name)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 460)
      }
      LabeledContent("Note") {
        TextField("Optional context; never put a secret here", text: $note)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 460)
      }
    }
  }

  private var variablesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("VARIABLES")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer()
        Button("Paste or Import .env…", systemImage: "doc.text") {
          showingDotenvInput = true
        }
        Button("Add Variable", systemImage: "plus") {
          variables.append(EnvironmentVariable(key: "", value: ""))
        }
      }

      VStack(spacing: 0) {
        if variables.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "text.badge.plus")
            Text("Paste a .env file or add a variable.")
          }
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120)
        } else {
          ForEach(Array(variables.enumerated()), id: \.element.id) { index, variable in
            HStack(spacing: 10) {
              TextField(
                "KEY",
                text: binding(for: variable.id, keyPath: \.key)
              )
              .font(.system(.body, design: .monospaced))
              .textFieldStyle(.plain)
              .accessibilityLabel("Variable name")
              Divider().frame(height: 22)
              SecureField(
                "Value",
                text: binding(for: variable.id, keyPath: \.value)
              )
              .font(.system(.body, design: .monospaced))
              .textFieldStyle(.plain)
              .accessibilityLabel("Value for \(variable.key)")
              Button {
                variables.removeAll { $0.id == variable.id }
              } label: {
                Image(systemName: "minus.circle")
                  .frame(width: 28, height: 28)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Remove \(variable.key.isEmpty ? "variable" : variable.key)")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            if index < variables.count - 1 { Divider() }
          }
        }
      }
      .envStorePanel()
    }
  }

  private var footer: some View {
    HStack {
      Text("⌘↩ saves")
        .font(.caption)
        .foregroundStyle(.tertiary)
      Spacer()
      Button("Cancel") { dismiss() }
      Button(isSaving ? "Saving…" : "Save") { submit() }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(isSaving)
    }
    .padding(16)
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
