# Terminal installer

The standalone macOS and Linux installer uses Bubble Tea 2 and Lip Gloss 2. Its English interface uses the Nord palette. You do not need Node.js, Go, Homebrew, a DMG, or an Apple developer certificate to run it.

## Availability

[Version 1.1.3](https://github.com/Ssisakhti/Claude-Desktop-Tweaks/releases/tag/v1.2.0) includes standalone Apple silicon and Intel executables. The release workflow creates drafts for review before later versions are published.

## Install with one command

```sh
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 https://raw.githubusercontent.com/Ssisakhti/Claude-Desktop-Tweaks/main/scripts/install.sh | bash
```

The bootstrap detects macOS or Linux and x64 or arm64, resolves one release version, downloads the executable and its SHA-256 checksum from that release, verifies the download, and opens the terminal interface. It installs into a private, versioned folder under `~/Library/Application Support/Claude Desktop Tweaks/releases/`. It preserves existing executables with different contents and does not edit your shell profile or PATH. The checksum detects corrupted or mismatched downloads; release authenticity relies on HTTPS and the repository's release access controls.

The command prints the full path to reopen settings. Run that path or repeat the installation command to change your choices. `--no-launch` downloads and verifies without opening the interface. `--version v1.2.0` pins a particular published release.

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

On macOS, the official Claude Desktop app is required. If Claude is missing, the interface names the official download source and destination and waits for an explicit **Y**. Enter does not approve the download.

After approval, the installer downloads the official Claude disk image, mounts it temporarily, verifies the Anthropic signature and macOS assessment, and copies the unmodified app into your Applications folder. It ejects the image afterward. The process uses built-in macOS tools. You do not open a DMG manually. Existing apps are preserved. If macOS blocks verification, the installer stops; it does not disable protection or remove quarantine attributes.

Quit Claude before applying extension changes. If migrating from an old Hammerspoon startup block, quit Hammerspoon too. The installer never quits either app. Open Claude normally after success. The extension uses the existing unofficial startup hook; future Claude updates can affect compatibility.

## Ubuntu and Debian

The standalone installer supports the **official** Claude Desktop package on Ubuntu 22.04+ and Debian 12+, x64 and arm64. AppImage, Flatpak, unofficial repackaging, other distributions, and Windows are not supported. Linux support is experimental until graphical acceptance is completed. Package compatibility was inspected read-only in official Claude 5.11492.5; container tests are not a graphical Claude test.

Use the same one-command installation above. Linux executables need no Node.js, Go, or package manager runtime. The bootstrap needs Bash, curl, and a SHA-256 utility. Settings live under `${XDG_DATA_HOME:-~/.local/share}/Claude Desktop Tweaks/`; Claude's extension lives under `${XDG_CONFIG_HOME:-~/.config}/Claude/extensions/`. Absolute XDG paths inside your home are supported. Paths outside your home and symbolic installation parents are rejected, with existing files preserved.

If Claude is missing, the interface requires **Y** before starting installation. PolicyKit (`pkexec`) requests administrator permission through the desktop's authentication agent. The helper rejects additional primary keys, checks the vendor signing-key fingerprint, and adds Anthropic's signed apt repository. It downloads Claude using an isolated vendor-only apt index, then installs `claude-desktop` and required packages. Missing curl/GnuPG prerequisites are installed through apt after consent. Repository settings remain for package updates. Existing differing repository files are preserved and installation stops. If PolicyKit or its authentication agent is unavailable, install the official package using [Anthropic's instructions](https://support.claude.com/en/articles/10065433-install-claude-desktop), then rerun setup. Applying tweaks itself needs no administrator permission.

Quit Claude before applying. Setup creates an owned user desktop entry with the same ID as the vendor entry, including its New Chat/New Code actions. Open Claude from your applications menu or its normal dock entry afterward. `REACT_PROFILE=1` is scoped to that launch, not your entire desktop session. Directly running `claude-desktop` in a terminal bypasses the user desktop entry; use `env REACT_PROFILE=1 claude-desktop` for that route. Existing unowned desktop entries or extensions are not overwritten. The unofficial hook is checked before changes, but future vendor changes can still require an update.

To change or disable features, rerun the printed settings command or the bootstrap and apply your selections with Claude closed. All-off retains the extension and launcher but disables all three tweaks. To remove the Linux installation, first quit Claude and preserve the receipt and backups. Remove only the owned user desktop entry, then restore any backed-up extension. Without an earlier extension, remove the owned extension only after disabling its profiling launch. Extension replacement backups are stored beside the extension under `.claude-desktop-tweaks-backups/`, so updates also work when XDG config and data are on separate filesystems. The vendor desktop entry in `/usr/share/applications/` is unchanged and becomes active again. Preserve any user-modified files rather than deleting them. There is no automatic uninstall command yet.

## Files, recovery, and privacy

On macOS, the Go installer preserves the existing extension ID, startup LaunchAgent, rollback receipt, `REACT_PROFILE` environment handling, and legacy Hammerspoon migration. It uses an exclusive installation lock and backs up replaced extension files and the previous receipt. Failures trigger rollback; concurrent unrelated changes are preserved. The UI does not access or send conversations.

On macOS, backups and the receipt are under `~/Library/Application Support/Claude Desktop Tweaks/`. Follow [extension rollback instructions](extension.md#rollback-of-the-local-installation) for removal. Failed writes, syncs, closes, and short writes now trigger cleanup of the newly created file, including the installation lock. The installer reports the original disk error instead of claiming another installation is running. Normal quit requests wait for transaction cleanup. A hard process kill or power loss can still leave a lock. If the filesystem itself prevents identity checks or deletion, the installer reports the cleanup failure and preserves unverified or replaced files. Identity checking and removal are not atomic protection against a hostile process with the same user identity; installation folders are private and cooperating installers honor the exclusive lock. Preserve the lock and backups, confirm no installation process is still active, and inspect the receipt and installed files before removing a stale lock or retrying. Do not delete backups to resolve an error.

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
