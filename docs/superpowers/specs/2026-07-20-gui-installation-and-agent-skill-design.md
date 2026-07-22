# EnvStore GUI installation and agent-skill design

Date: 2026-07-20
Status: Approved design

## 1. Goal

EnvStore must be installable from a GitHub Release without requiring the user to run terminal commands. The primary path is an unsigned DMG followed by an in-app first-run setup. The existing `scripts/install-local.sh` path remains supported for contributors and installs the same bundled agent skill.

The installation consists of four local components:

1. `EnvStore.app` in an Applications directory.
2. The `envstore` CLI in `~/.local/bin/envstore`.
3. The per-user broker through `SMAppService`.
4. The version-matched `envstore` agent skill for automatically detected agents.

## 2. Platform constraints

- No Developer ID or Apple Developer Program account is available initially.
- Gatekeeper therefore requires a one-time manual override through System Settings > Privacy & Security > Open Anyway. EnvStore must explain this honestly and must never recommend disabling Gatekeeper globally.
- An unsigned PKG is not the primary distribution format. Installer packages are also evaluated by Gatekeeper and do not remove the signing problem.
- Installation is user-scoped and requires no administrator privileges.
- The app never edits `.zshrc`, `.bashrc`, or another shell profile automatically.
- The app and installer never receive an Apple Account password or macOS login password.

Apple documents the unidentified-developer override in [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) and bundled launch-agent registration in [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice).

## 3. Distribution experience

The GitHub Release contains `EnvStore-X.Y.Z-unsigned.dmg`. Its Finder window contains `EnvStore.app`, an Applications alias, and a short drag-to-install instruction.

The user flow is:

1. Open the DMG and drag EnvStore to Applications.
2. Attempt to open EnvStore.
3. If Gatekeeper blocks it, use Privacy & Security > Open Anyway once.
4. EnvStore presents its first-run setup before the vault unlock screen.
5. Setup installs the CLI, registers the broker, and installs the agent skill.
6. Successful steps are not shown again for the same component version. Failed steps remain visible in Settings with remediation actions.

Moving or deleting the DMG after setup must not break the CLI or agent skill. Both are copied, never linked to the mounted image.

If EnvStore is launched directly from the mounted DMG, setup does not register the broker or copy resources from that transient path. It asks the user to drag the app to Applications and relaunch it there.

## 4. First-run setup UI

The setup is a native SwiftUI view with three status rows:

- Command-line tool
- Background broker
- Agent skill

Each row has `waiting`, `installing`, `installed`, `needs approval`, or `warning` state. Setup starts automatically. The user can continue to the vault when mandatory local components are ready; agent-skill failure is a warning and never makes the vault unusable.

Broker status comes from `SMAppService.status`. If macOS requires approval, the UI explains the reason and opens Login Items settings using the system API.

Agent-skill failure shows:

- `Agent skill was not installed`;
- a short non-sensitive reason;
- `Retry`;
- `Copy manual command` when `npx` exists;
- the bundled source and destination guidance when native installation could not complete.

Settings retains the same component status and recovery controls after onboarding.

## 5. Component architecture

A new focused setup module owns installation logic independently of SwiftUI:

- `InstallationCoordinator` runs steps and returns structured status.
- `CLIInstaller` copies the bundled CLI atomically to `~/.local/bin/envstore` with mode `0755`.
- `BrokerRegistrar` wraps `SMAppService` registration and status.
- `AgentSkillInstaller` selects the `npx` or native path.
- `AgentDetector` maps supported local-agent evidence to global skill destinations.
- `ProcessRunner` and filesystem abstractions make the behavior testable without changing the real home directory.

The app calls the setup module directly. The `envstore` executable exposes a narrow `setup install-agent-skill` command backed by the same module, and `scripts/install-local.sh` invokes that command after installing the CLI and broker. There is one implementation of skill installation.

The app bundle contains:

```text
EnvStore.app/Contents/
├── Library/LaunchAgents/dev.envstore.broker.plist
├── Library/LaunchServices/EnvStoreBroker
├── Resources/AgentSkills/envstore/...
└── SharedSupport/envstore
```

## 6. CLI and broker installation

