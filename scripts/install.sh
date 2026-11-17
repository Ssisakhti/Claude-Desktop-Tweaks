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
  --help|-h) printf '%s\n' 'Claude Desktop Tweaks' 'Options: --version v1.5.0  --no-launch'; exit 0;;
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
scratch=$(mktemp -d "${TMPDIR:-/tmp}/claude-tweaks.XXXXXX")
staged= transfer_pid= progress_drawn=0 progress_tty=0
if [ -t 2 ] && [ "${TERM:-dumb}" != dumb ]; then progress_tty=1; fi
cleanup() {
 if [ -n "$transfer_pid" ]; then kill "$transfer_pid" 2>/dev/null || :; wait "$transfer_pid" 2>/dev/null || :; fi
 progress_end
 rm -rf "$scratch"
 if [ -n "$staged" ]; then rm -f "$staged"; fi
}
trap cleanup EXIT
trap 'printf "\nDownload cancelled. Run the install command to retry.\n" >&2; exit 130' INT TERM
# Progress helpers
progress_columns() {
 local columns=
 columns=$(stty size <&2 2>/dev/null) || columns=
 columns=${columns##* }
 case "$columns" in ''|*[!0-9]*) columns=${COLUMNS:-80};; esac
 if [ "$columns" = 0 ]; then columns=${COLUMNS:-80}; fi
 case "$columns" in ''|*[!0-9]*) columns=80;; esac
 printf '%s' "$columns"
}
progress_metrics() {
 awk -v bytes="$1" -v total="$2" -v elapsed="$3" -v frame="${4:-0}" 'BEGIN {
  if(elapsed<1)elapsed=1;
  if(total>0){percent=int(bytes*100/total);if(percent>100)percent=100;filled=int(percent*24/100);bar="";for(i=0;i<24;i++)bar=bar (i<filled?"#":"-");printf "[%s] %d%%\n%.1f / %.1f MB · %.0f KB/s",bar,percent,bytes/1048576,total/1048576,bytes/1024/elapsed}
  else printf "%s Receiving data…\n%.1f MB · %.0f KB/s",substr("|/-\\",frame%4+1,1),bytes/1048576,bytes/1024/elapsed;
 }'
}
progress_frame() {
 [ "$progress_tty" -eq 1 ] || return 0
 local phase=$1 detail=$2 color= reset=
 if [ "$(progress_columns)" -lt 60 ]; then progress_end;progress_tty=0;printf '%s\n' "$phase" >&2;return 0;fi
 if [ -z "${NO_COLOR:-}" ]; then color=$'\033[38;2;136;192;208m'; reset=$'\033[0m'; fi
 printf '\r\033[K  %s%s%s\n\033[K  %s\n\033[K  %s\033[2A\r' "$color" "${phase:0:56}" "$reset" "${detail%%$'\n'*}" "${detail#*$'\n'}" >&2
 progress_drawn=1
}
progress_end() {
 if [ "$progress_drawn" -eq 1 ]; then printf '\n\n\n' >&2; progress_drawn=0; fi
}
run_transfer() {
 local phase=$1 output=$2 url=$3 timeout=$4 received=0 total=0 started=$SECONDS frame=0 detail=
 if [ "$progress_tty" -eq 0 ]; then printf '%s\n' "$phase"; fi
 : > "$scratch/headers"
 curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 15 --speed-limit 1 --speed-time 30 --max-time "$timeout" --max-filesize 67108864 --dump-header "$scratch/headers" --output "$output" --write-out '%{url_effective}' "$url" > "$scratch/effective" &
 transfer_pid=$!
 while kill -0 "$transfer_pid" 2>/dev/null; do
  if [ "$progress_tty" -eq 1 ]; then
   [ ! -f "$output" ] || received=$(wc -c < "$output" | tr -d ' ')
   total=$(awk 'BEGIN{n=0} /^HTTP\//{n=0} tolower($1)=="content-length:"{gsub("\r","",$2);if($2 ~ /^[0-9]+$/ && $2<=67108864)n=$2} END{print n}' "$scratch/headers")
   case "$phase" in
    'Downloading installer'*) detail=$(progress_metrics "$received" "$total" "$((SECONDS-started))" "$frame");;
    *) detail="$(printf '%s' '|/-\' | cut -c "$((frame%4+1))") Working…"$'\nPlease wait…';;
   esac
   progress_frame "$phase" "$detail"
   frame=$((frame+1))
  fi
  sleep 0.2
 done
 if wait "$transfer_pid"; then transfer_pid=; else transfer_pid=;progress_end;return 1;fi
 if [ "$progress_tty" -eq 1 ]; then
  received=$(wc -c < "$output" | tr -d ' ')
  total=$(awk 'BEGIN{n=0} /^HTTP\//{n=0} tolower($1)=="content-length:"{gsub("\r","",$2);if($2 ~ /^[0-9]+$/ && $2<=67108864)n=$2} END{print n}' "$scratch/headers")
  case "$phase" in
    'Downloading installer'*) detail=$(progress_metrics "$received" "$total" "$((SECONDS-started))" "$frame");;
    *) detail="$(printf '%s' '|/-\' | cut -c "$((frame%4+1))") Working…"$'\nPlease wait…';;
   esac
   progress_frame "$phase" "$detail"
   frame=$((frame+1))
 fi
}
# End progress helpers

if [ "$progress_tty" -eq 1 ]; then printf '  CLAUDE DESKTOP TWEAKS\n  Ctrl+C Cancel\n\n' >&2; fi
if [ "$release" = latest ]; then
 run_transfer 'Finding the latest release…' "$scratch/metadata" "$repository/releases/latest" 60 || fail 'Could not find the latest release. Check your connection and run the command again.'
 effective=$(cat "$scratch/effective")
 release=${effective##*/}
fi
case "$release" in v[0-9]*) ;; *) fail 'Invalid release version.';; esac
case "$release" in *[!A-Za-z0-9._-]*|*..*) fail 'Invalid release version.';; esac
asset=claude-tweaks_${platform}_$arch
base=$repository/releases/download/$release
run_transfer "Downloading installer · $release" "$scratch/$asset" "$base/$asset" 180 || fail 'Download stopped or failed. Check your connection and run the command again. No files were installed.'
run_transfer 'Downloading checksums…' "$scratch/checksums.txt" "$base/checksums.txt" 60 || fail 'Could not download checksums. Run the command again. No files were installed.'
if [ "$progress_tty" -eq 1 ]; then progress_frame 'Verifying download…' 'Checking SHA-256 integrity.
Please wait…'; else printf 'Verifying download…\n'; fi
expected=$(awk -v name="$asset" '$2 == name { value=$1; count++ } END { if (count != 1) exit 1; print value }' "$scratch/checksums.txt") || fail 'Release checksum is missing or ambiguous.'
[ "${#expected}" -eq 64 ] || fail 'Invalid release checksum.'
case "$expected" in *[!0-9a-f]*) fail 'Invalid release checksum.';; esac
hash_file() {
 if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
 elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
 else fail 'A SHA-256 tool is required (sha256sum or shasum).'; fi
}
[ "$(hash_file "$scratch/$asset")" = "$expected" ] || fail 'Checksum verification failed. No files were installed.'
progress_end
printf 'Download verified.\n'
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
