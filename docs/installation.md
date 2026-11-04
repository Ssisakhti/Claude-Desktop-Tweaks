# Installation and removal

## Requirements

- macOS and the official Claude Desktop app.
- Node.js 22.12.0 or later and npm.
- Hammerspoon with Accessibility permission.

Keep Hammerspoon running while using the integration. To start it after signing in to macOS, enable **Launch Hammerspoon at login** in Hammerspoon. This tool does not grant system permissions automatically.

## Preview and install

Run these commands from the project directory:

```sh
npm ci
node bin/claude-desktop-tweaks.cjs --dry-run
```

The preview does not write an installation. To install:

```sh
node bin/claude-desktop-tweaks.cjs --install
```

Keep the configuration backup path printed by the installer, then choose **Reload Config** in Hammerspoon. The installer copies two Lua modules and the command bundle into a private runtime directory. The installed watcher does not depend on the source checkout remaining in place. Runtime files are retained so a configuration backup can still refer to them.

Installation prepares the watcher; it does not prove that every app frame has been processed. The official app must be active and its interface ready. User input or developer tools already open can delay a transaction. The tool does not send messages, submit comments, or edit document content.

The installed Hammerspoon handle is named `claudeDesktopTweaks`. Status is written to `~/.hammerspoon/claude-desktop-tweaks/status.json`. Check that its time and process match the current app. An old report or the presence of a configuration file does not prove that the watcher is running.

## Replace an active installation

Before replacing or reloading an active integration, stop its running handle and confirm that cleanup has finished. The startup code requires the previous handle to report `running: false` with neither `cleanupPending` nor `cleanupRequired`. If cleanup or startup fails, the new integration stops with an error; it does not switch to another execution method.

The CLI changes files only. It does not control a live Hammerspoon session. Reloading the configuration is a separate step.

## Restore a configuration backup

Use the backup path printed by the installer:

```sh
node bin/claude-desktop-tweaks.cjs --restore-backup=/path/to/backup
```

The path above is a placeholder. Use your actual backup path, then reload the Hammerspoon configuration. Restoring the full configuration also reverts configuration edits made after that backup. Choose the backup carefully.

## Remove

```sh
node bin/claude-desktop-tweaks.cjs --remove
```

Then choose **Reload Config** in Hammerspoon. Removing the configuration alone does not stop the running watcher or remove styles already applied in memory. Save your work, quit Claude completely, and reopen it to clear the in-memory changes. The tool does not quit the app automatically.

## What changes

The installer writes this integration's Hammerspoon configuration and runtime files. It does not change Claude's files, signature, ASAR archive, frame isolation, or security settings. It does not open Chrome.

The console can appear briefly during a transaction. Completely invisible execution is not guaranteed. See [testing and limitations](testing.md) for reload detection and other boundaries.
