# Testing and limitations

## Automated checks

Run from the project directory:

```sh
npm ci
npm test
npm run check:fonts
npm audit --audit-level=low
```

Run both Lua suites with Lua 5.4:

```sh
python3 scripts/test-hammerspoon-lua.py --lua lua5.4 --module integrations/hammerspoon/claude-console.lua --test test/hammerspoon-console.test.lua
python3 scripts/test-hammerspoon-lua.py --lua lua5.4 --module integrations/hammerspoon/claude-console-auto.lua --test test/hammerspoon-console-auto.test.lua
```

These suites do not operate the live interface. They use synthetic fixtures to check frame discovery, context guards, exact source verification, clipboard protection, failure handling, and cleanup. Passing them does not establish every behavior of the real app. The font check verifies the embedded data for all nine weights.

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

A cold start of the final runtime in a completely new app process has not yet been verified in a live test. Keep this distinct from installation in an existing process.

Before inspecting frames, the watcher enables accessibility for the official app process. Electron provides the `AXManualAccessibility` attribute for assistive software on macOS. This does not grant system permissions. See the [official Electron accessibility guide](https://www.electronjs.org/docs/latest/tutorial/accessibility).

A reload that produces no useful accessibility change may remain undetected until you return to the window. The fallback does not reopen the console periodically while the window remains idle and active.

Native Quick Entry without an HTML frame is outside the tool's scope. A floating chat inside the main window is not a second native window. A second simultaneous native window for ordinary chat has not been verified. Do not broaden the accepted frame boundary to make an unsupported window pass.

Multi-item clipboards are not fully supported. If the clipboard cannot be preserved, the transaction stops before changing it. Existing user developer tools and nonempty prompts must not be overwritten. A cleanup failure must stop further automatic work.
