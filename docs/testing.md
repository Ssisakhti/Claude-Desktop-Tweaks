# Tests and known limits

Automated tests and live app checks answer different questions. Passing a test suite does not prove that every Claude window or artifact displays correctly.

## Current coverage

| Area | Coverage |
| --- | --- |
| Feature selection | All eight enable/disable combinations with each font/theme pair, saved choices, changes, and defaults |
| Updates | Owned manifest detection, numeric versions, unknown metadata, downgrade refusal, saved choices, and explicit update confirmation |
| Installation | Ownership checks, foreign-file preservation, locks, backups, rollback, running-app guards, and prerequisite consent |
| macOS display | Live checks on Apple silicon with Claude 5.11492.5 cover sampled chat replies, document artifacts, comments, reloads, and ordinary app startup |
| Linux installation | Tests in isolated Ubuntu 22.04 and Debian 12 containers, including separate config/data filesystems |
| Linux executables | ARM64 execution and emulated x64 execution in Ubuntu; native x64 CI checks |
| Public download | Published checksums and a standalone download without Node or Go on PATH |
| Linux compatibility | Read-only inspection of the official Claude 5.11492.5 amd64 package and its startup hook |
| Suggestion preview | Controller tests and synthetic browser checks for Persian/English direction, text-slot sizing, and unchanged controls |

Vazirmatn and Gruvbox Dark have automated resource, style, and installer-preview checks. Sampled live macOS checks also cover ordinary chat replies, a Persian document artifact, its nested content frame, and artifact comments. The variable font decoded at weights 100–900; sampled Persian prose used RTL, and table containers retained LTR column layout. These checks used existing content without editing or sending messages.

Linux graphical chat/artifact checks, the PolicyKit permission dialog, and Windows MSIX startup/display checks are **not verified live**. Linux and Windows support remain experimental. Live suggestion-preview acceptance, Intel Mac display behavior, macOS login-time startup, native Quick Entry, and every artifact type are also outside the verified coverage.

User testing reported no visible changes on Windows and Linux. Version 1.5.3 addresses reproduced installer gaps: Windows standard-profile selection and Linux launcher configuration propagation. An Ubuntu 22.04 Gio launch check verifies the generated entry's environment, including paths with spaces, quotes, percent signs, and other special characters. It launches a local probe, not Claude. These checks do not establish that the reported display failures are resolved.

Windows profile tests cover modern, roaming, and MSIX virtualized markers, empty or ambiguous profiles, redirected unused roaming directories, and discovering a profile after prerequisite installation. A `Local State` marker proves prior initialization, not the active profile of every Claude build. Multiple initialized profiles require further diagnosis; setup does not guess. Windows completion requests a full repaint, but the reported Console display issue still needs a live recheck.

Version 1.5.3 adds a regression check for unsafe unused candidate parents while preserving rejection of unsafe selected profiles. Native Windows ACL fixtures cover the same distinction; local cross-compilation does not execute those fixtures. Terminal tests parse the rendered cells to verify an opaque full-size canvas and visible error details and controls. Synthetic error and settings previews were inspected; they do not replace a Windows Terminal check.

Windows user evidence identified an active Claude-3p profile and the loading of React Developer Tools. Read-only inspection of the official 5.11492.5 archive found a local `app://localhost` interface without the `allowExtensions` protocol privilege. Claude-3p is unsupported. Experimental deployment detection and styling prototypes were removed; no successful Claude-3p styling is claimed.

## Automated checks

From the project directory:

```sh
npm ci
npm test
npm run check:fonts
```

The font check verifies the bundled official Estedad and Vazirmatn variable fonts and their weights. JavaScript tests cover frame selection, text direction, font delivery, theme rules, controller cleanup, generated feature combinations, and bootstrap checks.

Generate the native payload and run the Go checks:

```sh
node scripts/build-native-payload.cjs
cd native
go test -race ./...
go vet ./...
```

Use Node.js 22.12.0 or later and Go 1.27.4 for development. End users need neither.

## Build release files

Run from the project directory:

```sh
bash scripts/build-native-release.sh dev
```

The build produces five executables in `dist/`: macOS and Linux, each for x64 and ARM64, and Windows x64, plus `checksums.txt`. The Go binary embeds the controller, font, and licenses. Update `assets/terminal/LICENSES.txt` when compiled dependencies change.

## Platform test inputs

The installer tests use temporary homes and simulated system commands. An optional read-only archive check accepts `CDT_TEST_ASAR` pointing to an official Claude ASAR. `CDT_CROSS_FS_HOME` enables the update test with separate config and data mounts inside an isolated test home.

Archive inspection is read-only and does not establish graphical behavior.

Disk-error tests use temporary files and a resource limit in a child process. They do not fill the host disk. They cover failed writes, syncs, closes, short writes, lock cleanup, immediate retry, and preservation of replaced files.

## Windows checks

Windows platform checks read the native architecture from the registry. Tests reject unsupported or missing architecture values before installation.

The native Windows runner checks the executable, all eight feature combinations, saved settings, file ownership and permissions, reparse-point rejection, environment value/type restoration, and refusal to overwrite concurrent changes. PowerShell bootstrap tests cover checksums, repeated installation, unsafe versions, and preservation of existing executables.

The official x64 MSIX archive and startup hook are inspected read-only. This does not verify ordinary Start Menu activation, account sign-in, chat rendering, or artifact behavior. Claude Setup download and permission prompts also require a live Windows check.

## Live acceptance checklist

- Start Claude normally with each selected feature combination.
- Check Persian, English, mixed text, lists, tables, inline code, and code blocks in chat.
- Check the suggestion preview and accepted editor text separately. Preserve draft text, caret position, and selection.
- Open a document artifact and its comments. Verify font decoding and direction in each frame.
- Reload the artifact, switch chats, and restart Claude. Confirm automatic loading.
- Check hover, focus, search fields, cards, tooltips, and table separators in dark mode.
- Confirm that text, table column order, and control layout stay unchanged.
- Disable each feature and then all features. Confirm the choices persist after restart.

Use synthetic content or user-approved existing content. Do not submit messages or edit documents without authorization. Do not commit private text, URLs, screenshots, account details, or document identifiers. Report the tested platform, app version, result, and remaining limits.
