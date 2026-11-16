# Composer suggestion direction and generic installer naming

Goal: Correct the visible Persian suggestion before acceptance and keep product naming independent of Nord.
Cause: The suggestion uses an aria-hidden text layer separate from the contenteditable editor. Generic hidden-content exclusions omit it from direction styling.

- Treat only a recognized composer suggestion as a text surface; allow its own aria-hidden preview while preserving other hidden-content exclusions.
- Exclude suggestions from accepted editor content votes. Recompute replacement previews statelessly so a short English replacement cannot retain RTL hysteresis.
- Preserve text, editor input, buttons, visibility and acceptance behavior, and independent font/theme/RTL flags.
- Controller revision 8 carries the fix. Update the installer card label to Theme with Nord as its current value; do not fabricate additional theme implementations.
- Rename the existing v1.1.0 release title to Standalone installer. Publish the combined fixes through v1.1.2 without rewriting the existing v1.1.1 tag.

## Evidence
New regressions failed before the correction and passed afterward. A Chromium fixture using the production controller measured RTL Persian/mixed previews, zero right-edge gap for Persian preview text, an immediate one-word English LTR replacement, empty editor before acceptance, accepted editor RTL, and identical leading/trailing button geometry. The fixture is synthetic, not a live Claude chat. The user confirmed no natural suggestion is currently available. No chat text was changed or sent.

Additional scope regressions exposed and corrected an excluded-root fallback and an overbroad data-attribute exclusion outside the composer. Hidden ancestors and annotations remain excluded from direction, while unrelated document prose remains eligible. Marker removal/reuse also clears and restores preview direction. All fixes were observed failing before correction.
