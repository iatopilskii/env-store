import Foundation
import Testing

@testable import EnvStoreSetup

struct InstallationTests {
  @Test
  func shellPathAdvisorRecognizesExactCLIDirectory() {
    let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
    let advisor = ShellPathAdvisor(
      homeDirectory: home,
      pathEnvironment: "/usr/bin:/Users/example/.local/bin:/bin"
    )

    #expect(advisor.isCLIDirectoryInPath)
    #expect(!advisor.shouldShowNotice)
  }

  @Test
  func shellPathAdvisorRejectsTextualPrefixAndBuildsPortableCommand() {
    let home = URL(filePath: "/Users/private-name", directoryHint: .isDirectory)
    let advisor = ShellPathAdvisor(
      homeDirectory: home,
      pathEnvironment: "/usr/bin:/Users/private-name/.local/bin-tools"
    )

    #expect(!advisor.isCLIDirectoryInPath)
    #expect(advisor.shouldShowNotice)
    #expect(advisor.zshSetupCommand.contains("$HOME/.zshrc"))
    #expect(advisor.zshSetupCommand.contains("$HOME/.local/bin"))
    #expect(!advisor.zshSetupCommand.contains("private-name"))
  }

  @Test
  func invokesPinnedSkillsCLIWithAutomaticAgentDetection() throws {
    let fixture = try SetupFixture()
    let npx = try fixture.makeExecutable(relativePath: "bin/npx")
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, output: "installed"))
    let installer = fixture.agentSkillInstaller(
      path: npx.deletingLastPathComponent().path,
      processRunner: runner
    )

    let result = try installer.install()
    let invocation = try #require(runner.invocations.first)

    #expect(result.state == .installed)
    #expect(result.method == .npx)
    #expect(invocation.executableURL == npx)
    #expect(
      invocation.arguments == [
        "--yes", "skills@1.5.17", "add", fixture.agentSkillsRoot.path,
        "--skill", "envstore", "--global", "--copy", "--yes",
      ]
    )
    #expect(!invocation.arguments.contains("--agent"))
    #expect(invocation.environment["DISABLE_TELEMETRY"] == "1")
    #expect(invocation.environment["DO_NOT_TRACK"] == "1")
    #expect(invocation.environment["HOME"] == fixture.home.path)
  }

  @Test
  func failingNpxReturnsManualRecoveryWithoutNativeFallback() throws {
    let fixture = try SetupFixture()
    let npx = try fixture.makeExecutable(relativePath: "bin/npx")
    try fixture.makeDirectory(relativePath: ".codex")
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 1, output: "network error"))
    let installer = fixture.agentSkillInstaller(
      path: npx.deletingLastPathComponent().path,
      processRunner: runner
    )

    let result = try installer.install()

    #expect(result.state == .warning)
    #expect(result.method == .npx)
    #expect(result.recoveryCommand?.contains("skills@1.5.17") == true)
    #expect(!FileManager.default.fileExists(atPath: fixture.codexSkill.path))
  }

  @Test
  func npxLaunchFailureAlsoReturnsManualRecovery() throws {
    let fixture = try SetupFixture()
    let npx = try fixture.makeExecutable(relativePath: "bin/npx")
    let installer = fixture.agentSkillInstaller(
      path: npx.deletingLastPathComponent().path,
      processRunner: ThrowingProcessRunner()
    )

    let result = try installer.install()

    #expect(result.state == .warning)
    #expect(result.method == .npx)
    #expect(result.recoveryCommand?.contains("skills@1.5.17") == true)
  }

  @Test
  func missingNpxCopiesSkillToEveryDetectedNativeDestination() throws {
    let fixture = try SetupFixture()
    try fixture.makeDirectory(relativePath: ".codex")
    try fixture.makeDirectory(relativePath: ".claude")
    let installer = fixture.agentSkillInstaller(path: "")

    let result = try installer.install()

    #expect(result.state == .installed)
    #expect(result.method == .native)
    #expect(
      FileManager.default.fileExists(atPath: fixture.codexSkill.appending(path: "SKILL.md").path))
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.home.appending(path: ".claude/skills/envstore/SKILL.md").path
      )
    )
  }

  @Test
  func missingNpxUsesCanonicalDestinationWhenNoAgentIsDetected() throws {
    let fixture = try SetupFixture()
    let installer = fixture.agentSkillInstaller(path: "")

    let result = try installer.install()

    #expect(result.state == .installed)
    #expect(result.installedLocations == [fixture.canonicalSkill])
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.canonicalSkill.appending(path: "SKILL.md").path))
  }

  @Test
  func nativeInstallerPreservesUnownedExistingSkill() throws {
    let fixture = try SetupFixture()
    try fixture.makeDirectory(relativePath: ".codex/skills/envstore")
    let existingSkill = fixture.codexSkill.appending(path: "SKILL.md")
    try Data("unowned".utf8).write(to: existingSkill)
    let installer = fixture.agentSkillInstaller(path: "")

    let result = try installer.install()

    #expect(result.state == .warning)
    #expect(try String(contentsOf: existingSkill, encoding: .utf8) == "unowned")
  }

  @Test
  func nativeInstallerUpdatesOnlyItsManagedCopy() throws {
    let fixture = try SetupFixture()
    try fixture.makeDirectory(relativePath: ".codex")
    let firstInstaller = fixture.agentSkillInstaller(path: "", version: "1.0.0")
    let firstResult = try firstInstaller.install()
    #expect(firstResult.state == .installed)

    let sourceSkill = fixture.agentSkillsRoot.appending(path: "envstore/SKILL.md")
    try Data("managed update".utf8).write(to: sourceSkill)
    let secondInstaller = fixture.agentSkillInstaller(path: "", version: "1.1.0")

    let secondResult = try secondInstaller.install()

    #expect(secondResult.state == .installed)
    #expect(
      try String(
        contentsOf: fixture.codexSkill.appending(path: "SKILL.md"),
        encoding: .utf8
      ) == "managed update"
    )
    #expect(
      try fixture.manifestStore.load().managedSkillDestinations[fixture.codexSkill.path]?.version
        == "1.1.0")
  }

  @Test
  func nativeInstallerRefusesSymlinkedAgentDirectory() throws {
    let fixture = try SetupFixture()
    let outside = try fixture.makeDirectory(relativePath: "outside")
    let codex = fixture.home.appending(path: ".codex")
    try FileManager.default.createSymbolicLink(at: codex, withDestinationURL: outside)
    let installer = fixture.agentSkillInstaller(path: "")

    let result = try installer.install()

    #expect(result.state == .warning)
    #expect(
      !FileManager.default.fileExists(atPath: outside.appending(path: "skills/envstore").path))
  }

  @Test
  func cliInstallerCopiesAtomicallyWithExecutablePermissions() throws {
    let fixture = try SetupFixture()
    let source = try fixture.makeExecutable(relativePath: "bundle/envstore")
    let installer = CLIInstaller(
      sourceURL: source,
      destinationURL: fixture.home.appending(path: ".local/bin/envstore"),
      homeDirectory: fixture.home,
      version: "1.2.3",
      manifestStore: fixture.manifestStore,
      lockURL: fixture.lockURL
    )

    let result = try installer.install()
    let attributes = try FileManager.default.attributesOfItem(
      atPath: result.installedLocations[0].path)
    let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue

    #expect(result.state == .installed)
    #expect(mode == 0o755)
  }

  @Test
  func statusDetectsADeletedNativeSkill() throws {
    let fixture = try SetupFixture()
    try fixture.makeDirectory(relativePath: ".codex")
    try fixture.makeDirectory(relativePath: ".claude")
    let sourceCLI = try fixture.makeExecutable(relativePath: "bundle/envstore")
    let engine = LocalInstallationEngine(
      configuration: fixture.configuration(bundledCLIURL: sourceCLI)
    )
    let installed = try engine.installAgentSkill()
    #expect(installed.installedLocations.count == 2)
    let location = try #require(installed.installedLocations.first)
    try FileManager.default.removeItem(at: location)

    let status = engine.agentSkillStatus()

    #expect(status.state == .waiting)
  }

  @Test @MainActor
  func coordinatorPublishesProgressAndRegistersBroker() async throws {
    let fixture = try SetupFixture()
    let sourceCLI = try fixture.makeExecutable(relativePath: "bundle/envstore")
    let registrar = FakeBrokerRegistrar(status: .notRegistered, statusAfterRegistration: .enabled)
    let coordinator = InstallationCoordinator(
      localEngine: LocalInstallationEngine(
        configuration: fixture.configuration(bundledCLIURL: sourceCLI)
      ),
      brokerRegistrar: registrar
    )
    var transitions: [ComponentInstallationResult] = []

    let report = await coordinator.install { transitions.append($0) }

    #expect(report.mandatoryComponentsReady)
    #expect(report.agentSkill.state == .installed)
    #expect(registrar.registrationCount == 1)
    #expect(transitions.map(\.state).contains(.installing))
    #expect(transitions.last?.component == .agentSkill)
  }

  @Test @MainActor
  func coordinatorKeepsApprovalAsAnExplicitBrokerState() async throws {
    let fixture = try SetupFixture()
    let sourceCLI = try fixture.makeExecutable(relativePath: "bundle/envstore")
    let registrar = FakeBrokerRegistrar(status: .requiresApproval)
    let coordinator = InstallationCoordinator(
      localEngine: LocalInstallationEngine(
        configuration: fixture.configuration(bundledCLIURL: sourceCLI)
      ),
      brokerRegistrar: registrar
    )

    let report = await coordinator.install { _ in }

    #expect(report.backgroundBroker.state == .needsApproval)
    #expect(!report.mandatoryComponentsReady)
    #expect(registrar.registrationCount == 0)
  }
}

