# EnvStore

EnvStore is a local-only native macOS vault for named environment-variable sets. It injects one selected set into an exact child command through a per-user broker, without returning plaintext values to the CLI or an agent.

## Current preview

- Native SwiftUI manager with System, Light, and Dark themes
- Touch ID or macOS login-password gating through LocalAuthentication
- Automatic Keychain backend: local login Keychain for ad-hoc previews, Data Protection Keychain for provisioned builds
- AES-256-GCM envelope encryption with per-set keys and per-value ciphertext
- Encrypted SQLite persistence, bounded set revisions, project bindings, and command profiles
- Vercel-style dotenv paste preview, deterministic non-evaluating parser, file import, and explicit plaintext export
- Exact `posix_spawn` execution, stable JSON errors, short-lived in-memory grants, and strict executable digests
- Versioned Codex-compatible agent skill under `skills/envstore`
- Automatic agent-skill installation through pinned `npx skills`, with a native no-Node fallback
- Unsigned local `.app`, `.dmg`, CLI `.tar.gz`, skill `.tar.gz`, and SHA-256 packaging

EnvStore never syncs to iCloud and never receives an Apple ID password. macOS owns every biometric/password prompt.

## Requirements

- macOS 14 or later
- Swift 6.2 or later to build from source
- Xcode Command Line Tools

## Build and test

Run the complete automated suite and build the release artifacts:

```bash
swift test
scripts/package-release.sh
```

Artifacts appear in `dist/`. With no signing environment configured, the scripts create an ad-hoc-signed `EnvStore-X.Y.Z-unsigned.dmg` preview. A downloaded preview may require **System Settings > Privacy & Security > Open Anyway** once. Do not disable Gatekeeper globally.

To exercise the same flow an end user receives:

1. Open `dist/EnvStore-X.Y.Z-unsigned.dmg` and drag EnvStore to Applications.
2. Eject the DMG and open EnvStore from Applications.
3. Complete first-run setup and verify that CLI, broker, and agent skill report installed.
4. Unlock the vault, create a set named `Smoke Test`, and add the non-secret value `ENVSTORE_SMOKE=works`.
5. Check the broker and inject that set without printing its environment:

   ```bash
   envstore doctor
   envstore context
   envstore run --set "Smoke Test" -- /bin/zsh -c 'test "$ENVSTORE_SMOKE" = "works"' && echo "Injection OK"
   ```

6. Paste a multi-line dotenv sample into the set editor, then test file import and export using non-secret values. Confirm the exported file has mode `0600` and delete it when finished.
7. Lock the vault and repeat unlock and command execution with Touch ID and with the macOS-password fallback.

Never use `env`, `printenv`, or shell tracing for a smoke test with real secrets. Quarantine, Gatekeeper, and Login Items approval must be verified manually on a physical Mac using a DMG downloaded from GitHub; a locally built file does not reproduce the complete download path.

Apple requires a provisioned application identifier for the macOS Data Protection Keychain. The ad-hoc preview therefore stores its root key in the local login Keychain, whose default ACL trusts the creating app, and performs fresh device-owner authentication before every read. This preview backend never synchronizes data, but its authentication and Keychain ACL are separate checks rather than one atomic `userPresence` policy. Rebuilt ad-hoc binaries can trigger an additional macOS Keychain access prompt because they have no stable code identity.

## Install from GitHub Release

### What to download

