package installer

import "errors"

const linuxKeyVerification = `gpg --batch --show-keys --with-colons "$scratch/key.asc" > "$scratch/key-info"
[ "$(awk -F: '$1=="pub" {n++} END {print n+0}' "$scratch/key-info")" = 1 ] || { echo 'Vendor key file must contain exactly one primary key.' >&2; exit 1; }
fingerprint=$(awk -F: '$1=="fpr" {print $10; exit}' "$scratch/key-info")
[ "$fingerprint" = 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE ] || { echo 'Vendor signing key did not match.' >&2; exit 1; }
`

// Constant privileged helper: no user paths or interpolated shell input.
// PolicyKit obtains system permission; the UI has already required explicit Y.
const linuxPrerequisites = `set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
if ! command -v curl >/dev/null || ! command -v gpg >/dev/null; then
 apt-get update
 apt-get install -y --no-install-recommends ca-certificates curl gnupg
fi
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --max-time 120 https://downloads.claude.ai/claude-desktop/key.asc -o "$scratch/key.asc"
` + linuxKeyVerification + `printf '%s\n' 'deb [signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main' > "$scratch/claude-desktop.list"
for name in /usr/share/keyrings/claude-desktop-archive-keyring.asc /etc/apt/sources.list.d/claude-desktop.list; do
 [ ! -L "$name" ] || { echo 'Existing symbolic repository configuration was preserved.' >&2; exit 1; }
 if [ -e "$name" ]; then
  case "$name" in *.asc) cmp -s "$name" "$scratch/key.asc";; *) cmp -s "$name" "$scratch/claude-desktop.list";; esac || { echo 'Existing repository configuration differs and was preserved.' >&2; exit 1; }
 fi
done
[ -e /usr/share/keyrings/claude-desktop-archive-keyring.asc ] || install -m 644 "$scratch/key.asc" /usr/share/keyrings/claude-desktop-archive-keyring.asc
[ -e /etc/apt/sources.list.d/claude-desktop.list ] || install -m 644 "$scratch/claude-desktop.list" /etc/apt/sources.list.d/claude-desktop.list
# Isolate vendor metadata so another repository cannot supply Claude.
mkdir -p "$scratch/lists/partial"
apt-get -o "Dir::Etc::sourcelist=$scratch/claude-desktop.list" -o Dir::Etc::sourceparts=- -o "Dir::State::lists=$scratch/lists" update
cd "$scratch"
apt-get -o "Dir::Etc::sourcelist=$scratch/claude-desktop.list" -o Dir::Etc::sourceparts=- -o "Dir::State::lists=$scratch/lists" download claude-desktop
set -- "$scratch"/claude-desktop_*.deb
[ "$#" = 1 ] && [ -f "$1" ] || { echo 'Expected one verified vendor package.' >&2; exit 1; }
apt-get update
apt-get install -y "$1"
`

func (i *Installer) installLinuxClaude() error {
	if e := i.linuxDistribution(); e != nil {
		return e
	}
	installed, e := i.linuxPackage()
	if e != nil {
		return e
	}
	if installed {
		return nil
	}
	running, e := i.linuxRunning()
	if e != nil {
		return e
	}
	if running {
		return errors.New("quit Claude before installing the official package")
	}
	if _, e = i.Run("/usr/bin/pkexec", "/bin/sh", "-c", linuxPrerequisites); e != nil {
		return errors.New("official Claude installation did not finish; approve the system permission prompt or install claude-desktop from Anthropic's apt repository, then retry")
	}
	installed, e = i.linuxPackage()
	if e != nil {
		return e
	}
	if !installed {
		return errors.New("the official Claude package was not found after installation")
	}
	return linuxHook(i.systemPath("usr/lib/claude-desktop/resources/app.asar"))
}
