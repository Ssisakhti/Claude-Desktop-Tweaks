# Changelog

## Unreleased

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