Open the [EnvStore Releases page](https://github.com/iatopilskii/env-store/releases) and download:

- `EnvStore-X.Y.Z-unsigned.dmg` — the complete app and the recommended download for normal installation;
- `SHA256SUMS-X.Y.Z.txt` — optional checksums for verifying the download.

The `envstore-cli-*.tar.gz` and `envstore-agent-skill-*.tar.gz` assets are for manual or advanced setup. You do not need them when installing the DMG: the app already bundles and installs both components.

### Installation

1. Double-click `EnvStore-X.Y.Z-unsigned.dmg`.
2. Drag **EnvStore** into the **Applications** folder shown in the DMG window.
3. Eject the EnvStore disk image. Do not run the app directly from the mounted DMG because its background broker must remain at a stable installed path.
4. Open **EnvStore** from `/Applications`.
5. This preview has no Developer ID signature or notarization. If macOS blocks the first launch, open **System Settings → Privacy & Security**, find the EnvStore warning, click **Open Anyway**, and confirm. Do this only for a DMG downloaded from this repository. Never disable Gatekeeper globally.
6. Complete the first-run setup in EnvStore. The setup:
   - copies the CLI to `~/.local/bin/envstore`;
   - registers the per-user background broker through macOS Service Management;
   - installs the bundled EnvStore skill for detected agents.
7. If macOS asks whether EnvStore may run in the background, allow it. If the app reports that `~/.local/bin` is missing from the terminal `PATH`, copy its suggested zsh command, run it once in Terminal, and open a new terminal window.

Verify the installation in a new terminal:

```bash
envstore --version
envstore doctor
```

`envstore doctor` should report that the broker is available. After creating and unlocking a vault, it should also report that the vault is available.

To verify a downloaded DMG manually, calculate its checksum and compare it with the matching line in `SHA256SUMS-X.Y.Z.txt`:

```bash
shasum -a 256 EnvStore-X.Y.Z-unsigned.dmg
```

## Build and install from source

For a local source build:

```bash
scripts/build-macos-app.sh
scripts/install-local.sh
open dist/EnvStore.app
```

The installer places the CLI at `~/.local/bin/envstore`, registers `dev.envstore.broker` as a per-user LaunchAgent, and installs the same bundled agent skill as the GUI setup. Add `~/.local/bin` to `PATH` if needed. The skill also checks that absolute CLI path when `envstore` is absent from `PATH`.

When the app detects that its inherited `PATH` does not contain `~/.local/bin`, onboarding and Settings show a copyable, idempotent zsh command. Run it once and open a new terminal. EnvStore never edits shell startup files automatically.

Agent installation first invokes the tested `skills@1.5.17` package with telemetry disabled, global automatic agent detection, and copy mode. If `npx` is absent, EnvStore copies the skill directly to detected agent directories. If `npx` exists but fails, the app remains usable and Settings shows a retry action and a copyable manual command:

```bash
DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx --yes skills@1.5.17 add /Applications/EnvStore.app/Contents/Resources/AgentSkills --skill envstore --global --copy --yes
```

EnvStore never replaces an existing agent-skill directory that it does not own.

## CLI

```text
envstore doctor [--json]
envstore context [--json]
envstore run [--set NAME] -- EXECUTABLE [ARG...]
envstore profile run NAME
envstore grant request --profile NAME [--ttl 5m] [--uses 1] [--wait]
envstore grant list [--json]
envstore grant revoke UUID
envstore setup install-agent-skill --source PATH [--version VERSION] [--force]
```

Without `--set`, `run` resolves the nearest linked project directory. A profile pins its project root, set, executable, exact arguments, grant defaults, and optional strict SHA-256 digest.

Agents can wait while macOS presents Touch ID/password to the human at the Mac. A successful scoped grant permits only the exact approved command until its TTL or use limit is exhausted. Grants disappear when the broker restarts and are never written to disk.

## Security boundary

EnvStore protects secrets at rest and controls when they reach a child process. An approved child can still read, print, persist, transmit, and pass its environment to descendants. Do not run untrusted commands with secrets.

Plaintext export is intentionally conspicuous: it requires a destination before authentication, warns about synchronized locations, creates only a new `0600` file with `O_EXCL`, and never writes to stdout.

See [SECURITY.md](SECURITY.md) and the full [design specification](docs/superpowers/specs/2026-07-17-envstore-design.md).

## Signing and GitHub releases

The CI workflow tests every push to `main` and every pull request. For the first unsigned preview, keep the application and packaging versions at `0.1.0`, commit all release changes, then create and push an annotated tag:

```bash
git tag -a v0.1.0 -m "EnvStore 0.1.0"
git push origin v0.1.0
```

The release workflow runs the tests, builds the DMG, CLI archive, agent-skill archive, and SHA-256 checksum file, then attaches them to a GitHub Release. With no Apple credentials it publishes `EnvStore-0.1.0-unsigned.dmg` as a prerelease. Before each later tag, update `EnvStoreCore.version` and use the same version for the build and tag.

Users download the unsigned DMG from the repository's Releases page, optionally verify it against `SHA256SUMS-X.Y.Z.txt`, drag EnvStore to Applications, and complete the first-run setup. Because this preview has no Developer ID signature or notarization, macOS may require the one-time **Privacy & Security > Open Anyway** action. The app then installs its user-scoped CLI, broker, and detected agent skills without administrator access. If the PATH notice appears, the user only needs to copy its command into Terminal once; agent skills can already use the CLI's absolute fallback path.

Later, configure these repository secrets after joining the Apple Developer Program:

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Developer ID distribution, notarization, and the production Data Protection Keychain backend require Apple Developer Program signing and provisioning. Production hardening must also give every key-unwrapping process a provisioned application identifier and migrate an existing preview key explicitly. Local development and ad-hoc previews do not require an account.

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/dev.envstore.broker"
rm ~/Library/LaunchAgents/dev.envstore.broker.plist
rm ~/.local/bin/envstore
```

Delete `~/Library/Application Support/EnvStore` only if you intentionally want to destroy the encrypted vault. Its Keychain root key is device-bound; deleting either side without a backup is irreversible.
