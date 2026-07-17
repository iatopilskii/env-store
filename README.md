# EnvStore

EnvStore is a local-only native macOS vault for named environment-variable sets. It injects one selected set into an exact child command through a per-user broker, without returning plaintext values to the CLI or an agent.

## Current preview

- Native SwiftUI manager with System, Light, and Dark themes
- Touch ID or macOS login-password gating through Data Protection Keychain `userPresence`
- AES-256-GCM envelope encryption with per-set keys and per-value ciphertext
- Encrypted SQLite persistence, bounded set revisions, project bindings, and command profiles
- Vercel-style dotenv paste preview, deterministic non-evaluating parser, file import, and explicit plaintext export
- Exact `posix_spawn` execution, stable JSON errors, short-lived in-memory grants, and strict executable digests
- Versioned Codex-compatible agent skill under `skills/envstore`
- Unsigned local `.app`, `.dmg`, CLI `.tar.gz`, skill `.tar.gz`, and SHA-256 packaging

EnvStore never syncs to iCloud and never receives an Apple ID password. macOS owns every biometric/password prompt.

## Requirements

- macOS 14 or later
- Swift 6.2 or later to build from source
- Xcode Command Line Tools

## Build and test

```bash
swift test
scripts/package-release.sh
```

Artifacts appear in `dist/`. With no signing environment configured, the scripts create an ad-hoc-signed development preview. To open an unsigned downloaded preview, use Finder’s **Open** context-menu action and confirm the warning. Do not disable Gatekeeper globally.

## Local installation

```bash
scripts/build-macos-app.sh
scripts/install-local.sh
open dist/EnvStore.app
```

The installer places the CLI at `~/.local/bin/envstore` and registers `dev.envstore.broker` as a per-user LaunchAgent. Add `~/.local/bin` to `PATH` if needed.

Install the agent skill explicitly:

```bash
mkdir -p ~/.codex/skills
cp -R skills/envstore ~/.codex/skills/envstore
```

## CLI

```text
envstore doctor [--json]
envstore context [--json]
envstore run [--set NAME] -- EXECUTABLE [ARG...]
envstore profile run NAME
envstore grant request --profile NAME [--ttl 5m] [--uses 1] [--wait]
envstore grant list [--json]
envstore grant revoke UUID
```

Without `--set`, `run` resolves the nearest linked project directory. A profile pins its project root, set, executable, exact arguments, grant defaults, and optional strict SHA-256 digest.

Agents can wait while macOS presents Touch ID/password to the human at the Mac. A successful scoped grant permits only the exact approved command until its TTL or use limit is exhausted. Grants disappear when the broker restarts and are never written to disk.

## Security boundary

EnvStore protects secrets at rest and controls when they reach a child process. An approved child can still read, print, persist, transmit, and pass its environment to descendants. Do not run untrusted commands with secrets.

Plaintext export is intentionally conspicuous: it requires a destination before authentication, warns about synchronized locations, creates only a new `0600` file with `O_EXCL`, and never writes to stdout.

See [SECURITY.md](SECURITY.md) and the full [design specification](docs/superpowers/specs/2026-07-17-envstore-design.md).

## Signing and GitHub releases

Pushing a `v*` tag runs tests and publishes the DMG, CLI archive, agent-skill archive, and checksum file to GitHub Releases. With no Apple credentials it publishes an unsigned preview. Later, configure these repository secrets without changing the architecture:

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Developer ID distribution and notarization require paid Apple Developer Program membership. Local development and ad-hoc previews do not.

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/dev.envstore.broker"
rm ~/Library/LaunchAgents/dev.envstore.broker.plist
rm ~/.local/bin/envstore
```

Delete `~/Library/Application Support/EnvStore` only if you intentionally want to destroy the encrypted vault. Its Keychain root key is device-bound; deleting either side without a backup is irreversible.
