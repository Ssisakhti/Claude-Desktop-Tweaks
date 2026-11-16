# Automatic extension installation

The extension uses the existing Estedad font, direction controller, and Nord theme. It runs isolated content scripts in supported Claude frames, including nested document frames. It has no background worker, network calls, or storage permissions. CSS changes remain in memory; document text and table order are not edited.

Build a standalone directory with all font and code license notices:

```sh
node scripts/build-extension.cjs /absolute/path/to/extension
```

The manifest registers `all_frames`, `match_about_blank`, and `match_origin_as_fallback`. The runtime independently rejects unsupported origins and opaque frames without a supported artifact ancestor. Authentication and API pages are excluded. `about:srcdoc` documents are classified using browser-provided ancestor origins, not cross-origin DOM access.

## Install on macOS

This method does not require Hammerspoon or an idle keyboard. It was checked on Claude Desktop 5.11492.5. The app still needs time to load each page and decode the local font.

### 1. Prepare the checkout

Install Node.js 22.12.0 or later and Python 3. Python is used only to create the login LaunchAgent. Then run:

```sh
git clone https://github.com/Ssisakhti/Claude-Desktop-Tweaks.git
cd Claude-Desktop-Tweaks
npm ci
```

For an existing checkout, update it before building. Save work and quit Claude completely. The commands below never quit it for you.

If migrating from the Hammerspoon integration, stop its running handle in Hammerspoon Console with `claudeDesktopTweaks.stop()` and inspect `claudeDesktopTweaks.snapshot()`. Confirm it has stopped and cleanup has finished, as described in the [replacement guide](installation.md#replace-an-active-installation). Then remove only its startup block:

```sh
node bin/claude-desktop-tweaks.cjs --remove
```

Keep the printed backup path and reload the Hammerspoon configuration. Do not run both delivery methods together. If no old integration is installed, skip this migration step.

### 2. Build the extension in Claude's data directory

The folder name below is the React DevTools ID used by Claude's startup hook. The guard refuses to overwrite an existing directory, including a real React DevTools installation.

Run this block from the checkout:

```sh
(
  set -eu
  extension_dir="$HOME/Library/Application Support/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi"
  if [ -e "$extension_dir" ] || [ -L "$extension_dir" ]; then
    echo "Extension directory already exists. Identify and back it up before continuing."
    exit 1
  fi
  node scripts/build-extension.cjs "$extension_dir"
)
```

If the guard stops, inspect the directory first. Only replace a confirmed installation of this project's extension; keep a backup outside the `extensions` directory. Do not replace another author's extension. The build includes the official font and all license notices and does not depend on the checkout afterward.

### 3. Test one launch

With Claude fully closed:

```sh
open -a Claude --env REACT_PROFILE=1
```

Check a Persian chat, a document artifact, and its comments. Code blocks and table column order must stay unchanged. Fonts and direction apply automatically; no console installation code or Hammerspoon command is needed. If the test fails, do not enable automatic startup.

### 4. Enable ordinary launches and login startup

First record the previous environment value for rollback:

```sh
launchctl getenv REACT_PROFILE
```

No output means the variable was absent. If it already had a value, keep that value so you can restore it later.

Create a user LaunchAgent. This block refuses to overwrite an existing agent:

```sh
python3 - <<'PYAGENT'
from pathlib import Path
import os
import plistlib

agent = Path.home() / 'Library/LaunchAgents/local.claude-desktop-tweaks.environment.plist'
agent.parent.mkdir(parents=True, exist_ok=True)
job = {
    'Label': 'local.claude-desktop-tweaks.environment',
    'ProgramArguments': ['/bin/launchctl', 'setenv', 'REACT_PROFILE', '1'],
    'RunAtLoad': True,
}
with agent.open('xb') as output:
    plistlib.dump(job, output)
os.chmod(agent, 0o600)
PYAGENT
```

Register the agent and set the current login environment:

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.claude-desktop-tweaks.environment.plist"
launchctl setenv REACT_PROFILE 1
launchctl getenv REACT_PROFILE
```

The final command must print `1`. The variable is inherited by other GUI apps too. This is not an app-specific macOS environment setting.

Save work, quit Claude, and open it normally from Dock or Finder, or run:

```sh
open -a Claude
```

Check the same chat and artifact again. This ordinary-launch check passed locally. A logout/login cycle has not been checked; Claude starting as a login item can race with the agent and may need one relaunch.

### Update or remove

To update, save work and quit Claude first. Identify the installed extension by its `manifest.json` name, `Claude Desktop Persian Tweaks`. Move that owned directory to a backup outside `extensions`, then rebuild it with step 2. Never overwrite a directory of uncertain ownership. Open Claude normally and repeat the checks in step 3.

To remove automatic loading, unload the owned agent:

```sh
launchctl bootout "gui/$(id -u)/local.claude-desktop-tweaks.environment"
```

Move `~/Library/LaunchAgents/local.claude-desktop-tweaks.environment.plist` to a backup folder so it is not loaded at the next login. Restore the environment value you recorded in step 4. If it was absent, run:

```sh
launchctl unsetenv REACT_PROFILE
```

If it had a value, use `launchctl setenv REACT_PROFILE` followed by that exact value instead.

If the restored value is absent or is not `1`, save work, quit Claude, and move only this project's confirmed extension directory to a backup outside `extensions`. Open Claude normally to clear the in-memory styles.

If the previous value was `1`, restoring it keeps the profiling hook enabled. Keep the extension directory until you deliberately disable profiling or replace it with the original extension backup. Do not enable the Hammerspoon integration while this extension is still loaded. Removing the directory with `REACT_PROFILE=1` can make Claude download React DevTools in its place.

To return to Hammerspoon, first disable this extension's loading, then restore the Hammerspoon configuration backup with the standard CLI and reload Hammerspoon.

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

Synthetic checks passed separately: 139 JavaScript tests, the pinned font check, and the two stable Lua suites (744 and 322 assertions). These counts do not substitute for the live checks above.

## Rollback of the local installation

The local setup records its previous environment value and configuration backup in `~/Library/Application Support/Claude Desktop Tweaks/extension-startup.json`. Keep that file and the configuration backup.

To roll back, first save work and quit Claude. Unload the owned `local.claude-desktop-tweaks.environment` LaunchAgent and remove its plist. Restore the previous `REACT_PROFILE` value from the record, or unset it if it was absent. Restore the Hammerspoon configuration using the standard backup restoration command, then reload Hammerspoon. Keep the extension directory until no future profiling launch will reference it; removing it while `REACT_PROFILE=1` remains enabled can trigger installation of React DevTools instead.
