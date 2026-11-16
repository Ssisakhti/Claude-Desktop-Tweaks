# Terminal installer

The standalone macOS installer uses Bubble Tea 2 and Lip Gloss 2. Its English interface uses the Nord palette. You do not need Node.js, Go, Homebrew, a DMG, or an Apple developer certificate to run it.

## Availability

[Version 1.1.0](https://github.com/Ssisakhti/Claude-Desktop-Tweaks/releases/tag/v1.1.0) includes standalone Apple silicon and Intel executables. The release workflow creates drafts for review before later versions are published.

## Install with one command

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

The bootstrap detects Apple silicon or Intel, resolves one release version, downloads the executable and its SHA-256 checksum from that release, verifies the download, and opens the terminal interface. It installs into a private, versioned folder under `~/Library/Application Support/Claude Desktop Tweaks/releases/`. It preserves existing executables with different contents and does not edit your shell profile or PATH. The checksum detects corrupted or mismatched downloads; release authenticity relies on HTTPS and the repository's release access controls.

The command prints the full path to reopen settings. Run that path or repeat the installation command to change your choices. `--no-launch` downloads and verifies without opening the interface. `--version v1.1.0` pins a particular published release.

## Controls and settings

- Arrow keys or J/K: move between features.
- Space: toggle the selected feature. Keys 1–3 toggle each feature directly.
- Enter: continue, review, then apply.
- Escape: return without applying.
- Q: exit. Unsaved choices require confirmation before discard.
- R: refresh system checks, including whether Claude has closed.

The font, theme, and RTL options are independent. All eight combinations are supported, including all features off. Existing preferences are read from the installation receipt. Selecting all-off installs a controller that leaves Claude's font, theme, and text direction unchanged on its next launch.

Estedad is the official variable WOFF2, with weights 100–900 in one compact file. The font option affects Persian content in Claude; terminal text uses your terminal's configured font. Theme colors are applied in Claude's dark mode. RTL applies to supported text content and preserves code and table column order.

The interface fits terminals of at least 60 columns by 22 rows; wider terminals show a side panel. Smaller windows display a resize message. Terminal color support is detected automatically, including the `NO_COLOR` setting.

## Prerequisites and consent

macOS and the official Claude Desktop app are required. If Claude is missing, the interface names the official download source and destination and waits for an explicit **Y**. Enter does not approve the download.

After approval, the installer downloads the official Claude disk image, mounts it temporarily, verifies the Anthropic signature and macOS assessment, and copies the unmodified app into your Applications folder. It ejects the image afterward. The process uses built-in macOS tools. You do not open a DMG manually. Existing apps are preserved. If macOS blocks verification, the installer stops; it does not disable protection or remove quarantine attributes.

Quit Claude before applying extension changes. If migrating from an old Hammerspoon startup block, quit Hammerspoon too. The installer never quits either app. Open Claude normally after success. The extension uses the existing unofficial startup hook; future Claude updates can affect compatibility.

## Files, recovery, and privacy

The Go installer preserves the existing extension ID, startup LaunchAgent, rollback receipt, `REACT_PROFILE` environment handling, and legacy Hammerspoon migration. It uses an exclusive installation lock and backs up replaced extension files and the previous receipt. Failures trigger rollback; concurrent unrelated changes are preserved. The UI does not access or send conversations.

Backups and the receipt are under `~/Library/Application Support/Claude Desktop Tweaks/`. Follow [extension rollback instructions](extension.md#rollback-of-the-local-installation) for removal. A hard process kill, power loss, or disk I/O failure while creating a lock can leave an installation lock. Normal quit requests wait for transaction cleanup. Preserve the lock and backups, confirm no installation process is still active, and inspect the receipt and installed files before removing a stale lock or retrying. Do not delete backups to resolve an error.

`claude-tweaks --check` prints read-only system status as JSON. `--help`, `--version`, and `--licenses` are available without changing Claude.

## Build and verify from source

Maintainers need Node.js and Go 1.27.4. End users do not.

```sh
node scripts/build-native-payload.cjs
cd native
go test -race ./...
go vet ./...
cd ..
bash scripts/build-native-release.sh dev
```

The build embeds the same JavaScript controller used by the existing extension. Tests reproduce all eight generated payloads. `assets/terminal/LICENSES.txt` contains licenses for the compiled Go dependencies and standard library; update it when dependencies change. Existing project, Estedad, and Nord notices remain included. The built executable exposes those notices through `--licenses`.

## UI references

The interface uses the state model of [Bubble Tea](https://github.com/charmbracelet/bubbletea), layout and color tools from [Lip Gloss](https://github.com/charmbracelet/lipgloss), and the official [Nord palette guidance](https://www.nordtheme.com/docs/colors-and-palettes/). [Charm's terminal forms](https://github.com/charmbracelet/huh) informed the separate review and explicit consent steps. Huh is not a runtime dependency.
