package installer

import (
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf16"
)

func windowsFixture(t *testing.T) *Installer { i, _ := windowsFixtureSystem(t); return i }
func windowsFixtureSystem(t *testing.T) (*Installer, *windowsSystem) {
	t.Helper()
	home := t.TempDir()
	root := t.TempDir()
	profile := filepath.Join(home, "AppData/Local/Claude-Data/claude_pzs8sxrjxfjjc")
	os.MkdirAll(profile, 0700)
	os.MkdirAll(filepath.Join(root, "app/resources"), 0700)
	os.WriteFile(filepath.Join(root, "app/claude.exe"), []byte("vendor executable"), 0600)
	files := map[string]any{"main.js": map[string]any{"offset": "0", "size": len(windowsTestHook)}}
	j, _ := json.Marshal(map[string]any{"files": files})
	h := make([]byte, 16)
	binary.LittleEndian.PutUint32(h[4:], uint32(8+len(j)))
	binary.LittleEndian.PutUint32(h[12:], uint32(len(j)))
	os.WriteFile(filepath.Join(root, "app/resources/app.asar"), append(append(h, j...), []byte(windowsTestHook)...), 0600)
	d := windowsSystem{Build: 26100, Architecture: "X64", LocalAppData: filepath.Join(home, "AppData/Local"), RoamingAppData: filepath.Join(home, "AppData/Roaming"), Package: &windowsPackage{Family: "Claude_pzs8sxrjxfjjc", Root: root, Version: "5.11492.5.0"}}
	i := &Installer{Home: home, Platform: "windows", NotifyEnvironment: func() error { return nil }, Run: func(c string, a ...string) (string, error) {
		if c != "powershell.exe" {
			return "", errors.New("unexpected command")
		}
		script := decodePowerShellForTest(t, a[len(a)-1])
		if strings.Contains(script, "CDT_DISCOVERY") {
			b, _ := json.Marshal(d)
			return string(b), nil
		}
		if strings.Contains(script, "CDT_ENVIRONMENT") {
			if strings.Contains(script, "$desiredValue=$null") {
				d.EnvironmentValue = nil
				d.EnvironmentKind = ""
			} else {
				one := "1"
				d.EnvironmentValue = &one
				d.EnvironmentKind = "String"
			}
			return "", nil
		}
		return "", errors.New("unexpected PowerShell action")
	}}
	return i, &d
}

const windowsTestHook = `REACT_PROFILE loadReactDevTools fmkadmapgofadopljbjfkapdkoienihi loadExtension userData extensions`

func TestWindowsIndependentSettingsAndRepeat(t *testing.T) {
	for bits := 0; bits < 8; bits++ {
		i := windowsFixture(t)
		flags := Features{Font: bits&1 != 0, Theme: bits&2 != 0, RTL: bits&4 != 0}
		s, e := i.Check()
		if e != nil || !s.ClaudeInstalled {
			t.Fatalf("check: %+v %v", s, e)
		}
		r, e := i.Install(flags)
		if e != nil || !r.Changed {
			t.Fatalf("apply: %+v %v", r, e)
		}
		s, e = i.Check()
		if e != nil || s.Features != flags || !s.ExtensionInstalled {
			t.Fatalf("settings: %+v %v", s, e)
		}
		r, e = i.Install(flags)
		if e != nil || r.Changed {
			t.Fatalf("repeat: %+v %v", r, e)
		}
		if _, e = i.Install(Features{}); e != nil {
			t.Fatal(e)
		}
	}
}
func TestWindowsDoesNotAddOrReplaceShortcuts(t *testing.T) {
	i := windowsFixture(t)
	if _, e := i.Check(); e != nil {
		t.Fatal(e)
	}
	shortcut := filepath.Join(i.windows.RoamingAppData, "Microsoft/Windows/Start Menu/Programs/Claude.lnk")
	os.MkdirAll(filepath.Dir(shortcut), 0700)
	os.WriteFile(shortcut, []byte("original"), 0600)
	if _, e := i.Install(DefaultFeatures()); e != nil {
		t.Fatal(e)
	}
	b, _ := os.ReadFile(shortcut)
	if string(b) != "original" {
		t.Fatal("original shortcut changed")
	}
	entries, _ := os.ReadDir(filepath.Dir(shortcut))
	if len(entries) != 1 {
		t.Fatal("a new shortcut was added")
	}
}

func decodePowerShellForTest(t *testing.T, s string) string {
	t.Helper()
	b, e := base64.StdEncoding.DecodeString(s)
	if e != nil {
		t.Fatal(e)
	}
	units := make([]uint16, len(b)/2)
	for n := range units {
		units[n] = binary.LittleEndian.Uint16(b[n*2:])
	}
	return string(utf16.Decode(units))
}

func TestWindowsNotificationFailureRollsBackInstallation(t *testing.T) {
	i := windowsFixture(t)
	calls := 0
	i.NotifyEnvironment = func() error {
		calls++
		if calls == 1 {
			return errors.New("desktop notification failed")
		}
		return nil
	}
	if _, e := i.Install(DefaultFeatures()); e == nil {
		t.Fatal("notification failure reported success")
	}
	if _, e := os.Stat(i.target()); !os.IsNotExist(e) {
		t.Fatal("extension was not rolled back")
	}
	if _, e := os.Stat(i.receiptPath()); !os.IsNotExist(e) {
		t.Fatal("success receipt written after notification failure")
	}
}

func TestWindowsPreservesOriginalEnvironmentInReceipt(t *testing.T) {
	i, d := windowsFixtureSystem(t)
	original := "%USERPROFILE%\\custom"
	d.EnvironmentValue = &original
	d.EnvironmentKind = "ExpandString"
	if _, e := i.Install(DefaultFeatures()); e != nil {
		t.Fatal(e)
	}
	if _, e := i.Install(Features{RTL: true}); e != nil {
		t.Fatal(e)
	}
	r, e := i.ReadReceipt()
	if e != nil || r.PreviousReactProfile == nil || *r.PreviousReactProfile != original || r.PreviousReactProfileKind != "ExpandString" {
		t.Fatalf("original environment lost: %+v %v", r, e)
	}
}
func TestWindowsUnsupportedAndRunningStatesDoNotInstall(t *testing.T) {
	for _, name := range []string{"running", "architecture", "build", "package", "profile", "foreign extension"} {
		t.Run(name, func(t *testing.T) {
			i, d := windowsFixtureSystem(t)
			switch name {
			case "running":
				d.Running = true
			case "architecture":
				d.Architecture = "Arm64"
			case "build":
				d.Build = 19045
			case "package":
				d.Package.Family = "Unknown"
			case "profile":
				os.RemoveAll(filepath.Join(d.LocalAppData, "Claude-Data"))
			case "foreign extension":
				i.windows = *d
				os.MkdirAll(i.target(), 0700)
				os.WriteFile(filepath.Join(i.target(), "content.js"), []byte("foreign"), 0600)
			}
			if _, e := i.Install(DefaultFeatures()); e == nil {
				t.Fatal("unsupported state accepted")
			}
		})
	}
}
