# Automatic extension installation

The extension uses the existing Estedad font, direction controller, and Nord theme. It runs isolated content scripts in supported Claude frames, including nested document frames. It has no background worker, network calls, or storage permissions. CSS changes remain in memory; document text and table order are not edited.

Build a standalone directory with all font and code license notices:

```sh
node scripts/build-extension.cjs /absolute/path/to/extension
```

The manifest registers `all_frames`, `match_about_blank`, and `match_origin_as_fallback`. The runtime independently rejects unsupported origins and opaque frames without a supported artifact ancestor. Authentication and API pages are excluded. `about:srcdoc` documents are classified using browser-provided ancestor origins, not cross-origin DOM access.

## Install on macOS

This method does not require Hammerspoon or an idle keyboard. It was checked on Claude Desktop 5.11492.5. The app still needs time to load each page and decode the local font.

### One command

Install Node.js 22.12.0 or later and the official Claude Desktop app. Save work and quit Claude first. When migrating from the old integration, quit Hammerspoon too. The installer never quits either app automatically.

Run this command in Terminal:

```sh
npx --yes --cache="$(mktemp -d)" --package=https://github.com/Ssisakhti/Claude-Desktop-Tweaks/archive/refs/heads/main.tar.gz claude-desktop-tweaks --install-extension
```

This creates a fresh temporary npm cache, downloads the current repository package, and runs its Node installer. A fresh cache prevents updates from reusing an older npx executable at the same archive URL. Python, a manual checkout, and manual LaunchAgent editing are not required. The command is specific to macOS.

If you already have the checkout, the equivalent command is:

```sh
node bin/claude-desktop-tweaks.cjs --install-extension
```

The installer:

- Builds the extension with the local Estedad font and all license notices.
- Registers the login LaunchAgent and sets `REACT_PROFILE=1` for ordinary launches.
- Removes only the old Hammerspoon startup block when present, preserving unrelated configuration and saving a backup.
- Saves the original environment value and rollback information in `~/Library/Application Support/Claude Desktop Tweaks/extension-startup.json`.
- Backs up a verified older installation before updating it and preserves the original rollback value across repeated installs.
- Refuses unknown extension directories, unowned startup agents, symbolic links, and concurrent installs.
- Attempts to restore its own changes if installation fails. If rollback is incomplete, it reports that fact and the backup location; preserve those backups.

The extension directory is normally used by React DevTools. If it contains an unknown extension, installation stops instead of replacing it. Identify and preserve that installation before deciding how to proceed. Do not delete it just to bypass the check.

The launch variable is inherited by other GUI apps too; it is not an app-specific macOS setting. Claude's files, signature, ASAR archive, and security settings are unchanged.

### Verify installation

Open Claude normally from Dock or Finder, or run:

```sh
open -a Claude
```

Check a Persian chat, a document artifact, and its comments. Fonts and paragraph direction apply automatically. Code blocks, document text, and table column order must stay unchanged. The installer sets up loading; it does not claim that your app version has passed a live display test.

Ordinary launches passed local acceptance on Claude 5.11492.5. A logout/login cycle remains untested. Claude starting as a login item can race with the environment agent and may need one relaunch.

To preview changes without installing, with the same apps closed, use:

```sh
npx --yes --cache="$(mktemp -d)" --package=https://github.com/Ssisakhti/Claude-Desktop-Tweaks/archive/refs/heads/main.tar.gz claude-desktop-tweaks --extension-dry-run
```

Downloading the package can still populate npm's cache. The preview does not write the extension, startup agent, Hammerspoon configuration, or launch environment.

### Update or remove

To update, save work, quit Claude, and run the same installation command again. Verified older files are backed up outside Claude's `extensions` directory. Do not enable the old Hammerspoon watcher alongside the extension.

Removal is manual. Read the saved rollback record first and keep its backup paths. Unload only the owned agent:

```sh
launchctl bootout "gui/$(id -u)/local.claude-desktop-tweaks.environment"
```

Move `~/Library/LaunchAgents/local.claude-desktop-tweaks.environment.plist` to a backup folder so it is not loaded at the next login. Restore `previousReactProfile` from the record. If it is `null`, run:

```sh
launchctl unsetenv REACT_PROFILE
```

If it is a string, use `launchctl setenv REACT_PROFILE` followed by that exact value instead.

If the restored value is absent or is not `1`, save work, quit Claude, and move only this project's confirmed extension directory to a backup outside `extensions`. Open Claude normally to clear its in-memory styles.

