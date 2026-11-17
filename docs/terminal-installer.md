# Terminal installer

The installer is a standalone executable with an English interface and Nord colors. It does not need Node.js, Go, Homebrew, Hammerspoon, or an Apple developer certificate.

[Download the latest release](https://github.com/Ssisakhti/Claude-Desktop-Tweaks/releases/latest), or use the command below.

## Install on macOS or Linux

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

The script detects your system and processor, downloads one release, checks its SHA-256 checksum, and opens the interface. It prints the full path for reopening settings. It does not change your shell profile or PATH.

The checksum checks download integrity. Downloads rely on HTTPS and this repository's release permissions for authenticity.

The script needs Bash, curl, and either `sha256sum` or `shasum`. Linux supports the official Claude package on Ubuntu 22.04+ and Debian 12+, for x64 and ARM64. Linux display checks are pending, so support remains experimental. Windows ARM64, AppImage, and Flatpak are not supported.

## Install on Windows 11 x64

Run in PowerShell:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.ps1')))
```

The Windows script uses the built-in PowerShell runtime, checks HTTPS redirects and the release checksum, and preserves existing files. It does not change PowerShell execution policy. Windows support is experimental: live Claude startup and display checks are pending.

## Controls

| Key | Action |
| --- | --- |
| Up / Down | Choose an option or settings row |
| Enter | Continue, edit a row, or use the selected action |
| Escape | Go back without losing choices |
| R | Refresh the check on the review or settings page |
| Q | Exit; confirm if you have unsaved changes |

Use a terminal at least 60 columns wide and 22 rows high. The interface keeps one content column with a fixed label and value layout. The action hints stay at the bottom. `NO_COLOR` disables terminal colors.

## Setup and saved settings

Checks run automatically. New installations have four steps: Font, Theme, Direction, and Apply. Existing installations open a settings summary. Select a row to edit it, then review and apply your changes.

Each choice is independent:

- **Font:** Estedad, Vazirmatn, or Use Claude default. Both fonts use local variable WOFF2 files with weights 100–900. The installer loads only the selected font into Claude. It does not change your terminal font; the terminal cannot preview these fonts accurately.
- **Theme:** Nord, Gruvbox Dark with hard contrast, or Use Claude default. A small colored message and composer preview changes as you move between themes. This preview does not change Claude. Themes apply in Claude's dark mode.
- **Direction:** Automatic or Use Claude default. Automatic follows Persian and English text while preserving code and table column order.

Use Claude default disables only that feature. Selecting defaults for all three leaves the extension installed without applying tweaks. The choices are saved when you apply. Quit Claude before applying changes, then reopen it.

## Missing Claude on macOS

The installer shows the download source and destination and waits for **Y**. Enter does not approve a download.

After approval, it downloads the official Claude disk image, verifies the vendor signature and macOS checks, copies the app into your Applications folder, and ejects the image. You do not open a DMG manually. Existing apps are preserved, and a failed verification stops installation.

## Missing Claude on Ubuntu or Debian

The installer waits for **Y**, then uses PolicyKit (`pkexec`) to request administrator permission through your desktop's authentication agent.

It verifies the vendor signing key, adds Anthropic's signed apt repository, downloads Claude from that repository alone, and installs it with its required packages. If needed, apt also installs curl and GnuPG. The repository remains configured for Claude updates.

Existing repository files with different contents are preserved, and installation stops. If PolicyKit or its authentication agent is unavailable, follow [Anthropic's installation instructions](https://support.claude.com/en/articles/10065433-install-claude-desktop), then run setup again.

Applying the tweaks themselves does not need administrator permission on any supported system.

## Missing Claude on Windows

The interface waits for **Y** before downloading the official Claude Setup linked by Anthropic. It verifies the Windows vendor signature before opening the setup program. Approve any setup or system permission prompts yourself. If the download is blocked, install Claude from [Anthropic's download page](https://claude.com/download), then reopen settings.

Open Claude once after installation, quit it, and return to setup. The installer supports the official x64 MSIX package and its standard local profile. It preserves unsupported installations rather than modifying them.

## Reopen settings or download without opening

Run the settings path printed by the script, or repeat the install command. Both install commands select the latest published release automatically. No version number is needed.

On macOS or Linux, download the latest release without opening settings:

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash -s -- --no-launch
```

`--no-launch` installs only the settings executable. It does not apply tweaks or change Claude's startup.

On Windows, download the latest release without opening settings:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.ps1'))) -NoLaunch
```

`-NoLaunch` installs only the settings executable. It does not apply tweaks or change startup.

The executable also accepts `--check` for read-only JSON status, `--version`, `--help`, and `--licenses`.

See [installation and removal](installation.md) for file locations, startup, backups, and recovery.
