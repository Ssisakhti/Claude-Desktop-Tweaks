#!/bin/bash
# Download a standalone release. No runtime, package manager, or sudo is needed.
set -euo pipefail
release=latest
launch=1
fail() { printf 'Claude Tweaks: %s\n' "$*" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
 case "$1" in
  --version) [ "$#" -ge 2 ] || fail 'Missing release version.'; release=$2; shift 2;;
  --no-launch) launch=0; shift;;
  --help|-h) printf '%s\n' 'Claude Desktop Tweaks' 'Options: --version v1.3.0  --no-launch'; exit 0;;
  *) fail 'Unknown option. Use --help.';;
 esac
done
case "$(uname -s)" in
 Darwin) platform=darwin;;
 Linux) platform=linux;;
 *) fail 'This installer supports macOS, Ubuntu, and Debian.';;
esac
case "$(uname -m)" in arm64|aarch64) arch=arm64;; x86_64|amd64) arch=amd64;; *) fail 'Unsupported processor architecture.';; esac
repository=https://github.com/Ssisakhti/Claude-Desktop-Tweaks
if [ "$release" = latest ]; then
 effective=$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --max-time 60 --output /dev/null --write-out '%{url_effective}' "$repository/releases/latest") || fail 'No release could be found. No files were installed.'
 release=${effective##*/}
fi
case "$release" in v[0-9]*) ;; *) fail 'Invalid release version.';; esac
case "$release" in *[!A-Za-z0-9._-]*|*..*) fail 'Invalid release version.';; esac
asset=claude-tweaks_${platform}_$arch
scratch=$(mktemp -d "${TMPDIR:-/tmp}/claude-tweaks.XXXXXX")
staged=
cleanup() { rm -rf "$scratch"; if [ -n "$staged" ]; then rm -f "$staged"; fi; }
trap cleanup EXIT
trap 'exit 130' INT TERM
printf 'Downloading Claude Desktop Tweaks %s for %s…\n' "$release" "$arch"
base=$repository/releases/download/$release
for name in "$asset" checksums.txt; do
 curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --max-time 180 --output "$scratch/$name" "$base/$name" || fail 'Release download failed. No files were installed.'
done
expected=$(awk -v name="$asset" '$2 == name { value=$1; count++ } END { if (count != 1) exit 1; print value }' "$scratch/checksums.txt") || fail 'Release checksum is missing or ambiguous.'
[ "${#expected}" -eq 64 ] || fail 'Invalid release checksum.'
case "$expected" in *[!0-9a-f]*) fail 'Invalid release checksum.';; esac
hash_file() {
 if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
 elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
 else fail 'A SHA-256 tool is required (sha256sum or shasum).'; fi
}
[ "$(hash_file "$scratch/$asset")" = "$expected" ] || fail 'Checksum verification failed. No files were installed.'
printf 'Download verified. No Node.js or Go installation is needed.\n'
uid=$(id -u)
safe_directory() {
 local directory=$1 metadata owner mode
 [ ! -L "$directory" ] || fail 'A symbolic installation directory was preserved.'
 if [ ! -e "$directory" ]; then mkdir -m 700 "$directory"; fi
 [ -d "$directory" ] || fail 'An installation path is not a directory.'
 metadata=$(stat -f '%u %Lp' "$directory" 2>/dev/null) || metadata=$(stat -c '%u %a' "$directory")
 owner=${metadata%% *}; mode=${metadata##* }
 [ "$owner" = "$uid" ] || fail 'An installation directory has a different owner.'
 (( (8#$mode & 0022) == 0 )) || fail 'An installation directory is writable by other users.'
}
safe_directory "$HOME"
if [ "$platform" = darwin ]; then
 base="$HOME/Library/Application Support/Claude Desktop Tweaks"
else
 data_base=${XDG_DATA_HOME:-$HOME/.local/share}
 case "$data_base" in /*) ;; *) data_base="$HOME/.local/share";; esac
 base="$data_base/Claude Desktop Tweaks"
fi
case "$base" in "$HOME"/*) ;; *) fail 'The installation directory must be inside your home directory.';; esac
remaining=${base#"$HOME"/}/releases/$release/$arch
current=$HOME
while [ -n "$remaining" ]; do
 part=${remaining%%/*}
 case "$part" in ''|.|..) fail 'Unsafe installation directory.';; esac
 if [ "$remaining" = "$part" ]; then remaining=; else remaining=${remaining#*/}; fi
 current=$current/$part
 safe_directory "$current"
done
target=$current/claude-tweaks
[ ! -L "$target" ] || fail 'An existing symbolic executable was preserved.'
if [ -e "$target" ]; then
 [ -f "$target" ] || fail 'An existing installation path was preserved.'
 [ "$(hash_file "$target")" = "$expected" ] || fail 'An existing executable differs from this release and was preserved.'
else
 staged=$(mktemp "$current/.claude-tweaks.XXXXXX")
 cp "$scratch/$asset" "$staged"
 chmod 700 "$staged"
 mv -n "$staged" "$target"
 [ ! -L "$target" ] && [ "$(hash_file "$target")" = "$expected" ] || fail 'The destination changed during installation.'
 rm -f "$staged"; staged=
fi
printf 'Settings command: %q\n' "$target"
if [ "$launch" -eq 1 ]; then
 [ -r /dev/tty ] && [ -w /dev/tty ] || fail 'Open a terminal to run the printed settings command.'
 "$target" </dev/tty >/dev/tty
fi
