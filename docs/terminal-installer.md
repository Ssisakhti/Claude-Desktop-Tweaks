# Terminal installer

The installer is a standalone executable with an English interface and Nord colors. It does not need Node.js, Go, Homebrew, Hammerspoon, or an Apple developer certificate.

[Download version 1.2.0](https://github.com/Ssisakhti/Claude-Desktop-Tweaks/releases/tag/v1.2.0), or use the command below to get the current release.

## Install

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

The script detects your system and processor, downloads one release, checks its SHA-256 checksum, and opens the interface. It prints the full path for reopening settings. It does not change your shell profile or PATH.

The checksum checks download integrity. Downloads rely on HTTPS and this repository's release permissions for authenticity.

The script needs Bash, curl, and either `sha256sum` or `shasum`. Linux supports the official Claude package on Ubuntu 22.04+ and Debian 12+, for x64 and ARM64. Linux display checks are pending, so support remains experimental. Windows, AppImage, and Flatpak are not supported.

## Controls

| Key | Action |
| --- | --- |
| Arrow keys or J/K | Move between features |
| Space | Toggle the selected feature |
| 1, 2, 3 | Toggle font, theme, or right-to-left |
| Enter | Continue, review, then apply |
| Escape | Go back |
| R | Refresh the system check |
| Q | Exit; confirm if you have unsaved changes |

Use a terminal at least 60 columns wide and 22 rows high. Wider terminals show a side panel. `NO_COLOR` disables terminal colors.

## Feature choices

Each option is independent, and you can change it at any time by running the installer again.

- **Font:** Estedad for Persian content, with weights 100–900 in one local WOFF2 file. It does not change your terminal font.
- **Theme:** Nord colors in Claude's dark mode. Nord is the available theme, not the product name.
- **Right-to-left:** direction based on text, including mixed Persian and English. Code and table column order are preserved.

All-off leaves the extension installed without applying the three tweaks. Quit Claude before applying changes, then reopen it.

## Missing Claude on macOS

The installer shows the download source and destination and waits for **Y**. Enter does not approve a download.

After approval, it downloads the official Claude disk image, verifies the vendor signature and macOS checks, copies the app into your Applications folder, and ejects the image. You do not open a DMG manually. Existing apps are preserved, and a failed verification stops installation.

## Missing Claude on Ubuntu or Debian

The installer waits for **Y**, then uses PolicyKit (`pkexec`) to request administrator permission through your desktop's authentication agent.

It verifies the vendor signing key, adds Anthropic's signed apt repository, downloads Claude from that repository alone, and installs it with its required packages. If needed, apt also installs curl and GnuPG. The repository remains configured for Claude updates.

Existing repository files with different contents are preserved, and installation stops. If PolicyKit or its authentication agent is unavailable, follow [Anthropic's installation instructions](https://support.claude.com/en/articles/10065433-install-claude-desktop), then run setup again.

Applying the tweaks themselves does not need administrator permission on either system.

## Reopen settings and pin a version

Run the settings path printed by the script, or repeat the install command. Repeating the command selects the current published release.

To download a specific release without opening settings:

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash -s -- --version v1.2.0 --no-launch
```

`--no-launch` installs only the settings executable. It does not apply tweaks or change Claude's startup.

The executable also accepts `--check` for read-only JSON status, `--version`, `--help`, and `--licenses`.

See [installation and removal](installation.md) for file locations, startup, backups, and recovery.
