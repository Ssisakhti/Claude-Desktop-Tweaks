# Testing and limitations

## Automated checks

Run from the project directory:

```sh
npm ci
npm test
npm run check:fonts
npm audit --audit-level=low
```

Run the Lua suites with Lua 5.4:

```sh
python3 scripts/test-hammerspoon-lua.py --lua lua5.4 --module integrations/hammerspoon/claude-console.lua --test test/hammerspoon-console.test.lua
python3 scripts/test-hammerspoon-lua.py --lua lua5.4 --module integrations/hammerspoon/claude-console-auto.lua --test test/hammerspoon-console-auto.test.lua
python3 scripts/test-hammerspoon-lua.py --lua lua5.4 --module integrations/hammerspoon/claude-console-direct.lua --test test/hammerspoon-console-direct.test.lua
python3 scripts/test-hammerspoon-lua.py --lua lua5.4 --module integrations/hammerspoon/claude-console-direct-native.lua --test test/hammerspoon-console-direct-native.test.lua
```

These suites do not operate the live interface. They use synthetic fixtures to check frame discovery, context guards, exact source verification, clipboard protection, failure handling, and cleanup. Passing them does not establish every behavior of the real app. The font check verifies the embedded official variable WOFF2 and its pinned SHA-256. Weights 100–900 use one font face.

### Clean installation checks

A separate temporary-home check exercised preview, installation, repeated installation, removal, backup restoration, unrelated configuration preservation, private runtime permissions, and installation from the packed distribution. All 32 checks passed. The packed distribution retained the variable font and license files, omitted the old TTFs, and installed only the stable runtime. Installed runtime files remained available after the source directory was moved. Dependencies for this check came from the existing local installation; this was not a new registry download or a first-run macOS permission test.

A live-profile check also stopped the integration and confirmed completed cleanup, removed its configuration block, verified the remaining configuration byte for byte, loaded the configuration with no integration present, and installed again. A subsequent preview reported no changes. Existing macOS permissions and retained runtime files were reused; this does not claim a new operating-system profile.

## Live app checks

Record live results separately. Save documents and drafts before testing. An installed configuration, an old status file, or a controller left by another run is not evidence of an independent successful test.

- Verify independent installation in chat, document, comment, and parent frames.
- Prove that a full reload replaced the previous document. Switching views or finding healthy resources is not enough to demonstrate reload recovery.
- Check active question cards, answered history, mixed text starting with English, comments, and tables.
- Confirm that stored text, column order, control direction, and control positions are preserved.
- Confirm that tools close and the clipboard is preserved. New clipboard content must not be overwritten with an older backup.
- Leave the app idle and confirm that the console does not reopen repeatedly.

Do not commit private text, screenshots, URLs, real document identifiers, or execution receipts. Record only the result and its limits. Do not attribute an action to the user without confirmation.

## Version 1.0.0 limitations

The quiet-navigation runtime has been checked in a completely new official app process. Earlier checks needed an automatic retry; the later guest-readiness regression check below completed on its first attempt. These local checks are not evidence for every supported app version. Keep it distinct from installation in an existing process.

