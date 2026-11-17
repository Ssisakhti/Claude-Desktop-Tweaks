# Claude Desktop Tweaks

Choose the Persian font, dark theme, and text direction in Claude Desktop.

- **Font:** Estedad or Vazirmatn, with variable weights 100–900.
- **Theme:** Nord or Gruvbox Dark, with a preview before applying.
- **Direction:** automatic Persian and English text direction.

Each feature is independent. Select **Use Claude default** to disable one.

## Install or update

### macOS and Linux

Open Terminal and run:

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

### Windows 11 x64

Open PowerShell and run:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.ps1')))
```

Both commands get the latest published installer and verify the download.

For a new installation, follow **Font → Theme → Direction → Apply**. For an existing installation, the interface shows **Installed** and **Available** versions. Select **Update** to review and update with your saved choices. Select **Edit** to change an individual setting.

Save your work and quit Claude before applying. If Claude is open, setup keeps your choices and shows **Check again** and **Back**. Open Claude normally when setup finishes.

## Platforms

| System | Processors | Status |
| --- | --- | --- |
| macOS | Apple silicon, Intel | Available; live display checks cover Apple silicon |
| Ubuntu 22.04+ and Debian 12+ | x64, ARM64 | Experimental; live Claude display checks are pending |
| Windows 11 | x64 | Experimental; live Claude display checks are pending |

Use the official Claude Desktop app. Linux requires the Ubuntu or Debian package. Windows requires the x64 MSIX package and its standard user profile.

The extension loads fonts locally. It preserves message text, code, table column order, and control layout. It does not send conversation data or change Claude's application files or security settings.

## Guides

- [Installation, updates, and removal](docs/installation.md)
- [Installer controls](docs/terminal-installer.md)
- [Extension behavior](docs/extension.md)
- [Development and tests](docs/testing.md)
- [Release information](CHANGELOG.md)
- [Licenses](NOTICE.md)

This is an unofficial project and is not affiliated with Anthropic.
