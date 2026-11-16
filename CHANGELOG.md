# Release information

## 1.2.0

Standalone installers are available for macOS and official Claude Desktop on Ubuntu 22.04+ and Debian 12+, for x64 and ARM64. Linux support is experimental because live chat and artifact display checks are pending.

The English terminal interface provides independent font, theme, and right-to-left settings. It saves your choices and lets you change or disable them later. No Hammerspoon, Node.js, or Go is required to run it.

The installer checks downloads, preserves installation backups, and asks before installing missing Claude. Linux uses Anthropic's signed apt repository and a user desktop entry. macOS uses a user LaunchAgent.

See [installation](docs/installation.md) for setup and removal, and [tests and known limits](docs/testing.md) for verified coverage.
