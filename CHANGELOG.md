# Release information

## 1.5.3 (unreleased)

Document that Claude-3p deployments are unsupported. Remove the experimental deployment detection and styling prototypes. The terminal appearance and version-display fixes remain included.

## 1.5.2 (unreleased)

Windows profile discovery no longer checks permissions on unused search paths without a profile marker. Selected profiles still require the existing ownership, permission, and reparse-point checks. Directory errors identify the relative path without including the user's home path.

The installer paints the full terminal with explicit backgrounds, including step separators, and wraps long error text. Automated checks cover every screen at compact and wide sizes. A synthetic preview was checked; live Windows rendering remains unverified.

## 1.5.1 (unreleased)

Windows setup detects initialized modern, roaming, and MSIX virtualized profiles instead of always choosing one fixed directory. It rejects empty or ambiguous profiles. Linux menu launches use the installation's configuration directory and cannot bypass their environment through D-Bus activation.

Current versions show **Up to date** without advertising the same version as available. Windows installation completion requests a full terminal repaint to remove stale rows.

These changes have automated coverage. Live Windows and Linux Claude display checks remain pending; the terminal repaint also needs confirmation in Windows Console.

## 1.5.0

The standalone installer supports macOS, Ubuntu/Debian, and Windows 11 x64. Its English interface shows installed and available versions, reviews updates with saved settings, and rejects downgrades.

Font, theme, and automatic text direction are independent. Choose Estedad or Vazirmatn, Nord or Gruvbox Dark, or Claude defaults. Theme selection includes a local preview.

Downloads show progress and verify SHA-256 checksums. Setup asks before installing missing Claude, preserves backups, and waits for Claude to close before applying changes.

See [installation](docs/installation.md) and [tests and limits](docs/testing.md).