The CLI is copied from `Contents/SharedSupport/envstore` to `~/.local/bin/envstore`. Setup creates `~/.local/bin` when absent and never changes shell startup files. The agent skill first tries `envstore` from `PATH` and then the stable absolute fallback `$HOME/.local/bin/envstore`.

After CLI installation, setup checks whether the inherited process `PATH` contains `~/.local/bin`. When it does not, onboarding and Settings show a non-blocking terminal-access notice with a copyable, idempotent zsh command that adds the directory to `~/.zshrc`. The notice explicitly asks the user to open a new terminal afterward and remains available until the user confirms that configuration is complete. This is advisory because a GUI app cannot reliably determine the effective configuration of every interactive shell without evaluating shell profiles; EnvStore never evaluates or edits them.

The app registers the broker from its own bundle using `SMAppService.agent(plistName:)`. The packaged LaunchAgent plist and helper executable are code-signature resources of the app bundle. The legacy `launchctl` path remains only for local development until the `SMAppService` path passes the complete physical-Mac smoke test.

Registration is idempotent. Setup never registers a root daemon or privileged helper.

## 7. Bundled agent skill

`skills/envstore` remains the repository source. The macOS app build copies that directory verbatim to `Contents/Resources/AgentSkills/envstore`. App, CLI, broker, and skill share the release version.

Packaging fails when any required skill file is missing:

- `SKILL.md`
- `agents/openai.yaml`
- `references/cli.md`
- `references/security.md`
- `evals/adversarial.json`

The release keeps the standalone skill archive for users who want manual inspection or installation.

## 8. Primary `npx skills` path

EnvStore prefers the official `vercel-labs/skills` CLI because it maintains current agent detection and global install locations. The initial pinned version is `skills@1.5.17`; future EnvStore releases may change it only after the automated and physical-Mac checks pass. `ProcessRunner` invokes `npx` directly with the following argv, where `resolvedAgentSkillsPath` is the absolute path resolved from the installed app bundle:

```text
["--yes", "skills@1.5.17", "add", resolvedAgentSkillsPath,
 "--skill", "envstore", "--global", "--copy", "--yes"]
```

No `--agent` option is supplied, so `skills` automatically selects detected agents. `--copy` prevents the installed skill from depending on the app or mounted DMG path.

The child environment is minimal and includes `HOME`, a controlled `PATH`, locale and temporary-directory values, plus `DISABLE_TELEMETRY=1` and `DO_NOT_TRACK=1`. EnvStore does not invoke a login shell and does not evaluate user shell profiles.

`npx` discovery checks the inherited `PATH` and a small versioned set of conventional user locations, including Homebrew, Volta, asdf, fnm, and nvm installations. Paths are passed as argv, never concatenated into a shell command.

The full child output is bounded in memory, never persisted, and not included in activity records. The UI reports only a safe summary.

