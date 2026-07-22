# EnvStore GUI Installation Implementation Plan

Design: `docs/superpowers/specs/2026-07-20-gui-installation-and-agent-skill-design.md`

Toolchain: Swift 6.3, macOS 14 deployment target, `skills@1.5.17`.

## Phase 1 — Setup contracts and test harness

1. Add an `EnvStoreSetup` library and `EnvStoreSetupTests` target.
2. Define component states, installation reports, bundle paths, manifest records, process results, and safe user-facing errors.
3. Inject filesystem, process, environment, and broker-registration boundaries so tests never touch the real home directory or launch services.
4. Add temporary-home fixtures and a recording process runner.
5. Prove the contracts with `swift test --filter EnvStoreSetupTests`.

## Phase 2 — CLI and agent-skill installers

1. Implement atomic CLI installation with mode `0755` and no shell-profile edits.
2. Implement deterministic `npx` discovery from controlled `PATH` plus conventional Homebrew, Volta, asdf, fnm, and nvm paths.
3. Execute `skills@1.5.17` with structured argv, global auto-detection, copy mode, noninteractive mode, disabled telemetry, bounded output, and no shell.
4. Implement the versioned native agent map and evidence detection.
5. Implement staged native copies, symlink refusal, ownership markers, managed upgrades, unowned-destination preservation, and canonical `~/.agents/skills` fallback.
6. Persist a non-secret installation manifest atomically under Application Support.
7. Add tests for exact argv/environment, absent and failing `npx`, detection, copy safety, idempotency, and interruption recovery.

## Phase 3 — Broker registration and coordinator

1. Add the bundled LaunchAgent plist using `BundleProgram`, pointing to `Contents/Library/LaunchServices/EnvStoreBroker`.
2. Wrap `SMAppService.agent(plistName:)` status, registration, and Login Items settings opening behind a main-actor registrar.
3. Implement `InstallationCoordinator` state transitions for CLI, broker, and skill.
4. Detect mounted-DMG and non-installed bundle locations before registering durable components.
5. Treat skill failure as a warning while keeping CLI and broker mandatory in packaged-app onboarding.
6. Add coordinator tests for success, approval, warnings, retries, and version idempotency.

## Phase 4 — CLI and native app integration

1. Add `envstore setup install-agent-skill --source PATH` using `EnvStoreSetup` and stable exit codes.
2. Add an app setup model that resolves installed bundle resources and runs installation away from the main actor.
3. Present first-run setup before vault unlock with per-component progress, approval, warning, retry, and recovery actions.
4. Add the same integration status and controls to Settings.
5. Preserve a development escape path for non-app SwiftPM runs without weakening packaged-app onboarding.
6. Detect inherited `PATH` coverage and show a non-blocking copyable zsh remediation without reading or editing shell profiles.
7. Add model tests for setup presentation and state mapping.

## Phase 5 — Packaging and local installation

1. Bundle `skills/envstore` under `Contents/Resources/AgentSkills/envstore` and validate every required file.
2. Bundle the LaunchAgent plist under `Contents/Library/LaunchAgents` and keep the helper under LaunchServices.
3. Add a DMG read-me file with drag-to-Applications and scoped Gatekeeper guidance.
4. Name unsigned artifacts explicitly while retaining signed-release compatibility.
5. Update `scripts/install-local.sh` to call the shared CLI skill installer, warn without failing core installation, and print a manual `npx` command on failure.
6. Keep the standalone skill archive and checksum coverage.

## Phase 6 — Documentation and verification

1. Update README installation, first-run, manual skill retry, PATH, Gatekeeper, and uninstall guidance.
2. Document setup security boundaries and non-secret manifest data in SECURITY.md.
3. Run `swift test`, strict release builds, and shell syntax checks.
4. Build the app and inspect required bundle files, permissions, plist validity, signatures, and embedded skill version.
5. Build and mount the unsigned DMG; verify the Finder payload and that copied CLI/skill resources do not depend on the mounted volume.
6. Record physical-only checks for Gatekeeper quarantine, Login Items approval, and agent discovery.

## Commit boundaries

1. `feat: add secure local setup engine`
2. `feat: add first-run installation flow`
3. `build: bundle setup resources and unsigned dmg`
4. `docs: document gui and agent setup`

## Unresolved questions

None.
