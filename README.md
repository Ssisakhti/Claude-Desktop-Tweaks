# Claude Desktop Tweaks

Estedad fonts, paragraph direction, and a Nord dark theme for Claude Desktop on macOS.

The tweaks run in memory inside the official app. Claude's files, signature, ASAR archive, and security settings stay unchanged. The tool uses Hammerspoon and Claude's built-in console. It does not open Chrome.

[Installation and removal](docs/installation.md) · [Testing and limitations](docs/testing.md) · [Changelog](CHANGELOG.md)

## Features

- Nine Estedad font weights are included locally. No font download is needed at runtime.
- Each paragraph gets a direction based on its text, including Persian paragraphs that start with an English word.
- Supported chat, document, and comment frames are handled separately.
- Text inside table cells is handled without changing column order or control layout.
- Removed fonts and styles are restored within the same document.
- Nord colors apply in dark mode.

## Get started

You need macOS, the official Claude Desktop app, Node.js 22.12.0 or later, npm, and Hammerspoon. Give Hammerspoon Accessibility permission and keep it running while you use the tool.

```sh
git clone https://github.com/Ssisakhti/Claude-Desktop-Tweaks.git
cd Claude-Desktop-Tweaks
npm ci
node bin/claude-desktop-tweaks.cjs --dry-run
node bin/claude-desktop-tweaks.cjs --install
```

In Hammerspoon, choose **Reload Config**. Keep the configuration backup path printed by the installer. See the [installation guide](docs/installation.md) before replacing an active installation.

The installer copies the runtime to a private Hammerspoon directory. Once installed, the watcher does not depend on the source checkout remaining in place.

## Supported behavior and limits

Only macOS and the official Claude Desktop app are supported. Hammerspoon controls Claude's interface, so the console may appear briefly. User input, an unverified context, or developer tools already open can delay or stop a transaction.

A cold start of the final runtime in a completely new app process has not yet been verified in a live test. A reload that produces no useful accessibility event may remain undetected until you return to the window. Native Quick Entry without an HTML frame is outside the tool's scope. A second simultaneous native window for ordinary chat has not been verified. See [testing and limitations](docs/testing.md).

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

Run both Lua suites as well; the commands are in the [testing guide](docs/testing.md). Automated tests and live app checks are reported separately.

## Licenses

Code license notices, the Estedad font license, and the Nord license are included in the repository. See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

This is an unofficial project. It is not affiliated with or endorsed by Anthropic.