If the previous value was `1`, restoring it keeps the profiling hook enabled. Keep the extension directory until you deliberately disable profiling or replace it with its original extension backup. Removing the directory with `REACT_PROFILE=1` can make Claude download React DevTools in its place.

To return to Hammerspoon, first disable this extension's loading. If `hammerspoonBackup` is present in the rollback record, restore that configuration with the standard `--restore-backup` command and then open or reload Hammerspoon. Never start both methods together.

## How loading works

Claude 5.11492.5 has a process-start `REACT_PROFILE=1` hook that loads the directory normally reserved for React DevTools. This is an unofficial implementation detail, not a supported Claude extension API. Do not replace an existing third-party extension in that directory. Back up an owned prototype before replacing it.

Stop and verify cleanup of the Hammerspoon watcher before testing, and remove its startup block before switching permanently. Do not run both transports together: their isolated JavaScript worlds cannot coordinate controller ownership.

The inspected Electron runtime does not expose `chrome.runtime.reload()` to this content script, despite the current upstream documentation listing it. A new Claude process is needed to reload this extension's registration. Save work and have the user quit the app; never quit it automatically.

A one-process launch can use `open -a Claude --env REACT_PROFILE=1` after the app is fully closed. A login LaunchAgent can set `REACT_PROFILE` in the user's launch environment for ordinary Dock and Finder launches. This variable is then inherited by other GUI apps as well. A Claude login item can race with that agent, so a login-time launch still needs independent verification.

Automated controller tests do not establish actual extension delivery, browser font decoding, or display correctness. Complete the live checks above before relying on automatic startup.

## Local diagnostics

Each supported isolated frame exposes `window.__claudePersianExtensionV1.snapshot()` and an asynchronous `dispose()`. Snapshot diagnostics contain controller counts and health, not document text. The release build has no diagnostic overlay and no clipboard or keyboard automation.

Verify decoded font faces, computed fonts on actual Persian text nodes, and direction on prose blocks. Exclude code, math, icons, and intentionally isolated inline fragments. Compare text and ordered table content before and after without exporting private text. Test comments in their own frame and repeat after a full document reload. Record the result and limits separately from synthetic tests.

## Local acceptance on Claude 5.11492.5

A new official app process loaded the extension with the original watcher stopped. In an existing document, all 141 text runs containing Arabic-script letters used Estedad and RTL direction. The 14 additional Arabic-range runs contained numbers rather than Arabic-script letters and were not treated as prose-direction failures. One decoded variable font face covered weights 100–900.

Refreshing the actual controller preserved document text, inner HTML, and all four ordered tables. An existing comment in its separate artifact-content frame used Estedad and RTL, and its HTML was unchanged during refresh. Reloading that frame recreated the document; the new document controller was healthy and all 141 letter-bearing runs again used Estedad and RTL, without console installation commands.

The tested build was registered for automatic loading through a user login environment agent, and the original Hammerspoon startup block was removed with a configuration backup. The job registration and current launch environment were verified.

After the user fully quit Claude, an ordinary `open -a Claude` launch, without process-specific environment options, passed independent live acceptance. All 29 Persian text runs in the sampled chat replies used Estedad and RTL. The nested artifact document was healthy, with all 141 letter-bearing text runs using Estedad and RTL and four tables present. One decoded font face was loaded in each tested document. No installation or reapplication commands were run in the console; console commands only measured the already-applied resources. The original watcher remained stopped and its startup block remained absent. The diagnostic tools window was closed afterward.

A macOS logout/login cycle has not been tested. Other artifact types, native windows, and future Claude versions remain outside this acceptance result.

The initial extension acceptance used 139 JavaScript tests, the pinned font check, and the two stable Lua suites (744 and 322 assertions). Installer validation adds temporary-home tests with simulated process and launchctl results: new and repeated installation, migration, ownership refusal, symlink refusal, locks, backups, and failure rollback. These tests do not modify a live system profile and do not substitute for the live frame checks above.

## Rollback of the local installation

The local setup records its previous environment value and configuration backup in `~/Library/Application Support/Claude Desktop Tweaks/extension-startup.json`. Keep that file and the configuration backup.

To roll back, first save work and quit Claude. Unload the owned `local.claude-desktop-tweaks.environment` LaunchAgent and remove its plist. Restore the previous `REACT_PROFILE` value from the record, or unset it if it was absent. Restore the Hammerspoon configuration using the standard backup restoration command, then reload Hammerspoon. Keep the extension directory until no future profiling launch will reference it; removing it while `REACT_PROFILE=1` remains enabled can trigger installation of React DevTools instead.
