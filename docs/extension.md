# How the extension works

Claude Desktop Tweaks loads an unpacked extension into the official Claude app. The extension applies the selected font, theme, and text direction when supported pages load.

Use the [standalone installer](installation.md) to install or change settings. See the [development guide](testing.md) for source builds.

## Loading and restart

Claude 5.11492.5 exposes a `REACT_PROFILE=1` startup hook. It loads an extension directory normally used by React DevTools. This is an unofficial implementation detail, not a supported Claude extension API.

The installer preserves unknown extensions instead of replacing them. A Claude update may change the hook; Linux setup checks the installed archive before writing files. That check does not replace a live display test.

A full Claude restart is required after applying settings. The installed Electron runtime does not provide a usable extension reload command for this setup. Save your work and quit Claude yourself; the installer never quits it.

## Startup on macOS

A user LaunchAgent sets `REACT_PROFILE=1` for ordinary Dock and Finder launches. This environment value can also be inherited by other GUI apps. The installer records its previous value for removal.

A Claude login item can start before the LaunchAgent. Login-time startup remains unverified and may need a relaunch. See [removal instructions](installation.md#remove-on-macos) before removing the extension directory.

## Startup on Linux

An installer-owned desktop entry launches the official app with `REACT_PROFILE=1` and the same `XDG_CONFIG_HOME` used during installation. It uses the entry's command rather than D-Bus activation. These environment values apply to that Claude process, not the whole desktop session. The system desktop entry stays unchanged.

Open Claude from the applications menu or dock. For a direct terminal launch, use:

```sh
env REACT_PROFILE=1 claude-desktop
```

The extension uses Claude's standard user profile. Custom `CLAUDE_USER_DATA_DIR` profiles are not supported.

## Startup on Windows

Setup records the current user's `REACT_PROFILE` value and registry type, sets it to `1`, and sends Windows an environment-change notification. Open Claude normally. No shortcut or vendor file is replaced. Other newly opened programs can inherit this user environment value too.

Setup finds an initialized profile by its `Local State` file in one of three standard locations: `%LOCALAPPDATA%\Claude-Data\claude_pzs8sxrjxfjjc\`, `%APPDATA%\Claude\`, or `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\`. It does not read the marker's contents. An empty folder is insufficient. If several locations have this marker, setup stops instead of guessing. Custom profiles and other package families are not supported. Live MSIX startup and graphical behavior are not yet verified, so Windows support remains experimental.

An existing terminal or app launcher can keep its old environment. If the tweaks do not appear after a full Claude restart, sign out of Windows and sign in again, then open Claude from its normal icon. Setup does not sign you out or restart the desktop.

See [removal instructions](installation.md#remove-on-windows) before changing or deleting the extension.

## Frames and content

### Claude-3p deployment limit

Claude-3p is the app's separate profile for third-party-provider deployments. It is not an alternate spelling of the standard Claude-Data profile. Runtime inspection on Windows showed `--user-data-dir` pointing to `%LOCALAPPDATA%\Claude-3p` while the extension was installed in the standard profile. A controlled launch loaded React Developer Tools instead of this extension.

There is a second limit: the inspected official Claude 5.11492.5 archive serves third-party pages from `app://localhost`. Its `app` scheme enables standard, secure, fetch, and service-worker privileges, but does not set `allowExtensions`. That privilege defaults to false in [Electron's CustomScheme API](https://github.com/electron/electron/blob/main/docs/api/structures/custom-scheme.md). The extension's manifest and runtime scope also support HTTPS pages only. Moving the extension directory alone would not enable this UI.

**Claude-3p is not supported.** The installer does not detect or configure this deployment. Do not use the standard-profile installation instructions for Claude-3p. No alternate launcher, extra window, or experimental styling route is provided.

This project does not change Claude's archive, provider selection, protocol privileges, or security settings to bypass the limit. Existing installation receipts prove file installation, not successful display in Claude-3p.

The manifest loads content scripts in supported chat and artifact frames, including nested document frames. The runtime checks each frame's origin and rejects unsupported pages. Authentication and API pages are excluded.

For `about:srcdoc` frames, it uses browser-provided ancestor origins. It does not read a cross-origin parent document. Font and direction checks run inside each supported frame.

Styles stay in memory. The controller does not edit message text, document content, table column order, or code. It handles supported Persian prose separately from declared programming languages.

The extension has no background worker, network requests, or storage permissions. Both variable fonts and their license notices are bundled locally; only the selected font is decoded and loaded. Nord and Gruvbox Dark share the same component and interaction rules with separate palettes.

## Version checks

The installer reads the installed manifest only after verifying the extension against its saved ownership digest. The available version comes from the embedded manifest. Version checks are read-only and use numeric comparison. The installer preserves saved feature choices and rejects downgrades.

## Diagnostics

In a supported frame's isolated extension context, `window.__claudePersianExtensionV1.snapshot()` reports controller counts and health. It does not include document text. `dispose()` asynchronously removes that frame's controller.

For a live check, verify the decoded font and computed direction on actual Persian text. Check chat, document artifacts, and comments separately. Compare document text, table order, and control layout before and after. Repeat after a reload and a normal app restart.

Keep private text, chat URLs, screenshots, and document identifiers out of committed reports. Record only results and limits. See [test coverage](testing.md) for what is currently verified.

## Build from source

```sh
node scripts/build-extension.cjs /absolute/path/to/extension
```

The generated directory includes the font and required license notices. Building the directory alone does not configure Claude's startup. Use the standalone installer for installation.
