# Claude Desktop Tweaks

Estedad fonts, paragraph direction, and a Nord dark theme for Claude Desktop on macOS and official Ubuntu/Debian Linux.

The tweaks run in memory inside the official app. Claude's files, signature, ASAR archive, and security settings stay unchanged. The automatic extension applies them at page load without controlling the keyboard or mouse. The existing Hammerspoon console integration remains available. Neither method opens Chrome.

[Installation and removal](docs/installation.md) · [Testing and limitations](docs/testing.md) · [Changelog](CHANGELOG.md)

## Features

- One official Estedad variable WOFF2 is included locally and covers weights 100–900. No font download is needed at runtime.
- Each paragraph gets a direction based on its text, including Persian paragraphs that start with an English word.
- Supported chat, document, and comment frames are handled separately.
- Text inside table cells is handled without changing column order or control layout.
- Removed fonts and styles are restored within the same document.
- Nord colors apply in dark mode.

## Standalone terminal installer

The new English Bubble Tea interface provides independent switches for the Estedad font, Nord theme, and automatic RTL. Its standalone macOS and Linux executables needs no Node.js or Go. It checks prerequisites, requests approval before downloading missing Claude, and preserves installation backups.

Install with one command:

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

See the [terminal installer guide](docs/terminal-installer.md) for controls, prerequisite approval, settings changes, and recovery. The existing Node-based method below remains available.

## Automatic installation on macOS

The extension applies fonts, text direction, and colors automatically in chat, document artifacts, and comments. It needs no Hammerspoon watcher or idle input period. Local acceptance passed on Claude Desktop 5.11492.5, including an ordinary app launch and nested document reloads.

Save work and quit Claude, then run:

```sh
npx --yes --cache="$(mktemp -d)" --package=https://github.com/Ssisakhti/Claude-Desktop-Tweaks/archive/refs/heads/main.tar.gz claude-desktop-tweaks --install-extension
```

Node.js 22.12.0 or later is required. Quit Hammerspoon too when migrating from the old integration; the installer backs up and removes its startup block. Then open Claude normally. No Python or manual startup configuration is needed.

Follow the [complete automatic installation guide](docs/extension.md#install-on-macos) for previews, migration, verification, updates, and rollback. The guide also covers updates and removal. The method uses an unofficial startup hook; a macOS logout/login cycle remains untested.

## Hammerspoon installation

You need macOS, the official Claude Desktop app, Node.js 22.12.0 or later, npm, and Hammerspoon. Give Hammerspoon Accessibility permission and keep it running while you use the tool.

```sh
git clone https://github.com/Ssisakhti/Claude-Desktop-Tweaks.git
cd Claude-Desktop-Tweaks
npm ci
node bin/claude-desktop-tweaks.cjs --dry-run
node bin/claude-desktop-tweaks.cjs --install
```

In Hammerspoon, choose **Reload Config**. Bring Claude to the front and leave the mouse and keyboard idle for at least two seconds. Keep the configuration backup path printed by the installer. See the [installation guide](docs/installation.md) before replacing an active installation.

The installer copies the runtime to a private Hammerspoon directory. Once installed, the watcher does not depend on the source checkout remaining in place.

## Supported behavior and limits

The standalone installer supports macOS and the official Linux package on Ubuntu 22.04+ and Debian 12+ (x64 and arm64). Linux support is experimental: package compatibility and container tests pass, but graphical chat/artifact acceptance has not been run on Linux. Hammerspoon and the Node installer remain macOS-only. Hammerspoon controls Claude's interface, so the console may appear briefly. User input, an unverified context, or developer tools already open can delay or stop a transaction.

The latest local cold-start check completed on the first attempt after waiting for guest content. A separate four-frame document check also completed without a retry. These local checks do not guarantee zero-retry behavior for every launch or app version. Chat navigation reuses the in-page controller when the frame layout is unchanged. Reloads without an observed loading or frame-layout change may need **Reapply in Claude in 3 seconds** from the **CDT** menu. Native Quick Entry without an HTML frame is outside the tool's scope. A second simultaneous native window for ordinary chat has not been verified. See [testing and limitations](docs/testing.md).

The default runtime remains the guarded console route. An independent direct-dispatch experiment is documented in [background bootstrap investigation](docs/background-bootstrap.md); it is not enabled by installation.

The [automatic extension](docs/extension.md) uses the same controller for nested artifact frames. The Hammerspoon CLI does not install it; follow the separate guide and disable the old watcher before switching.

## Remove the integration

```sh
node bin/claude-desktop-tweaks.cjs --remove
```

Reload the Hammerspoon configuration afterward. Removing the configuration does not itself remove styles already applied in Claude's memory. After saving your work, quit Claude completely and reopen it to clear those styles. The tool does not quit the app for you.

## Development

```sh
npm test
npm run check:fonts
npm audit --audit-level=low
```

Run the Lua suites as well; the commands are in the [testing guide](docs/testing.md). Automated tests and live app checks are reported separately.

## Licenses

Code license notices, the Estedad font license, and the Nord license are included in the repository. See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

This is an unofficial project. It is not affiliated with or endorsed by Anthropic.
