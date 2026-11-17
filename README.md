# Claude Desktop Tweaks

Choose your font, theme, and text direction in Claude Desktop.

- **Font:** Estedad or Vazirmatn for Persian text, with weights 100–900 in a local variable font.
- **Theme:** Nord or Gruvbox Dark colors for dark mode.
- **Right-to-left:** automatic direction for Persian and mixed Persian/English text.

Turn each option on or off independently. Run the installer again whenever you want to change your choices.

## Install

Save your work and quit Claude.

### macOS and Linux

Run in Terminal:

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

### Windows 11 x64

Run in PowerShell:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.ps1')))
```

This command gets the latest published release. No version number is needed.

### Finish setup

Follow the Font, Theme, Direction, and Apply steps. Preview the theme before applying. The interface is in English. If Claude is missing, the installer asks before installing it.

On macOS and Windows, open Claude normally after setup. On Linux, use the applications menu or dock.

**Hammerspoon, Node.js, and Go are not required.** No separate installer app is needed.

## Platforms

| System | Processors | Status |
| --- | --- | --- |
| macOS | Apple silicon, Intel | Available; live app checks cover Apple silicon |
| Ubuntu 22.04+ and Debian 12+ | x64, ARM64 | Experimental; live Linux chat and artifact checks are pending |
| Windows 11 | x64 | Experimental; live Claude startup and display checks are pending |

Linux support requires the official Claude Desktop package. Windows support requires the official x64 MSIX package from Anthropic and its standard local profile. AppImage and Flatpak are not supported.

## Change settings

Run the same command again, or use the settings path printed by the installer. Quit Claude before applying changes, then reopen it.

You can enable any combination, including all options off. Turning everything off keeps the extension installed but stops it from changing fonts, colors, or text direction.

## What it changes

The extension applies styles to supported chats, document artifacts, and comments. It preserves message text, code, table column order, and control layout. It loads the font locally and does not send conversation data.

Claude's application files and security settings stay unchanged. Loading uses an unofficial startup hook, so a Claude update may affect compatibility. Native Quick Entry and every artifact type are not covered by the current checks.

## Guides

- [Installation and removal](docs/installation.md)
- [Installer controls and prerequisites](docs/terminal-installer.md)
- [How the extension works](docs/extension.md)
- [Tests and known limits](docs/testing.md)
- [Release information](CHANGELOG.md)

## Development

Node.js and Go are needed to build from source. See the [testing guide](docs/testing.md) for checks and build commands.

## Licenses

Code, font, theme, and dependency notices are included. See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

This is an unofficial project, not affiliated with or endorsed by Anthropic.
