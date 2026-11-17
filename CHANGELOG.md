# Release information

## 1.4.1

Downloads show a progress bar, percentage, received size, and average speed when the total is known. Unknown-size transfers show a spinner and received size. Redirected output uses plain phase messages. Cancellation cleans up partial downloads.

When Claude is open, setup keeps your choices and shows Check again and Back before applying. It never quits Claude automatically.

The English terminal installer uses four steps: Font, Theme, Direction, and Apply. Existing installations open saved settings with a separate edit action for each choice. The layout keeps labels and values aligned, with action hints at the bottom.

Choose Estedad or Vazirmatn variable fonts, Nord or Gruvbox Dark themes, and automatic text direction independently. Each feature can use Claude defaults instead. The theme step includes a local preview before applying changes.

Standalone installers are available for macOS, official Ubuntu/Debian Linux packages, and the official Windows 11 x64 MSIX package. Linux and Windows support remain experimental until live Claude checks are complete. End users do not need Node.js, Go, or Hammerspoon.

Use the install command to get the latest published release. Downloads include five executables and SHA-256 checksums. Setup asks before installing missing Claude and preserves backups and startup settings for removal.

See [installation](docs/installation.md) and [tests and known limits](docs/testing.md).
