# Installation and removal

## Install

Use macOS or the official Claude Desktop package on Ubuntu 22.04+ or Debian 12+. Linux support is experimental. See the [current test coverage](testing.md) before relying on it.

Save your work and quit Claude. Open a terminal and run:

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

1. Review the system check.
2. If Claude is missing, approve its installation or install it yourself first.
3. Choose font, theme, and right-to-left separately.
4. Review your choices and select Apply.
5. Open Claude normally.

Hammerspoon, Node.js, and Go are not needed. The installer never quits Claude for you.

On Linux, open Claude from your applications menu or dock. A direct terminal launch needs `env REACT_PROFILE=1 claude-desktop` to load the extension.

## Update or change settings

Run the same command again. It downloads the current release and opens your saved choices. You can also use the full settings path printed by the installer.

Quit Claude before applying, then reopen it. Selecting all options off disables the tweaks without removing their files.

## Installation files

| Files | macOS | Linux defaults |
| --- | --- | --- |
| Settings, receipt, executable releases | `~/Library/Application Support/Claude Desktop Tweaks/` | `~/.local/share/Claude Desktop Tweaks/` |
| Extension | `~/Library/Application Support/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi/` | `~/.config/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi/` |
| Startup | `~/Library/LaunchAgents/local.claude-desktop-tweaks.environment.plist` | `~/.local/share/applications/com.anthropic.Claude.desktop` |

On Linux, `XDG_CONFIG_HOME` and `XDG_DATA_HOME` override the default config and data locations. They must point inside your home directory. Symbolic installation paths are rejected.

The receipt is named `extension-startup.json`. Keep it and the reported backups until you are sure you no longer need them.

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

## If setup stops

Keep the error message, receipt, and backups. The installer tries to undo its own changes and preserves files it cannot identify safely.

A power loss or forced termination can leave an installation lock. Confirm that no installer is running before investigating it. Do not delete locks or backups just to bypass an error.

See [installer details](terminal-installer.md) for download options and prerequisite approval.
