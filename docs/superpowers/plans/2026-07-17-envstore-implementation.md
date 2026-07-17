# EnvStore Implementation Plan

Design: `docs/superpowers/specs/2026-07-17-envstore-design.md`

Toolchain: Swift 6.3, Xcode 26.4, macOS 14 deployment target.

## Phase 1 — Workspace and core contracts

1. Create `Package.swift` with `EnvStoreCore`, `EnvStoreCrypto`, `EnvStoreStorage`, `EnvStoreIPC`, `envstore`, `EnvStoreBroker`, and `EnvStoreApp` targets.
2. Add shared domain models and stable error/JSON envelopes under `Sources/EnvStoreCore/`.
3. Implement the non-evaluating dotenv parser and serializer.
4. Add path normalization, nearest-project binding resolution, grant/profile matching, and dangerous-key detection.
5. Prove with `swift test --filter EnvStoreCoreTests`.

## Phase 2 — Cryptography and storage

1. Add Keychain-backed and in-memory root-key providers under `Sources/EnvStoreCrypto/`.
2. Implement AES-256-GCM envelope wrapping, set manifests, per-value records, AAD domains, and rotation.
3. Implement guarded byte buffers with explicit clearing.
4. Add SQLite schema, migrations, encrypted set CRUD, bindings, profiles, activity, revisions, and migration snapshots under `Sources/EnvStoreStorage/`.
5. Verify missing-key preservation, tag tampering, rotation, transaction rollback, and snapshot restore.
6. Prove with `swift test --filter EnvStoreCryptoTests` and `swift test --filter EnvStoreStorageTests`.

## Phase 3 — Broker, process execution, and CLI

1. Define versioned IPC messages and transport abstraction under `Sources/EnvStoreIPC/`.
2. Implement the macOS XPC transport and a deterministic in-process transport for tests.
3. Implement broker request validation, grant lifecycle, lock/sleep clearing, profile matching, and approval coordination.
4. Implement exact `posix_spawn`, absolute executable resolution, terminal descriptor forwarding, process groups, signal forwarding, and exit propagation.
5. Implement CLI commands: `run`, `profile run`, `grant request/list/revoke`, `context`, `doctor`, and project link/unlink.
6. Add CLI JSON fixtures and stable error-code tests.
7. Prove with `swift test --filter EnvStoreIPCTests`, `swift test --filter EnvStoreBrokerTests`, and command smoke tests.

## Phase 4 — Native application

1. Implement the SwiftUI application shell and lock state under `Sources/EnvStoreApp/`.
2. Build Sets, Projects, Profiles, Activity, Settings, bulk paste/diff, import/export, reveal/copy timeout, revision comparison, and approval views.
3. Implement System/Light/Dark themes using semantic tokens and the approved brand mark.
4. Add keyboard navigation, VoiceOver labels, contrast/reduced-motion behavior, destructive confirmations, and empty/error states.
5. Connect the UI to broker APIs; never add a GUI command runner.
6. Add model/view-model tests and render/smoke checks.

## Phase 5 — Agent skill and distribution

1. Use the `skill-creator` workflow to create `skills/envstore/SKILL.md`, references, and adversarial eval cases.
2. Add `scripts/build-macos-app.sh` to assemble the app, CLI, broker, plists, entitlements, resources, and AppIcon.
3. Add `scripts/build-macos-dmg.sh`, checksum generation, unsigned/signed modes, notarization hooks, and Sparkle-ready metadata.
4. Add GitHub Actions for tests, universal artifacts, skill archive, checksums, and conditional signing/notarization.
5. Add installation, CLI PATH, helper registration, unsigned-preview, security model, and uninstall documentation.

## Phase 6 — Completion audit

1. Run all Swift tests with strict concurrency and warnings treated as errors.
2. Run parser fuzz/property cases and crypto tamper fixtures.
3. Run CLI/broker smoke tests, process/signal tests, and a fresh vault workflow.
4. Build and launch the `.app`; inspect light/dark screens and approval flow on macOS.
5. Build the unsigned DMG and CLI/skill archives; verify contents and SHA-256 sums.
6. Audit every requirement and security invariant in the approved design against source, tests, and built artifacts.
7. Record unavoidable manual checks for Touch ID, screen lock, Developer ID, notarization, and Gatekeeper when credentials or physical interaction are unavailable.

## Commit boundaries

1. `chore: scaffold Swift workspace`
2. `feat: add dotenv parsing and domain policies`
3. `feat: add encrypted vault storage`
4. `feat: add broker and CLI execution`
5. `feat: add native EnvStore application`
6. `feat: add agent skill and release tooling`
7. `test: complete EnvStore verification matrix`

## Unresolved questions

None. Developer ID credentials are intentionally absent; unsigned preview behavior is specified.
