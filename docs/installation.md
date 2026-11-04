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

If no Hammerspoon configuration existed, the installer reports `backup: null`; there is no earlier configuration to restore.

After reloading, bring Claude to the front and leave the keyboard and mouse idle for at least two seconds. A brief console transaction can occur during the first application.

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

## Quiet navigation and recovery

The default watcher reuses the controller across chat URL changes when the supported frame layout is unchanged. The in-page controller handles new messages, streaming text, and editor input. Returning to Claude does not trigger a console health scan just because 30 seconds have passed.

The **CDT** menu shows the current activity and the last result separately. **Checked** means a scan finished; **Applied** means a scan reported at least one application. Neither result proves coverage of every frame. Switching to Terminal normally changes the activity to **Waiting for Claude**.

If a full reload clears the styles without an observable loading or frame-layout change, choose **Reapply in Claude in 3 seconds** from the CDT menu, return to the Claude window, and stop moving the mouse or typing. This command never brings Claude to the front automatically. A page load event or a changed accessibility identity alone cannot reliably distinguish chat navigation from a replaced document.

For diagnostic compatibility, advanced callers can pass `recoveryOnActivation=true` to the Lua startup configuration. This restores load-event and activation recovery, including its possible console popups. The installer uses quiet navigation by default.

Use the CDT menu or Hammerspoon Console for diagnosis. The optional `hs` Terminal command requires `require("hs.ipc")` in the running Hammerspoon session; its connection error does not by itself indicate a failed installation or missing accessibility permission.

## Failure diagnostics and time budgets

`lastFailure` retains the most recent failed attempt even after a retry succeeds. It contains only fixed reason/phase names, bounded durations, and safe counts. A new Claude process clears the previous process's failure evidence. `lastDriver.elapsedSeconds` and `phaseDurations` describe the current or most recent transaction; they do not contain page content or URLs.

After ownership and document checks, an apply command clears output in its newly owned console before running the payload. This removes the large source echo that can otherwise hide the prompt beyond the accessibility traversal limit. The following result receipt remains available. Existing user tools are never taken over or cleared.

The installer gives each frame up to 60 seconds, with a hard total scan cap of 300 seconds. The driver still checks input, focus, window identity, and clipboard ownership throughout. Advanced callers may pass a smaller `scanTimeout` in seconds, at least the frame `timeout` and at most 300. A stalled frame cannot use the full scan budget by itself.

## Experimental direct dispatch

The default installation does not load `claude-console-direct.lua`. That module separates asynchronous direct prompt writes, exact readback, local console focus, app-targeted execution, nonce/document receipts, and cleanup. It does not bootstrap a console. A separate experimental native adapter, `claude-console-direct-native.lua`, implements capture, source probing, owned handoff, prompt dispatch, and release. It requires an explicit trusted ownership handoff and cannot take over an existing user console.

See [background bootstrap investigation](background-bootstrap.md) for the tested official menu alternative and its focus-transfer limitation. Experimental transport tests are separate from the supported default runtime.

For the native experiment, create the adapter with `native.new(hs)`, call `capture(sourceWindowId, expectedURL)` before a trusted bootstrap creates tools, and obtain `probeCode(captureToken)`. The bootstrap must execute that exact source-guarded probe in the new console. `bind(captureToken, toolsWindowId)` then reads and verifies the real console receipt itself; callers cannot supply a proof table. Pass the returned opaque ownership value to the direct module. No startup hook is installed. Missing monitoring capabilities or rejected AX watcher registration refuse the handoff. An accepted asynchronous window close is conservatively reported as incomplete and monitoring is stopped; do not mistake that for verified cleanup.

The stable watcher waits for the main guest content at startup instead of targeting a temporary local `main_window` shell. A nonmodal native dialog can be excluded from console candidates only after a complete bounded inspection proves it contains no web area and exactly one other candidate has the expected console title and official PID. The classification is rechecked until source ownership is proven. Modal, unknown, truncated, and additional console candidates still stop the transaction. An excluded dialog is never targeted or closed.

Abort an unclaimed native experiment with `discard(token)` so its capture/ownership state is released. The native adapter's lifecycle watcher registration and event capabilities must all succeed before a handoff is usable. Stop the default watcher and verify its cleanup before any live experiment.

For a child frame, `capture(sourceWindowId, expectedURL, toolsSourceURL)` can bind the child to its chat parent's tools title. Both exact, unique accessibility elements must exist in the same official window and remain unchanged. The source probe independently classifies the actual browser frame, including bounded ancestor origins for `about:srcdoc`, before creating or reusing a document identity. An existing identity with a different frame is preserved and rejected.

`buildDirectPlan({namespace, nonce, kind})` in `lib/persian/direct-plan.cjs` creates a complete experimental font/controller plan using the same production modules. The current variable-font plan has 33 commands, each below the direct transport limit. It transfers font bytes as data and trusted repository functions as syntax, without `eval` or `Function`. Each command checks namespace ownership; the final command verifies the actual production controller's health. Cleanup removes only temporary helpers and font chunks, retaining a successful controller. This builder does not open tools or install a startup hook.
