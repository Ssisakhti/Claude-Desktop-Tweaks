# Artifact extension support

The user has requested extension delivery, overriding the console-only route for this task. Keep app files, signatures, security settings, document text, and table order unchanged.

1. Test extension registration for nested frames and opaque document frames. Reject unrelated origins and authentication pages.
2. Build an unpacked extension from the existing classifier, controller, font data, and licensed modules. Use isolated content scripts, with no network or storage permissions. Provide explicit disposal and bounded status diagnostics.
3. Replace only the owned prototype after its old runtime has been disposed. Reload the target page. The installed runtime lacks extension reload support, so have the user quit Claude before changing registration.
4. Verify actual font loading and text direction in an existing document and comments. Compare document text and ordered table contents locally before and after; output only booleans and counts. Recheck chat.
5. Only after live success, install the tested extension and a login environment agent. Disable the old watcher startup with a recoverable configuration backup. Verify installation and report cold-start verification separately if restarting the app requires user action.
