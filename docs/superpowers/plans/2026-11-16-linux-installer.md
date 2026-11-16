# Linux Installer Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Support official Ubuntu/Debian Claude Desktop with the existing standalone settings interface.
**Architecture:** Keep the macOS backend unchanged; dispatch Linux operations to a separate backend. Reuse rooted file operations, lock cleanup, payload generation, and feature preferences.
**Tech Stack:** Go, Bubble Tea, shell bootstrap, freedesktop desktop entries, apt.
**Spec:** docs/superpowers/specs/2026-11-16-linux-installer-design.md

## Global Constraints
- No vendor file changes, automatic app quitting, conversation access, or runtime Node dependency.
- English interface; three independent feature flags; Linux amd64/arm64.
- Explicit consent before prerequisite installation. Preserve foreign files.

## Review Focus
- Existing custom launchers: reject conflicts rather than overwrite.
- Interrupted file writes: rollback and release lock.
- Spaces and special characters in paths: desktop-entry quoting must preserve arguments.
- Active Claude: refuse writes and preserve drafts.
- Unsupported vendor hook/package: report incompatibility before changing files.

### Task 1: Verify vendor compatibility and add Linux backend
- [x] Inspect the official .deb without executing it; identify executable, desktop ID and extension hook.
- [x] Write failing tests for Linux detection, all feature combinations, repeat install, foreign files, app-open guard, rollback, and quoting.
- [x] Implement Linux paths, compatibility checks, owned launcher, and transactional install.
- [x] Run Go tests and vet.

### Task 2: Portable interface and bootstrap
- [x] Add failing tests for Linux interface labels and bootstrap architecture/path selection.
- [x] Implement platform labels, explicit Linux prerequisite consent, Linux download/checksum paths, and release builds.
- [x] Test both Mac and Linux behavior and cross-compile all four binaries.

### Task 3: Verification and documentation
- [x] Run Node tests, font checks, both Lua suites, Go race/vet and Linux execution tests.
- [x] Request an independent review and resolve material issues.
- [x] Document platform support and graphical validation limits; publish only after checks pass.

## Execution record

The user approved the official Ubuntu/Debian target and requested implementation in the existing session. Existing prompt-preview revision 9 changes were preserved and included in version 1.2.0.

Independent review identified vendor source selection, additional keys in the keyring, and cross-filesystem extension backups. Vendor metadata is now isolated for package download, extra primary keys are rejected, and backups are stored beside the extension. Ubuntu tmpfs tests reproduced the cross-device failure before the fix and passed afterward. Applying tweaks uses user files only; prerequisite installation alone asks PolicyKit for system permission. Absolute XDG paths outside the user's home remain explicitly unsupported.

Linux graphical acceptance and a live PolicyKit dialog remain unverified and are documented as such. Container tests are not live Claude tests.
