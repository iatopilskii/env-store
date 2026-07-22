# Security policy

## Reporting

Do not open a public issue containing a vulnerability, vault database, process output, environment key, secret value, path, or command that may reveal sensitive data. Use the repository’s private security-advisory channel when available.

## Invariants

- Secret values never appear in broker metadata, CLI status JSON, grants, activity records, notifications, or logs.
- The CLI sends structured argv and never constructs `/bin/sh -c` implicitly.
- Existing vaults never create a replacement root key when the Keychain item is missing.
- Every encrypted record authenticates its vault ID, record ID, record kind, crypto version, and schema version.
- Provisioned builds use Data Protection Keychain with `WhenUnlockedThisDeviceOnly`, disabled synchronization, and `userPresence`.
- Ad-hoc previews use the local login Keychain default ACL and require a fresh LocalAuthentication device-owner check before each root-key read.
- Plaintext exports create only a new mode-`0600` file and never target stdout.
- Release entitlements do not include `get-task-allow`.
- Setup receives no vault secret, environment value, Apple Account credential, or macOS password.
- Agent setup invokes a pinned `skills` package with telemetry disabled, structured argv, a controlled environment, and bounded non-persistent output.
- Native skill installation writes only below the current user's home directory, refuses symlink traversal, and never replaces an unowned skill directory.
- The non-secret installation manifest contains only component versions, methods, timestamps, and destination paths.

## Out of scope

A process that receives injected values can disclose them. A fully compromised same-user account, EnvStore broker, operating-system kernel, or physical device outside the unlocked session is outside the threat model. Memory locking and zeroization reduce accidental exposure but are not a defense against a compromised process or kernel.

Unsigned previews do not provide a stable production code identity. Their LocalAuthentication check and file-based Keychain ACL are separate controls, and a rebuilt binary may require an additional Keychain permission prompt. Verify release checksums and prefer notarized Developer ID builds once they are available.
