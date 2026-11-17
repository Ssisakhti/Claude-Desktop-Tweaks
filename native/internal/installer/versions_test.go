package installer

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func versionFixtureChecks(t *testing.T, i *Installer) {
	t.Helper()
	features := Features{Font: true, Theme: false, RTL: true, FontFamily: "vazirmatn", ThemeName: "gruvbox"}
	if _, e := i.Install(features); e != nil {
		t.Fatal(e)
	}
	manifestPath := filepath.Join(i.target(), "manifest.json")
	data, e := os.ReadFile(manifestPath)
	if e != nil {
		t.Fatal(e)
	}
	var manifest map[string]any
	json.Unmarshal(data, &manifest)
	available := manifest["version"].(string)
	for _, installed := range []string{"1.0.0", available, "999.0.0", "bad\u001b[2J"} {
		manifest["version"] = installed
		data, _ = json.Marshal(manifest)
		if e = os.WriteFile(manifestPath, data, 0600); e != nil {
			t.Fatal(e)
		}
		status, e := i.Check()
		if e != nil {
			t.Fatal(e)
		}
		b, _ := json.Marshal(status)
		var result map[string]any
		json.Unmarshal(b, &result)
		if result["availableVersion"] != available {
			t.Fatal("available version missing", string(b))
		}
		expected := installed
		if installed == "bad\u001b[2J" {
			expected = ""
		}
		if result["installedVersion"] != expected {
			t.Fatal("installed version incorrect", string(b))
		}
		if status.Features != features {
			t.Fatal("settings changed during version check")
		}
		want := installed == "1.0.0" || expected == ""
		if result["updateAvailable"] != want {
			t.Fatal("update decision incorrect", string(b))
		}
		if installed == "1.0.0" {
			if _, e = i.Install(features); e != nil {
				t.Fatal(e)
			}
			updated, e := i.Check()
			if e != nil || updated.InstalledVersion != available || updated.Features != features || updated.UpdateAvailable {
				t.Fatal("update lost version or preferences", updated, e)
			}
		}
		if installed == "999.0.0" {
			before, _ := os.ReadFile(manifestPath)
			if _, e = i.Install(features); e == nil {
				t.Fatal("downgrade was accepted")
			}
			after, _ := os.ReadFile(manifestPath)
			if string(before) != string(after) {
				t.Fatal("newer installation changed")
			}
		}
	}
	// An unowned source must never produce a trusted installed version.
	if e = os.WriteFile(filepath.Join(i.target(), "content.js"), []byte("foreign"), 0600); e != nil {
		t.Fatal(e)
	}
	status, e := i.Check()
	if e != nil {
		t.Fatal(e)
	}
	b, _ := json.Marshal(status)
	var raw map[string]any
	json.Unmarshal(b, &raw)
	if raw["installedVersion"] != "" || raw["updateAvailable"] != false {
		t.Fatal("unowned version trusted", string(b))
	}
}
func TestWindowsInstalledVersionAndSavedChoices(t *testing.T) {
	versionFixtureChecks(t, windowsFixture(t))
}

func TestVersionComparisonIsNumericAndBounded(t *testing.T) {
	for _, c := range []struct {
		a, b string
		want int
	}{{"1.10.0", "1.9.0", 1}, {"1.5.0", "1.5.0.0", 0}, {"1.4.1", "1.5.0", -1}, {"2.0.0", "1.99.99", 1}} {
		got, ok := compareVersions(c.a, c.b)
		if !ok || got != c.want {
			t.Fatal(c, got, ok)
		}
	}
	for _, bad := range []string{"", "v1.5.0", "1.5.0-beta", "1.5.0\n", "1.2.3.4.5", "65536.0.0", "01.0.0"} {
		if _, ok := versionParts(bad); ok {
			t.Fatal("unsafe version accepted", bad)
		}
	}
}
