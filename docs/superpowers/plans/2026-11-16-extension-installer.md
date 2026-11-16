# One-command extension installation

The existing Node CLI will accept `--install-extension` and `--extension-dry-run`. Installation builds the tested extension with licenses, registers the user login agent, sets the current launch environment, and removes only the legacy Hammerspoon startup block with a backup. No Python, app patch, automatic app quit, or UI automation is added.

Require macOS, a closed Claude process, and a closed Hammerspoon process when a legacy startup block exists. Refuse unknown extension/agent ownership and symbolic links. Keep backups and the original environment value. Repeat installation must preserve the original rollback information. On failure, restore owned writes and the immediately preceding environment; preserve concurrent changes and report incomplete rollback.

1. Add failing temporary-home tests for new/repeated installation, migration, refusal, dry run, and rollback.
2. Implement the filesystem transaction and injectable system commands. Route the CLI without changing legacy options.
3. Verify all tests, font data, Lua suites, and packed distribution. Use synthetic process/launchctl fixtures for mutation tests; do not claim a live system install from those results.
4. Replace manual instructions with the single command, retain manual diagnostics, review, commit, and publish the guide and implementation together.