@MainActor
private final class FakeBrokerRegistrar: BrokerRegistering {
  private(set) var registrationCount = 0
  private var currentStatus: BrokerRegistrationStatus
  private let statusAfterRegistration: BrokerRegistrationStatus

  var status: BrokerRegistrationStatus { currentStatus }

  init(
    status: BrokerRegistrationStatus,
    statusAfterRegistration: BrokerRegistrationStatus? = nil
  ) {
    currentStatus = status
    self.statusAfterRegistration = statusAfterRegistration ?? status
  }

  func register() throws {
    registrationCount += 1
    currentStatus = statusAfterRegistration
  }

  func openSystemSettings() {}
}

private final class RecordingProcessRunner: SetupProcessRunning, @unchecked Sendable {
  private let lock = NSLock()
  private let result: ProcessResult
  private var recordedInvocations: [ProcessInvocation] = []

  var invocations: [ProcessInvocation] {
    lock.withLock { recordedInvocations }
  }

  init(result: ProcessResult) {
    self.result = result
  }

  func run(_ invocation: ProcessInvocation) throws -> ProcessResult {
    lock.withLock { recordedInvocations.append(invocation) }
    return result
  }
}

private struct ThrowingProcessRunner: SetupProcessRunning {
  func run(_: ProcessInvocation) throws -> ProcessResult {
    throw EnvStoreSetupError.processLaunchFailed("test")
  }
}

