# Installation and removal

## Supported systems

| System | Processors | Status |
| --- | --- | --- |
| macOS | Apple silicon, Intel | Available; live app checks cover Apple silicon |
| Ubuntu 22.04+ and Debian 12+ | x64, ARM64 | Experimental; live chat and artifact checks are pending |
| Windows 11 | x64 | Experimental; live Claude startup and display checks are pending |

Use the official Claude Desktop app. Linux requires the official Ubuntu or Debian package. Windows requires Anthropic's x64 MSIX package and its standard local profile. Windows ARM64, AppImage, and Flatpak are not supported.

See [tests and known limits](testing.md) for verified coverage.

## Install on macOS or Linux

Save your work and quit Claude. Open Terminal and run:

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

## Install on Windows 11 x64

Save your work and quit Claude. Open PowerShell and run:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.ps1')))
```

The command downloads the latest published release. You do not need to enter or update a version number.

## Finish setup

Setup checks your system automatically. If Claude is missing, approve its installation or install it yourself first.

1. **Font:** select Estedad, Vazirmatn, or Use Claude default.
2. **Theme:** preview Nord or Gruvbox Dark, or select Use Claude default.
3. **Direction:** select Automatic or Use Claude default.
4. **Apply:** review the rows, edit any choice, and select Apply changes.

On macOS and Windows, open Claude normally. On Linux, use the applications menu or dock.

The installer never quits Claude for you.

For a direct Linux terminal launch, use `env REACT_PROFILE=1 claude-desktop` to load the extension.

On Windows, open Claude normally after setup. The installer changes only the current user's `REACT_PROFILE` environment entry and notifies the desktop. Existing shortcuts stay unchanged. The entry can also be inherited by other newly opened programs. Keep the receipt so you can restore its exact value and type when removing the tweaks.

## Update or change settings

Run the same command again. It gets the latest published installer and opens your saved choices. Installed and Available show the extension and installer package versions. Select Update, review your choices, and confirm. A newer installed version is preserved. You can also reopen settings with the path printed by the installer.

Quit Claude before applying, then reopen it. Selecting all options off disables the tweaks without removing their files.

## Installation files

### macOS

- Settings, receipt, and executable releases: `~/Library/Application Support/Claude Desktop Tweaks/`
- Extension: `~/Library/Application Support/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi/`
- Startup job: `~/Library/LaunchAgents/local.claude-desktop-tweaks.environment.plist`

### Linux

- Settings, receipt, and executable releases: `~/.local/share/Claude Desktop Tweaks/`
- Extension: `~/.config/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi/`
- User desktop entry: `~/.local/share/applications/com.anthropic.Claude.desktop`

`XDG_CONFIG_HOME` and `XDG_DATA_HOME` override the default config and data locations. They must point inside your home directory. Symbolic installation paths are rejected.

### Windows

- Settings, receipt, and executable releases: `%LOCALAPPDATA%\Claude Desktop Tweaks\`
- Extension: `%LOCALAPPDATA%\Claude-Data\claude_pzs8sxrjxfjjc\extensions\fmkadmapgofadopljbjfkapdkoienihi\`
- Startup setting: the current user's `REACT_PROFILE` entry in `HKEY_CURRENT_USER\Environment`

The standard Claude profile must exist. If prompted, open Claude once, quit it, and return to setup. Custom Claude profiles and application-data locations outside your user profile are not supported.

On all systems, the receipt is named `extension-startup.json`. Keep it and the reported backups until you are sure you no longer need them.

## Remove on macOS

There is no automatic uninstall command for the standalone installer. To stop the styling without removing files, turn all three options off and apply.

For full removal:

1. Save your work and quit Claude.
2. Read `extension-startup.json` and keep its backup paths.
3. Unload the startup job:

   ```sh
   launchctl bootout "gui/$(id -u)/local.claude-desktop-tweaks.environment"
   ```

4. Move this project's LaunchAgent plist to a backup folder so it cannot load at login.
5. Restore `previousReactProfile` from the receipt. If it is `null`, run `launchctl unsetenv REACT_PROFILE`. If it is a string, restore that exact value with `launchctl setenv REACT_PROFILE`.
6. Once future launches no longer use `REACT_PROFILE=1`, move the owned extension to a backup folder or restore its saved replacement.
7. Open Claude normally and check the result.

If the saved value is `1`, restoring it keeps the loading hook active. Keep the extension until you decide how that profiling launch should work. Do not remove an extension belonging to another tool.

## Remove on Linux

1. Save your work and quit Claude.
2. Keep the receipt and backups.
3. Remove only the installer-owned user desktop entry listed above. The system's Claude desktop entry is unchanged and becomes active again.
4. Stop using terminal launches that set `REACT_PROFILE=1`.
5. Restore a saved extension, or move this project's extension to a backup folder if there is nothing to restore.
6. Open Claude from the applications menu and check the result.

Extension backups are beside the extension, under `.claude-desktop-tweaks-backups/`. Keep any files you have edited instead of deleting them. Removing tweaks does not uninstall Claude or its apt repository.

## Remove on Windows

1. Save your work and quit Claude.
2. Keep `extension-startup.json` and the reported backups.
3. Restore `REACT_PROFILE` in the current user's environment from `previousReactProfile` and `previousReactProfileKind` in the receipt. A `null` value means the entry should be absent. Preserve the raw value and its registry type (`String` or `ExpandString`). The user environment is stored in `HKEY_CURRENT_USER\Environment`.
4. Sign out and back in so new applications receive the restored environment.
5. Once future launches no longer use `REACT_PROFILE=1`, move the owned extension to a backup folder or restore its saved replacement. If the saved value is `1`, keep the extension until you decide how that profiling launch should work.
6. Open Claude normally and check the result.

No shortcut changes need to be undone. Do not remove another tool's extension or a user-modified file.

## If setup stops

Keep the error message, receipt, and backups. The installer tries to undo its own changes and preserves files it cannot identify safely.

A power loss or forced termination can leave an installation lock. Confirm that no installer is running before investigating it. Do not delete locks or backups just to bypass an error.

See [installer details](terminal-installer.md) for download options and prerequisite approval.