The command format and flags follow the official [`vercel-labs/skills` documentation](https://github.com/vercel-labs/skills).

## 9. Native fallback without `npx`

Native fallback runs only when no usable `npx` executable is found. A present but failing `npx` produces a warning and manual retry command rather than silently changing installation semantics.

`AgentDetector` uses a versioned allowlist derived from the tested `vercel-labs/skills` release. A target is considered detected when at least one of its documented global configuration directory, CLI executable, or macOS application is present. The initial destination map is:

| Agent | Global skill root |
| --- | --- |
| Codex | `~/.codex/skills` |
| Claude Code | `~/.claude/skills` |
| Cursor | `~/.cursor/skills` |
| Gemini CLI | `~/.gemini/skills` |
| GitHub Copilot | `~/.copilot/skills` |
| OpenCode | `~/.config/opencode/skills` |
| Cline, Dexto, Kimi, Loaf, Warp, Zed | `~/.agents/skills` |

The map is release data, not scattered conditionals, so it can be reviewed and updated alongside the pinned `skills` CLI version.

For every detected target, EnvStore copies the bundled directory to the target's documented global destination as `envstore`. It uses a sibling staging directory, validates the staged `SKILL.md`, and atomically replaces only a previously EnvStore-managed installation. It does not follow a destination symlink and does not overwrite an unowned existing `envstore` directory.

Managed destinations and installed versions are recorded in a non-secret manifest under `~/Library/Application Support/EnvStore/`. If no agent is detected, EnvStore stores a canonical copy under `~/.agents/skills/envstore` and shows its location for manual connection.

Direct copies are intentional. They survive app relocation and avoid agent-specific symlink compatibility problems.

## 10. Versioning and idempotency

The bundled skill has the same SemVer as EnvStore. A successful setup records the installed component version in the installation manifest. First launch of a newer EnvStore version reruns only outdated steps.

The installer may safely run from both `scripts/install-local.sh` and the app. Concurrent setup attempts are serialized with a user-scoped lock. Interrupted copies leave either the previous complete version or the new complete version, never a partial destination.

An `npx` success records the version and method but does not assume that users cannot later remove a skill. Settings offers `Verify` and `Reinstall` actions.

## 11. Errors and recovery

Core app installation succeeds even when the agent skill cannot be installed.

Expected outcomes are:

- Missing `npx`: use native fallback.
- `npx` package/network failure: warn and show the exact manual command.
- No detected native target: install the canonical copy and show its path.
- Existing unowned skill directory: preserve it and warn.
- Permission or disk error: preserve the previous installation and show a safe reason.
- Broker requires approval: open Login Items settings on request.
- CLI destination is not writable: keep the bundled CLI usable and show its absolute path.

`scripts/install-local.sh` prints warnings to stderr but returns success when the app, CLI, and broker were installed. It prints the same manual skill command emitted by the setup module.

## 12. Security properties

- No secret or environment value participates in setup.
- The skill source comes from the sealed app bundle, not a mutable remote repository.
- The `skills` package version is pinned per EnvStore release.
- `skills` telemetry is disabled.
- External processes receive a minimal environment and structured argv.
- Native fallback writes only beneath the current user's home directory.
- Existing unowned agent instructions are never overwritten.
- Setup output is not stored in the vault, logs, activity, or analytics.
- Gatekeeper bypass instructions remain scoped to EnvStore and never weaken global settings.

## 13. Verification

### Automated tests

- `npx` discovery across controlled path fixtures.
- Exact executable, argv, and environment for the `skills add` call.
- Automatic-agent mode contains no `--agent` argument.
- Native detection and destination mapping in a temporary home.
- Atomic copy, managed update, unowned-directory preservation, and interruption recovery.
- Component-version idempotency and serialization.
- Safe warning and manual-command generation.
- Setup state transitions for success, approval, and warning.
- Package inspection for CLI, broker plist, broker executable, and complete bundled skill.
- `install-local.sh` smoke tests with fake `npx`, absent `npx`, and failing `npx`.

Automated tests never write to the developer's real agent directories.

### Physical Mac tests

1. Download the GitHub DMG so quarantine metadata is present.
2. Drag EnvStore to Applications.
3. Verify the documented Gatekeeper Open Anyway flow.
4. Complete first-run setup without Terminal.
5. Verify CLI copying and broker registration.
6. Verify `npx` auto-detection with at least Codex and one other agent.
7. Remove `npx` from discovery and verify native fallback.
8. Launch a safe command through the installed EnvStore skill and broker.
9. Upgrade to a newer build and verify idempotent component updates.

## 14. Acceptance criteria

1. A user can install and configure EnvStore from the DMG without opening Terminal.
2. The only unavoidable unsigned-build friction is the scoped Gatekeeper override and any macOS Login Items approval.
3. `scripts/install-local.sh` also installs the bundled skill automatically.
4. `npx skills add` is the primary skill installer and automatically detects agents.
5. Missing `npx` triggers native installation for detected agents.
6. Skill failure never prevents vault use and always provides actionable recovery.
7. Installed CLI and skill remain usable after the DMG is ejected.
8. No installer path weakens secret handling, Gatekeeper, or existing agent instructions.
9. When direct `envstore` command resolution may be unavailable, the GUI provides a safe manual PATH remediation without blocking agent-skill use.

## 15. Out of scope

- Eliminating Gatekeeper warnings without Developer ID.
- App Store distribution.
- A privileged system-wide CLI installation.
- Silent edits to user shell configuration.
- Automatic unsigned self-update.
