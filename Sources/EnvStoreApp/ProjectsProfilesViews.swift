import AppKit
import CryptoKit
import EnvStoreAppCore
import EnvStoreCore
import SwiftUI

struct ProjectsView: View {
  @ObservedObject var model: VaultViewModel
  @State private var showingEditor = false

  var body: some View {
    VStack(spacing: 0) {
      AppPageHeader(
        "Projects",
        subtitle: "Resolve the nearest environment set from a working directory."
      ) {
        Button("Link Project", systemImage: "plus") { showingEditor = true }
          .buttonStyle(.envPrimary)
      }

      ScrollView {
        Group {
          if model.projectBindings.isEmpty {
            AppEmptyState(
              title: "No linked projects",
              message: "Link a directory to resolve its nearest environment set automatically.",
              symbol: "folder.badge.questionmark"
            )
            .frame(maxWidth: .infinity, minHeight: 340)
            .envStorePanel()
          } else {
            projectTable
          }
        }
        .frame(maxWidth: 980)
        .padding(AppMetrics.pageHorizontalPadding)
        .frame(maxWidth: .infinity)
      }
      .background(AppColor.canvas)
    }
    .sheet(isPresented: $showingEditor) {
      ProjectBindingEditor(model: model)
    }
  }

  private var projectTable: some View {
    VStack(spacing: 0) {
      HStack(spacing: 18) {
        Text("PROJECT DIRECTORY").frame(maxWidth: .infinity, alignment: .leading)
        Text("ENVIRONMENT SET").frame(width: 190, alignment: .leading)
        Color.clear.frame(width: 34)
      }
      .font(.system(size: 10, weight: .semibold))
      .tracking(0.35)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .frame(height: 42)
      .background(AppColor.subtle)

      AppDivider()

      ForEach(Array(model.projectBindings.enumerated()), id: \.element.id) { index, binding in
        HStack(spacing: 18) {
          HStack(spacing: 9) {
            Image(systemName: "folder")
              .foregroundStyle(.secondary)
            Text(binding.path)
              .font(.system(size: 11, design: .monospaced))
              .lineLimit(2)
              .textSelection(.enabled)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Text(model.sets.first(where: { $0.id == binding.setID })?.name ?? "Missing set")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 190, alignment: .leading)

          Button(role: .destructive) {
            Task { await model.deleteProjectBinding(id: binding.id) }
          } label: {
            Image(systemName: "trash").frame(width: 34, height: 34)
          }
          .buttonStyle(.plain)
          .foregroundStyle(AppColor.danger)
          .accessibilityLabel("Delete project binding for \(binding.path)")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        if index < model.projectBindings.count - 1 { AppDivider() }
      }
    }
    .envStorePanel()
  }
}

struct ProfilesView: View {
  @ObservedObject var model: VaultViewModel
  @State private var showingEditor = false

  var body: some View {
    VStack(spacing: 0) {
      AppPageHeader(
        "Command Profiles",
        subtitle: "Pin exact commands and grant limits for coding agents."
      ) {
        Button("New Profile", systemImage: "plus") { showingEditor = true }
          .buttonStyle(.envPrimary)
      }

      ScrollView {
        Group {
          if model.profiles.isEmpty {
            AppEmptyState(
              title: "No command profiles",
              message: "Create a profile to constrain executable paths, arguments, and grants.",
              symbol: "terminal"
            )
            .frame(maxWidth: .infinity, minHeight: 340)
            .envStorePanel()
          } else {
            profileTable
          }
        }
        .frame(maxWidth: 980)
        .padding(AppMetrics.pageHorizontalPadding)
        .frame(maxWidth: .infinity)
      }
      .background(AppColor.canvas)
    }
    .sheet(isPresented: $showingEditor) {
      CommandProfileEditor(model: model)
    }
  }

  private var profileTable: some View {
    VStack(spacing: 0) {
      HStack(spacing: 18) {
        Text("PROFILE").frame(width: 170, alignment: .leading)
        Text("EXACT COMMAND").frame(maxWidth: .infinity, alignment: .leading)
        Text("POLICY").frame(width: 170, alignment: .leading)
        Color.clear.frame(width: 34)
      }
      .font(.system(size: 10, weight: .semibold))
      .tracking(0.35)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .frame(height: 42)
      .background(AppColor.subtle)

      AppDivider()

      ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
        HStack(spacing: 18) {
          VStack(alignment: .leading, spacing: 5) {
            Text(profile.name)
              .font(.system(size: 12, weight: .medium))
            AppStatusBadge(
              text: profile.trustMode.rawValue,
              tone: profile.trustMode == .strict ? .success : .neutral
            )
          }
          .frame(width: 170, alignment: .leading)

          Text(([profile.executablePath] + profile.arguments).joined(separator: " "))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

          VStack(alignment: .leading, spacing: 4) {
            Text("TTL \(Int(profile.defaultTTL))s")
            Text("\(profile.defaultUses) permitted uses")
              .foregroundStyle(.secondary)
          }
          .font(.system(size: 11).monospacedDigit())
          .frame(width: 170, alignment: .leading)

          Button(role: .destructive) {
            Task { await model.deleteProfile(id: profile.id) }
          } label: {
            Image(systemName: "trash").frame(width: 34, height: 34)
          }
          .buttonStyle(.plain)
          .foregroundStyle(AppColor.danger)
          .accessibilityLabel("Delete profile \(profile.name)")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 68)
        if index < model.profiles.count - 1 { AppDivider() }
      }
    }
    .envStorePanel()
  }
}