Before inspecting frames, the watcher enables accessibility for the official app process. Electron provides the `AXManualAccessibility` attribute for assistive software on macOS. This does not grant system permissions. See the [official Electron accessibility guide](https://www.electronjs.org/docs/latest/tutorial/accessibility).

Quiet navigation is enabled by default. A reload that produces no observed loading or supported frame-layout change may require the CDT menu command to reapply. Returning to the window does not automatically open the console for a health check. Accessibility load events and identity changes alone do not prove a new document.

Native Quick Entry without an HTML frame is outside the tool's scope. A floating chat inside the main window is not a second native window. A second simultaneous native window for ordinary chat has not been verified. Do not broaden the accepted frame boundary to make an unsupported window pass.

Multi-item clipboards are not fully supported. If the clipboard cannot be preserved, the transaction stops before changing it. Existing user developer tools and nonempty prompts must not be overwritten. A cleanup failure must stop further automatic work.

## Quiet navigation acceptance checks

- Switch between 20 chats after initial application. Confirm no new console transaction and confirm newly rendered Persian text remains styled.
- Return from another app after more than 30 seconds. Confirm no health-check popup.
- Reload the page and restart Claude separately. Check recovery with an observed loading change, a new process, and manual reapplication when no reliable lifecycle evidence is available.
- Open a new document or artifact frame and confirm it still receives a discovery scan.
- Check empty and populated composers, Persian starting with an English word, multiline input, and composition input. Preserve text, caret, selection, table layout, and clipboard.
- Record the last scan reason and application receipt separately from the current waiting phase. Do not include chat URLs or content in reports.

These are live acceptance criteria, not claims of completed live verification.

### Local live checks for the quiet-navigation change

The following checks were completed locally on the official desktop app. These observations are separate from the synthetic suites.

| Check | Observed result |
| --- | --- |
| Chat navigation | Twenty UI switches between two existing sample chats, with idle pauses between batches. No additional console transaction was recorded during the run. Metadata updates can coalesce, so their count is not a switch count. |
| Cold app start | Confirmed the previous app stopped, then opened a new process. The runtime applied to chat, closed its tools, and restored the clipboard after one early failed transaction and automatic retry. |
| Full reload | Used the desktop View > Reload command. Chat styles were applied again and tools closed. |
| Document discovery | Opened an existing fictional sample. Artifact, artifact-content, and document frames were processed. The initial multi-frame transaction needed one automatic retry; the next scan successfully applied to the document and closed its tools. |
| Document and table | Compared the ordered accessible text and table structure before and after manual reapplication. Text and column order were unchanged. Persian and English blocks were also inspected visually. No document text was edited. |
| Comments | Inspected an existing comment and reply. A temporary mixed-language reply starting with English displayed right-aligned, then was cleared without submission. |
| Manual recovery | Invoked the same delayed runtime action used by the CDT menu. Exactly one scan completed, checked four already healthy frames, closed tools, and preserved the complete clipboard data. Menu wiring is separately covered by the synthetic suite; the menu click itself was not verified live. |
| Return after inactivity | Switched to Finder for more than 30 seconds and returned to Claude. No new transaction was recorded. |

The two automatic retries are a remaining latency limitation of these checks. Successful recovery does not establish a zero-retry first launch or first multi-frame installation. No messages or comments were submitted. The tests do not establish every window type, future DOM version, or clipboard format.

### Background dispatch and variable-font experiment

A separate in-memory experiment stopped the normal watcher and left Finder foreground. Direct application menu dispatch and an app-targeted DevTools shortcut did not produce a verified tools window. After explicitly opening one owned console, asynchronous `AXValue` writes and app-targeted Return executed a small calculation and a temporary DOM style change without bringing Claude foreground. The style change was removed.

The official Estedad 7.3 variable WOFF2 was then transferred as verified data chunks to that console. Chromium loaded it as one face with weight range `100 900`; font checks succeeded for 100, 400, 500, 600, 700, and 900. The temporary font face and data were removed. This proves background execution through an existing console, not a complete focus-free startup or a production replacement for the guarded driver. No main-process debugger, app patch, or security-setting change was used.

After switching the runtime to the official variable font, a live chat application completed on the first attempt with zero failed transactions. Tools closed and the clipboard was restored. This was an existing app process, not a new cold-start check of the variable-font runtime. The chat payload is 185,923 bytes before the driver's guard wrapper, compared with 2,190,489 bytes previously.

### Stabilization and diagnostics checks

The guarded driver now records total and per-phase durations and gives each new frame its own deadline under a fixed overall scan cap. Synthetic regressions cover progressive multi-frame scans, stalled frames, total caps, immutable timing snapshots, and failure evidence retained after successful retries. The independent direct-dispatch suite also executes generated JavaScript in Node to verify data isolation, namespace ownership, document replacement, and cleanup. It does not operate the live app.

The experimental native adapter has separate fake-native tests for capture-before ownership, source probe receipts, stale targets, scoped interaction tracking, watcher-registration rejection, local focus, exact prompt verification, and conservative release. Its generated bootstrap probe is executed in Node tests.

A later live check used both experimental modules together: fresh capture, explicit foreground console opening, a verified source probe, native binding, and direct dispatch with Finder foreground. The source already had the stable integration's document identity record. Three commands transferred base64 data `NDI=` and validated the decoded value `42`, then the transaction removed its namespace and closed its owned console. The result was `complete` with `ok: true`, `released: true`, `cleanupRequired: false`, no owned tools remaining, and no monitored console interruption. Finder remained foreground during dispatch and release. This was a small transport check, not the full font/style payload or a complete startup integration. Bootstrap without focus transfer remains unqualified; the default runtime was not changed.

### Startup readiness regression

A new-process live check with durable diagnostics captured `tools-title-mismatch` in `await-tools`: the watcher selected the local main-window shell before the guest chat existed, while the menu subsequently opened the guest console. The stable watcher now waits for guest content rather than starting against the temporary main shell. A repeated cold start then completed on its first attempt in about nine seconds, with tools closed and clipboard restored. This is a local check, not a zero-retry guarantee for every launch.

A subsequent document-opening check captured an `ambiguous-tools` failure caused by a separate nonmodal native AX dialog appearing beside the expected console. Native classification now requires an explicit nonmodal value, a complete bounded accessibility traversal, and no web area. Only when there is exactly one exact-title, correct-PID console may such a dialog be excluded from candidates. Unknown/modal windows remain ambiguous, and the ignored classification is rechecked until the source receipt proves ownership. The dialog is never targeted or closed.

After the native-dialog classification change, a live four-frame document scan completed on its first attempt in about 35 seconds. It applied to artifact, artifact-content, and document frames, skipped the already healthy chat, closed the console, and restored the clipboard. The unrelated native dialog was preserved. That final scan occurred in an existing process with the dialog already present; candidate-exclusion races are covered by the separate native metadata and state-machine regressions, not claimed as a fully repeated cold-document live test.

### First-document prompt traversal regression

A later cold-start and first-document sequence reproduced a different timeout after applying two child frames. Safe diagnostics repeatedly reported 4,000 visited console nodes, a truncated traversal, and zero prompt matches. The large echoed commands placed the prompt outside the bounded search. An automatic retry could succeed after reopening tools; that did not fix the first attempt.

The guarded apply wrapper now clears output only in its newly owned console, after verifying the document and before executing the payload. The payload's following receipt remains visible. Synthetic JavaScript checks cover ordering, document mismatch, receipt preservation, and missing or throwing `console.clear`; the latter cases do not execute the payload. Prompt diagnostics distinguish missing, duplicate, and truncated searches without returning content.

After this correction, a repeated live sequence started from a confirmed stopped app process. Chat application completed on the first attempt in about eight seconds. The first document opening then completed one four-frame scan in about 22 seconds, applying three child frames and skipping healthy chat. Both transactions closed tools and restored the clipboard, with zero failures and no truncated-prompt samples. This local sequence does not guarantee every app version or console setting.
