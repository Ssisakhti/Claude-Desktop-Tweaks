# Background console bootstrap investigation

## Scope

This investigation concerns the built-in console of the official macOS desktop app. It does not change the app, its signature, its ASAR archive, developer permissions, or security settings. Main-process debugging and app patching remain excluded.

The installed app version inspected was **4.16336.0**. Its packaged JavaScript was read without modifying or executing it. The observations below describe that version, not a stable vendor API contract.

## Why the ordinary menu can be accepted without opening tools

The packaged **Show Dev Tools** callback asks Electron for the app's focused web contents. It opens tools only when that call returns a value. Selecting the menu item through accessibility does not itself provide a focused web contents. This explains why a successful menu-selection return value is insufficient evidence that tools opened.

Electron documents that [`getFocusedWebContents()` can return null](https://www.electronjs.org/docs/latest/api/web-contents#webcontentsgetfocusedwebcontents). Hammerspoon documents [`selectMenuItem()` as menu selection](https://www.hammerspoon.org/docs/hs.application.html#selectMenuItem), not as confirmation of the application's resulting action.

## Concrete alternative: the official Show All Dev Tools menu

The inspected **Show All Dev Tools** callback directly opens tools for three existing host-owned web contents before considering focused content:

| Packaged reference | Construction and role | Expected source classification |
| --- | --- | --- |
| `V` | `BrowserWindow`, `MAIN_WINDOW` | The local main-window shell |
| `H` | `WebContentsView`, `CLAUDE_AI_WEB` | The actual `claude.ai` chat/task surface |
| `ho` | `WebContentsView`, `FIND_IN_PAGE` | The local find-in-page shell, when present |

The callback then optionally opens tools for the focused web contents if it is not already open. The direct `H` call is the useful difference: this route is not limited to the local shell and does not first require focused web contents.

This is a promising bootstrap experiment, not an established quiet startup path. It can create several tools windows. The app supplies only an undocked mode option; it does not request `activate: false`. Electron's documented [`openDevTools()` default is to activate the tools window](https://www.electronjs.org/docs/latest/api/web-contents#contentsopendevtoolsoptions). Background initiation therefore does not prove that focus remains with the user's previous app.

## Required live experiment

The research agent did not operate the live app. The coordinating agent performed the live check described below. The following procedure also applies to any repeat check.

1. Stop the normal integration and confirm completed cleanup before the experiment.
2. Refuse the experiment if any user tools window already exists. Record the app PID, supported source metadata, foreground application, and all existing window IDs.
3. Send **Developer > Show All Dev Tools** once to the official app while another application is foreground. Do not activate or focus Claude as a workaround.
4. Wait asynchronously for resulting windows. A selected menu item alone is not success.
5. Require new IDs, the exact official PID, valid supported source classification, and a current console probe before sending any installation code. Do not infer that the first or last window is the chat console.
6. Measure foreground changes. Distinguish initiating in the background, executing in the background, and avoiding focus transfer completely.
7. Close only newly created, verified, owned tools windows after their prompt and outstanding work are safe. Preserve all pre-existing windows and input. Stop if ownership or cleanup is uncertain.

If this works but steals focus or opens multiple visible tools windows, keep it behind an explicit experimental choice. Do not silently make it the default startup route.

## Coordinating agent's live result

The coordinating agent sent **Show All Dev Tools** while another application was foreground. Two new tools windows appeared, and exactly one tools title matched the current supported source URL. No monitored user input occurred during the check.

An immediate observation after menu selection still showed the other application in front. After asynchronous tools creation, the actual system foreground changed to Claude. The route therefore provides a workable explicit console bootstrap, but **does not preserve foreground focus**. A successful menu-selection return or an immediate foreground sample would have overstated the result.

The normal startup route was not switched to this approach. The two experiment-created tools were subsequently closed after their identities and empty prompts were verified; the pre-existing app windows were preserved. This result does not claim that all startup, frame-discovery, or cleanup cases have passed.

### Experimental native adapter and dispatch chain

A later live check exercised the actual `claude-console-direct-native.lua` and `claude-console-direct.lua` modules together. With the normal watcher stopped, the native adapter captured the current chat source before a fresh console was opened through **Show Dev Tools**. The source already had the stable integration's document identity record. The native adapter verified the source probe receipt and bound the new console before dispatch began.

Finder was then placed foreground. Three direct commands transferred the base64 data `NDI=`, decoded and checked the value `42`, and were followed by namespace cleanup. The transaction reported `complete`, `ok: true`, `released: true`, and `cleanupRequired: false`. The owned tools window was absent afterward, no monitored console interruption occurred, and Finder remained foreground during dispatch and release.

This qualifies a small transport transaction through the new modules after an explicit foreground bootstrap. It does not qualify the full font/style payload, cold startup, document frame discovery, or bootstrap without focus transfer. The test did not change the app's main process, files, signature, or security settings. The experimental modules remain outside the default runtime.

### Complete production payload plan

The experimental builder now separates the official font data and trusted production modules into 33 bounded commands. Semantic tests execute the actual controller in all five supported frame kinds, check the complete font bytes and controller health, preserve text and table structure, and confirm that temporary namespace cleanup retains the installed controller. Generated commands use no `eval` or `Function`.

A subsequent live chat check used a fresh normal app process with the default watcher absent. After explicit console bootstrap and source receipt verification, Finder was foreground while the full plan ran. All 33 commands and cleanup completed, controller health passed, the owned tools closed, and the clipboard was unchanged. This extends the small-data result above to the production font/controller payload in chat. It does not establish quiet startup or automatic acceptance of every frame or future app version.

Local prompt focus is verified before AXValue writes, after their exact echo, and immediately before Return. A pending focus acknowledgement delays the write without restarting the deadline. This is local console focus; the direct adapter does not activate Claude. Child-frame handoff additionally pins the chat parent's exact accessibility element and the actual target frame, with independent browser ancestry classification before document identity creation.

## Other approaches and boundaries

### Process-local docked startup experiment

Read-only inspection of the same installed app found a process-local `CLAUDE_DEV_TOOLS` startup option. The value `bottom` requests the guest's tools directly at startup, without selecting a focused web contents through the external menu. This is an observed implementation detail, not a supported external API.

A live experiment stopped the normal watcher, confirmed the previous app exited, and launched the official executable once with this value in that process's environment. Finder was foreground before launch. The exact launched app PID exposed one embedded tools web area and one console prompt, with no separate tools window. Of 90 foreground samples over roughly 18 seconds, 87 showed Claude foreground. This route therefore did not preserve foreground focus. The experiment did not distinguish activation caused by ordinary app startup from activation caused by the embedded tools.

The experimental process was closed and a normal launch was verified to have no automatic console. No global environment, app files, signature, security settings, or private signed launch token were changed. The docked startup option is not enabled by the installer. Electron's [inspectable view implementation](https://github.com/electron/electron/blob/v44.9.3/shell/browser/ui/inspectable_web_contents_view.cc) distinguishes detached-window activation from embedded view focus, but that distinction alone does not establish quiet startup in the host app.

- An existing console can support asynchronous accessibility value writes and app-targeted key events. That proves a transport after bootstrap; it does not establish a startup mechanism by itself.
- Electron's `executeJavaScript()` and `openDevTools({activate:false})` are main-process APIs. Their existence does not grant an external integration access to them. No such access was introduced here.
- Local app metadata has no declared AppleScript scripting definition or `NSAppleScriptEnabled` flag. This is evidence against a declared scriptable JavaScript interface, not proof that all possible Apple events are unsupported.
- [Chromium documents an `auto-open-devtools-for-tabs` startup switch](https://github.com/chromium/chromium/blob/main/chrome/common/chrome_switches.h). Electron support for the installed app is unverified, and opening tools for every new content surface conflicts with the quiet-navigation goal. Do not treat the Chrome switch as a verified Claude feature.
- [Desktop MCP extensions connect tools to Claude](https://www.anthropic.com/engineering/desktop-extensions). Their documented purpose is not a general stylesheet or renderer-startup injection API.

## Recommendation

The official **Show All Dev Tools** route has now passed the limited bootstrap check above, including a confirmed unwanted foreground transfer. If it exposes the main chat console, combine it with the separately tested background transport only as an opt-in experiment. Keep the stable focused driver available until cold startup, documents, cleanup, input isolation, and focus behavior pass live acceptance checks.
