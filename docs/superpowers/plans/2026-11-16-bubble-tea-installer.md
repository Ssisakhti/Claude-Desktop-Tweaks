# Bubble Tea installer

Goal: Ship an English Nord terminal installer and settings manager as one standalone executable, with no end-user Node or Go dependency.
Spec: User explicitly selected Bubble Tea and requested modern UI, one-command installation, prerequisite consent, independent font/theme/RTL switches, and later changes.
Architecture: Bubble Tea 2 + Lip Gloss 2, native Go installer and safe macOS operations. Embed a build-time generated JavaScript controller template and licenses. End users never run Node; Node remains a maintainer tool for the existing extension source.

## Design
A responsive Nord dashboard with numbered steps, three feature cards, keyboard switches, selection summary, explicit review before apply, progress and recovery screens. Frost marks focus; Snow Storm shows text; Aurora green/yellow/red marks success/warnings/errors. Use textual state labels alongside colors. English throughout. Narrow terminals use a compact layout. No font claim for terminal text: Estedad applies inside Claude.

## Constraints
No Claude bundle modification, automatic quit, chat access, unsigned GUI packaging, or security bypass. Block installation while Claude is running. Existing startup ownership, backups, rollback and Hammerspoon migration remain protected. Downloads require consent. Download Claude only from the official endpoint and verify its vendor signature. Existing app is preserved.

## Tasks
- [x] Generate and embed controller template and licenses; verify all eight configurations.
- [x] Port transactional installer to Go; test ownership, symlinks, rollback, lock, closed-app guard, migration, preferences.
- [x] Implement consent-based prerequisite installation and read-only checks.
- [x] Implement responsive Bubble Tea dashboard and test keyboard flows, unsaved state, errors, busy exits.
- [x] Build standalone macOS arm64/amd64 binaries; add verified bootstrap and release workflow.
- [x] Run Go and repository suites, PTY smoke checks and independent review. Document publication status accurately.

## Interfaces and ledger
Feature flags are shared by the Go receipt/UI and the JavaScript controller. Preserve JSON names font/theme/rtl. Existing Node receipt fields remain compatible.
The source archive is a maintainer input, not an end-user runtime. Public installation downloads a prebuilt binary plus SHA-256 checksum from the same GitHub release.
The current checkout preserves earlier style changes. The implementation branch is codex/bubble-tea-installer.


## Verification and review
- All eight payload variants reproduce the shared extension source.
- 178 JavaScript tests, variable font verification, Go tests with the race detector, Go vet, and both Lua suites passed.
- A real PTY read the installed settings, navigated check/features/review, blocked apply while Claude was open, and exited without installation.
- Independent review found signal shutdown and narrow-window discard bugs. Both were reproduced and fixed. A subprocess SIGTERM regression and tracked session prove cleanup completes before exit, including terminal failure shutdown. The original signal behavior fails that regression.
- Preserve formatted legacy LaunchAgents and CRLF-adjacent blank lines; regression tests failed before the compatibility corrections and passed afterward.
- Minor deferred: a disk I/O failure during exclusive lock-file creation may leave a partial lock. Recovery preserves the lock and backups for inspection; this limitation is documented.
- User explicitly approved publishing source and standalone release assets in the existing GitHub repository.

- Publication preflight: Linux CI passed. macOS jobs were cancelled before running because macos-14 was retired on 2026-11-02; migrate all workflows to the supported macos-15 image and verify again before tagging.
