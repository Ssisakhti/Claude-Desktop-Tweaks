# RTL and Nord interaction audit

Reproduce the four reported screenshots using the existing app without editing document text or submitting messages. Inspect computed styles and original CSS rules, including hover overlays, table borders, tooltip text, and unspecified-language code blocks. Keep private content and screenshots outside the repository.

Evidence so far: the original CDS hover/selection fills are translucent and used by `background-image` layers. The current Nord override makes them opaque, which can mask card content and row separators. The reported handoff is an unhighlighted code block with no language marker; its Persian prose is excluded by the existing programming-code guard.

1. Add regressions for translucent interaction layers, visible border tokens, prose-only code blocks, tooltip text, and preservation of real code/control layout.
2. Correct token semantics with Nord-derived alpha colors. Handle confirmed Persian prose separately from actual programming code and isolated labels separately from container layout.
3. Verify generated CSS and controller behavior with tests, then inspect the actual app with temporary, reversible in-memory styles. Compare text and table structure locally. Include hover, focus, selection, disabled states, and light mode.
4. Build and review the resulting extension. Never replace a live instance or quit Claude automatically; test persistence only after the user closes the app if registration reload is required.

## Verification status

- Added and ran failing regressions before each implementation change.
- All 164 JavaScript tests pass, including source-code exclusions, isolated tooltip labels, and contrast after hover-layer compositing.
- Official variable font verification and both Lua suites pass (744 and 322 assertions).
- Review found and corrected unlabelled shell/SQL/assignment classification and control-element targeting.
- A temporary live stylesheet was adopted and its ghost-hover value read back as `#eceff413`. No chat text was changed or sent.
- Reproduced the disappearing card in the live Discover page. Temporary styles were removed and cleanup was confirmed.
- Review also found and corrected stale RTL rules when a reused navigation title changes to English.
- A first revision-6 installation exposed additional live defects: stacked card hover falls back to an opaque neutral token, compound inputs had an independent forced background, and a nested accent coachmark inherited the forced page background.
- Corrected all three. Live temporary theme updates confirmed the forced-hover card overlay is 5% Nord white, card text/icons stay visible, search input stays transparent, and the coachmark uses Nord8 behind Nord0 text. The main-window screenshots confirmed the card, search field, hovered table row, and coachmark.
- Added current faded-label wrapper support after inspecting the actual navigation markup.
- Revision 7 is built and reviewed. Its final installed startup, prose fence, navigation tooltip, and artifact checks are pending user Quit. No document text or messages were changed.

## Composer follow-up

The native suggestion overlay uses `data-prompt-suggestion-ghost` and a secondary-text color close to the editor foreground. The visible shell is `[data-cds="ChatComposer"] > .rounded-composer`; the editor suppresses its own outline. Add a scoped suggestion foreground and a two-pixel inset focus outline on the shell. Keep native suggestion visibility and acceptance behavior unchanged.

Live checks confirmed suggestion RGB 161/184/208 versus editor RGB 236/239/244, a two-pixel Nord8 outline on focus, no outline after blur, unchanged draft content, and identical composer bounds. No suggestion was accepted and no message was sent. Temporary rules were merged into the already owned dark-theme sheet, the extra audit sheet and private draft snapshot were removed, and DevTools was closed. Persistent installation and the full restart/RTL/artifact pass still await the user's planned Quit.

The user found the initial two-pixel cyan composer focus too strong. Refine only this indicator to a one-pixel inset Nord9 outline. Keep other focus indicators and suggestion colors unchanged.