private struct ProjectBindingEditor: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: VaultViewModel
  @State private var path = ""
  @State private var setID: UUID?

  var body: some View {
    VStack(spacing: 0) {
      AppSheetHeader(
        title: "Link project",
        subtitle: "The nearest linked ancestor wins during CLI resolution.",
        dismiss: dismiss.callAsFunction
      )
      AppDivider()

      VStack(alignment: .leading, spacing: 12) {
        AppSectionHeader("Project binding") { EmptyView() }
        VStack(spacing: 0) {
          AppFormRow("Directory", hint: "Stored encrypted in the local vault") {
            HStack(spacing: 8) {
              TextField("/path/to/project", text: $path)
                .font(.system(size: 11, design: .monospaced))
                .envStoreField()
              Button("Choose…") { chooseDirectory() }
                .buttonStyle(.envSecondary)
            }
          }
          AppDivider()
          AppFormRow("Environment set", hint: "Used for commands inside this directory") {
            Picker("Environment Set", selection: $setID) {
              Text("Select a set…").tag(nil as UUID?)
              ForEach(model.sets) { set in
                Text(set.name).tag(set.id as UUID?)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .envStoreControl()
          }
        }
        .envStorePanel()
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(AppColor.canvas)

      AppDivider()
      HStack {
        Label("Project paths are encrypted", systemImage: "lock")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { dismiss() }
          .buttonStyle(.envSecondary)
        Button("Link Project") { save() }
          .buttonStyle(.envPrimary)
          .disabled(path.isEmpty || setID == nil)
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 20)
      .frame(height: 64)
      .background(AppColor.surface)
    }
    .frame(width: 640, height: 390)
  }

  private func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    path = url.resolvingSymlinksInPath().standardizedFileURL.path
  }

  private func save() {
    guard let setID else { return }
    Task {
      if await model.saveProjectBinding(path: path, setID: setID) { dismiss() }
    }
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
      AppSheetHeader(
        title: "New command profile",
        subtitle: "Pin an exact command and the smallest useful grant policy.",
        dismiss: dismiss.callAsFunction
      )
      AppDivider()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          commandSection
          policySection
          if let localError {
            Label(localError, systemImage: "exclamationmark.circle")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(AppColor.danger)
          }
        }
        .padding(24)
      }
      .background(AppColor.canvas)

      AppDivider()
      HStack {
        Label("Strict mode rejects a changed executable", systemImage: "checkmark.shield")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { dismiss() }
          .buttonStyle(.envSecondary)
        Button("Save Profile") { submit() }
          .buttonStyle(.envPrimary)
          .disabled(name.isEmpty || setID == nil || projectRoot.isEmpty || executable.isEmpty)
          .keyboardShortcut(.return, modifiers: .command)
      }
      .padding(.horizontal, 20)
      .frame(height: 64)
      .background(AppColor.surface)
    }
    .frame(width: 720, height: 700)
  }

  private var commandSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      AppSectionHeader("Command") { EmptyView() }
      VStack(spacing: 0) {
        AppFormRow("Profile name", hint: "Stable name used by agents") {
          TextField("Deploy preview", text: $name).envStoreField()
        }
        AppDivider()
        AppFormRow("Environment set") {
          Picker("Environment set", selection: $setID) {
            Text("Select a set…").tag(nil as UUID?)
            ForEach(model.sets) { set in Text(set.name).tag(set.id as UUID?) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .envStoreControl()
        }
        AppDivider()
        AppFormRow("Project root", hint: "Working directory boundary") {
          pathField("/path/to/project", text: $projectRoot, directories: true)
        }
        AppDivider()
        AppFormRow("Executable", hint: "Absolute executable path") {
          pathField("/usr/bin/env", text: $executable, directories: false)
        }
        AppDivider()
        AppFormRow("Arguments", hint: "One argument per line") {
          TextField("Arguments", text: $argumentsText, axis: .vertical)
            .lineLimit(3...6)
            .font(.system(size: 11, design: .monospaced))
            .envStoreField()
        }
      }
      .envStorePanel()
    }
  }

  private var policySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      AppSectionHeader("Grant policy") { EmptyView() }
      VStack(spacing: 0) {
        AppFormRow("Trust mode", hint: "Strict pins the executable digest") {
          Picker("Trust mode", selection: $trustMode) {
            Text("Development").tag(ProfileTrustMode.development)
            Text("Strict").tag(ProfileTrustMode.strict)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(maxWidth: 280)
        }
        AppDivider()
        AppFormRow("Grant TTL", hint: "Expires automatically") {
          Stepper("\(ttl) seconds", value: $ttl, in: 30...3600, step: 30)
            .font(.system(size: 12).monospacedDigit())
        }
        AppDivider()
        AppFormRow("Maximum uses", hint: "Consumed after each matching run") {
          Stepper("\(uses) uses", value: $uses, in: 1...100)
            .font(.system(size: 12).monospacedDigit())
        }
      }
      .envStorePanel()
    }
  }

  private func pathField(
    _ placeholder: String,
    text: Binding<String>,
    directories: Bool
  ) -> some View {
    HStack(spacing: 8) {
      TextField(placeholder, text: text)
        .font(.system(size: 11, design: .monospaced))
        .envStoreField()
      Button("Choose…") {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text.wrappedValue = url.resolvingSymlinksInPath().standardizedFileURL.path
      }
      .buttonStyle(.envSecondary)
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
      arguments: argumentsText.split(separator: "\n", omittingEmptySubsequences: false).map(
        String.init),
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
