# Official Linux installer

User-approved target: official Claude Desktop on Ubuntu 22.04+ and Debian 12+, amd64 and arm64. Preserve the English Bubble Tea interface, Nord palette, one-command installation, and independent font/theme/RTL settings.

Reuse the Go interface and embedded controller. Add a separate Linux backend with XDG user paths, an owned desktop launcher with a process-scoped REACT_PROFILE environment, and transactional extension/receipt updates. Store extension replacement backups beside the extension to support separate XDG filesystems. Do not modify the vendor package, global environment, or application files. Preserve foreign desktop entries and extensions. Require Claude to be closed. Detect the official package and its extension hook before applying changes; fail clearly if incompatible.

Approaches: a portable binary alone cannot configure startup. Global environment changes affect other apps. A user desktop entry keeps the environment scoped to Claude and needs no administrator access for tweaks; this is the selected implementation. Official Claude installation, if absent, remains a distinct consent step using the vendor's signed apt repository. Never install unofficial packages.

Release linux_amd64 and linux_arm64 binaries with checksums. Test Linux transactions on Linux and macOS fixtures. Report graphical Claude tests separately; this Mac cannot establish Linux graphical acceptance.
