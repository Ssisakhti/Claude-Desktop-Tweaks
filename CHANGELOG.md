# Changelog

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
