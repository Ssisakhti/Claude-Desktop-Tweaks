# Changelog

## 1.1.1 — 2026-11-16

- Remove newly created files after failed writes, syncs, closes, or short writes, including failed installation-lock acquisition.
- Preserve existing locks and foreign file, directory, or symlink replacements. Use non-recursive cleanup after checking the captured file identity.
- Keep original I/O errors and report cleanup failures instead of treating every failure as another active installation.
- Add a real subprocess write-failure/retry regression plus ENOSPC, EIO, short-write, replacement, and permission-failure coverage.

## 1.1.0 — 2026-11-16

- Add a standalone English Bubble Tea 2 installer with a responsive Nord dashboard, independent font/theme/RTL switches, explicit review, and saved preferences.
- Port transactional extension installation to Go; include closed-app guards, startup ownership checks, locks, backups, rollback, and legacy migration.
- Download missing Claude only after explicit consent and verify its vendor signature before installation.
- Add a SHA-256-verified release bootstrap and Apple silicon/Intel build workflows. End-user binaries require no Node.js, Go, or DMG interaction.

- Keep Nord interaction fills translucent so card hover layers preserve text and table separators.
- Add Nord colors for CDS row separators and tooltips.
- Preserve translucent neutral, card, control, and field layers, including the stacked-card hover fallback.
- Preserve native transparent inputs inside compound search fields.
- Limit the base page background to the document root so accent coachmarks keep their contrasting text.
- Distinguish unaccepted prompt suggestions with a readable Nord blue foreground while preserving accepted editor text.
- Draw an inset composer focus outline for mouse and keyboard focus without changing control geometry.
- Apply Estedad and paragraph direction to Persian prose in plain or Markdown code fences; preserve declared programming languages and detected source syntax.
- Isolate Persian tooltip and truncated and faded navigation title text without changing control layout or document content.

- Add `--install-extension` and `--extension-dry-run` with a one-command GitHub package install.
- Automate extension building, login-agent registration, environment setup, and backed-up Hammerspoon migration without Python.
- Preserve verified installation backups and original environment values; roll back owned changes after installation failures.

- Add an unpacked extension build for automatic font, direction, and Nord application in chat and nested artifact frames.
- Include document `srcdoc` support, isolated controller lifecycle checks, and bundled font and code licenses.
- Document installation, Hammerspoon migration, ordinary-launch startup, updates, and rollback.
- Verify live Persian chat, document tables, comments, frame reloads, and ordinary launches on Claude Desktop 5.11492.5 separately from synthetic tests.

- Add a complete bounded direct font/controller plan with shared production health checks and semantic tests.
- Verify local console focus before direct writes and wait safely for asynchronous focus acknowledgements.
- Verify child-frame handoffs against both the target and chat parent, and classify browser ancestry before creating document identities.
- Verify clean temporary-home and live-profile removal/reinstallation separately from first-run OS permissions.
- Replace nine static TTF faces with the unmodified official Estedad 7.3 variable WOFF2; retain weights 100–900 in one face.
- Reduce the chat console payload from about 2.19 MB to 186 KB.
- Retain safe failure reasons and phase timings across successful retries.
- Wait for the guest chat on cold startup instead of targeting the temporary local shell.
- Distinguish a completely inspected native nonmodal dialog from the single exact console candidate.
- Bound each frame separately while keeping a hard overall scan limit.
- Diagnose bounded prompt traversal and clear large source echoes only in the newly owned console after document verification.
- Add an isolated direct-dispatch experiment and synthetic JavaScript/ownership tests; keep it outside the default installer.
- Reuse confirmed controllers across same-layout chat navigation and accessibility identity changes.
- Disable activation health scans by default; retain explicit compatibility recovery.
- Add a CDT status menu and delayed manual reapplication without forcing app focus.
- Cover empty textbox composers and nested chat-input textareas; upgrade the renderer revision.
- Explain idle startup, result evidence, optional IPC, and manual recovery limits.
- Count manual reapplication separately from automatic health scans.
- Record live navigation, cold-start, reload, document, comment, clipboard, and recovery checks, including two automatic retries.

## 1.0.0

Initial release of Claude Desktop Tweaks.

- Added in-memory tweaks through Claude Desktop's built-in console and Hammerspoon.
- Included nine Estedad font weights, paragraph direction for mixed-language text, and a Nord dark theme.
- Added separate handling for supported chat, document, and comment frames, with frame type and document identity checks before installation.
- Added font and stylesheet health checks and recovery within the same document.
- Added exact source verification, focus checks, user-input guards, and clipboard ownership checks before execution.
- Added one CLI for installation, configuration removal, and backup restoration.
- Kept Claude's files, signature, ASAR archive, and security settings unchanged.

A cold start of the final runtime has not yet been verified in a live test. Reloads without useful accessibility events may not be detected until the window becomes active again. See [testing and limitations](docs/testing.md).