private struct SetupFixture {
  let root: URL
  let home: URL
  let temporary: URL
  let applicationSupport: URL
  let agentSkillsRoot: URL
  let manifestStore: InstallationManifestStore
  let lockURL: URL

  var codexSkill: URL {
    home.appending(path: ".codex/skills/envstore", directoryHint: .isDirectory)
  }
  var canonicalSkill: URL {
    home.appending(path: ".agents/skills/envstore", directoryHint: .isDirectory)
  }

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "EnvStoreSetupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    home = root.appending(path: "home", directoryHint: .isDirectory)
    temporary = root.appending(path: "tmp", directoryHint: .isDirectory)
    applicationSupport = home.appending(
      path: "Library/Application Support/EnvStore",
      directoryHint: .isDirectory
    )
    agentSkillsRoot = root.appending(path: "AgentSkills", directoryHint: .isDirectory)
    let manifestURL = applicationSupport.appending(path: "installation.json")
    manifestStore = InstallationManifestStore(url: manifestURL)
    lockURL = applicationSupport.appending(path: "setup.lock")

    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: agentSkillsRoot.appending(path: "envstore"),
      withIntermediateDirectories: true
    )
    try Data("---\nname: envstore\ndescription: test\n---\n".utf8)
      .write(to: agentSkillsRoot.appending(path: "envstore/SKILL.md"))
  }

  func agentSkillInstaller(
    path: String,
    version: String = "1.2.3",
    processRunner: any SetupProcessRunning = RecordingProcessRunner(
      result: ProcessResult(exitCode: 0, output: "")
    )
  ) -> AgentSkillInstaller {
    AgentSkillInstaller(
      agentSkillsRoot: agentSkillsRoot,
      homeDirectory: home,
      temporaryDirectory: temporary,
      applicationDirectories: [],
      pathEnvironment: path,
      version: version,
      processRunner: processRunner,
      manifestStore: manifestStore,
      lockURL: lockURL
    )
  }

  func configuration(bundledCLIURL: URL) -> LocalSetupConfiguration {
    LocalSetupConfiguration(
      bundledCLIURL: bundledCLIURL,
      agentSkillsRoot: agentSkillsRoot,
      homeDirectory: home,
      applicationSupportDirectory: applicationSupport,
      temporaryDirectory: temporary,
      applicationDirectories: [],
      pathEnvironment: "",
      version: "1.2.3"
    )
  }

  @discardableResult
  func makeDirectory(relativePath: String) throws -> URL {
    let url = home.appending(path: relativePath, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func makeExecutable(relativePath: String) throws -> URL {
    let url = root.appending(path: relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }
}
