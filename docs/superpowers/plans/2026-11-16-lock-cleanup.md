# Failed installation lock cleanup

Goal: Remove files created by failed exclusive writes, preserve foreign replacements, report disk failures accurately, and publish the patch release.
Cause: exclusive creates the lock before Write/Sync/Close, but does not remove it on failure. Install treats every acquisition failure as an existing active installation.

1. Reproduce a real failed write using a child-only file-size resource limit, then verify immediate installation retry.
2. Own the lifecycle of an exclusively created file: capture its identity, handle short writes and Write/Sync/Close errors, remove only that same regular file on failure, and retain any cleanup error.
3. Exercise ENOSPC, EIO, short writes, replacement preservation, and retry with real temporary files and faulting I/O wrappers.
4. Run all Go, JavaScript, font, and Lua checks and request an independent review.
5. Publish v1.1.1, verify the released checksums, and test the public bootstrap without changing Claude settings.

No dependency, Claude bundle, runtime controller, or live user profile changes are required for the fix. Hard termination or an inability to unlink due to a continuing filesystem failure cannot guarantee cleanup; report this accurately without deleting an unverified lock.

## Verification ledger
- The original implementation failed the subprocess regression: the failed acquisition left an empty installation lock.
- Write, Sync, Close, and short-write failures now close the descriptor and remove the same newly created file. Foreign replacements remain intact. Original and cleanup errors are preserved.
- A mutation that ignored final lock-release errors fails the release-error regression.
- Independent review found no important defect; it confirmed fresh Go race tests and the real subprocess write failure. Same-file checking/unlinking is not atomic against malicious same-user replacement, and inability to stat/unlink is reported without deleting an unverified path.
