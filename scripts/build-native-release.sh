#!/bin/bash
# Maintainer build only. Released executables do not require Node or Go.
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${1:-dev}
case "$version" in *[!A-Za-z0-9._-]*) printf 'Invalid build version.\n' >&2; exit 1;; esac
cd "$root"
node scripts/build-native-payload.cjs
mkdir -p dist
cd native
for arch in arm64 amd64; do
 GOOS=darwin GOARCH=$arch CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=$version" -o "$root/dist/claude-tweaks_darwin_$arch" ./cmd/claude-tweaks
done
cd "$root/dist"
shasum -a 256 claude-tweaks_darwin_arm64 claude-tweaks_darwin_amd64 > checksums.txt
printf 'Built standalone macOS releases in dist/.\n'
