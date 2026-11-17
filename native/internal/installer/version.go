package installer

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"strconv"
	"strings"
)

// Versions use the extension manifest's numeric format, with at most four parts.
func versionParts(value string) ([4]uint64, bool) {
	var result [4]uint64
	parts := strings.Split(value, ".")
	if len(parts) > 4 {
		return result, false
	}
	for n, part := range parts {
		if part == "" || len(part) > 5 || len(part) > 1 && part[0] == '0' {
			return result, false
		}
		for _, r := range part {
			if r < '0' || r > '9' {
				return result, false
			}
		}
		v, e := strconv.ParseUint(part, 10, 16)
		if e != nil {
			return result, false
		}
		result[n] = v
	}
	return result, true
}
func compareVersions(a, b string) (int, bool) {
	left, ok := versionParts(a)
	if !ok {
		return 0, false
	}
	right, ok := versionParts(b)
	if !ok {
		return 0, false
	}
	for n, v := range left {
		if v < right[n] {
			return -1, true
		}
		if v > right[n] {
			return 1, true
		}
	}
	return 0, true
}

type extensionManifest struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

func ownedManifestName(name string) bool {
	return name == "Claude Desktop Tweaks" || name == "Claude Desktop Persian Tweaks"
}
func readManifestVersion(data []byte) string {
	var m extensionManifest
	if json.Unmarshal(data, &m) != nil || !ownedManifestName(m.Name) {
		return ""
	}
	if _, ok := versionParts(m.Version); !ok {
		return ""
	}
	return m.Version
}
func availableVersion() (string, error) {
	b, e := embedded.ReadFile("payload/manifest.json")
	if e != nil {
		return "", e
	}
	version := readManifestVersion(b)
	if version == "" {
		return "", errors.New("the installer version metadata is invalid")
	}
	return version, nil
}
func (i *Installer) versionStatus(s Status) (Status, error) {
	available, e := availableVersion()
	if e != nil {
		return s, e
	}
	s.AvailableVersion = available
	f, e := i.files()
	if e != nil {
		return s, e
	}
	defer f.root.Close()
	b, e := f.read(i.receiptPath())
	if e != nil {
		return s, e
	}
	if b == nil {
		return s, nil
	}
	receipt, e := decodeReceipt(b)
	if e != nil {
		return s, e
	}
	source, e := f.read(filepath.Join(i.target(), "content.js"))
	if e != nil {
		return s, e
	}
	if source == nil || receipt.ExtensionSHA256 == "" || hash(source) != receipt.ExtensionSHA256 {
		return s, nil
	}
	s.InstallationDetected = true
	manifest, e := f.read(filepath.Join(i.target(), "manifest.json"))
	if e != nil {
		return s, e
	}
	s.InstalledVersion = readManifestVersion(manifest)
	relation, known := compareVersions(s.InstalledVersion, available)
	s.UpdateAvailable = !known || relation < 0
	return s, nil
}

// Recheck the current manifest immediately before replacing the extension.
func (i *Installer) guardUpdateVersion(f *safeFS) error {
	b, e := f.read(filepath.Join(i.target(), "manifest.json"))
	if e != nil {
		return e
	}
	var m extensionManifest
	if json.Unmarshal(b, &m) != nil || !ownedManifestName(m.Name) {
		return errors.New("the existing extension metadata is not recognized; it was preserved")
	}
	available, e := availableVersion()
	if e != nil {
		return e
	}
	if relation, known := compareVersions(m.Version, available); known && relation > 0 {
		return errors.New("a newer version is installed; run the install command to get the latest installer")
	}
	return nil
}

func (s Status) NewerVersionInstalled() bool {
	r, ok := compareVersions(s.InstalledVersion, s.AvailableVersion)
	return ok && r > 0
}
