//go:build !windows

package installer

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func linuxFixture(t *testing.T) *Installer {
	t.Helper()
	root := t.TempDir()
	home := t.TempDir()
	for _, p := range []string{"usr/bin", "usr/share/applications", "usr/lib/claude-desktop/resources", "etc"} {
		if e := os.MkdirAll(filepath.Join(root, p), 0755); e != nil {
			t.Fatal(e)
		}
	}
	os.WriteFile(filepath.Join(root, "etc/os-release"), []byte("ID=ubuntu\nVERSION_ID=\"22.04\"\n"), 0644)
	os.WriteFile(filepath.Join(root, "usr/bin/claude-desktop"), []byte("executable"), 0755)
	os.WriteFile(filepath.Join(root, "usr/share/applications/com.anthropic.Claude.desktop"), []byte("[Desktop Entry]\nName=Claude\nExec=claude-desktop %U\nType=Application\n[Desktop Action NewChat]\nExec=claude-desktop \"claude://claude.ai/new\"\n"), 0644)
	writeTestASAR(t, filepath.Join(root, "usr/lib/claude-desktop/resources/app.asar"), map[string]string{"main.js": `process.env.REACT_PROFILE==="1";loadReactDevTools();`, "tools.js": `fmkadmapgofadopljbjfkapdkoienihi;loadExtension();userData;extensions`})
	return &Installer{Home: home, Platform: "linux", SystemRoot: root, Run: func(c string, a ...string) (string, error) {
		if strings.HasSuffix(c, "dpkg-query") {
			return "install ok installed\t5.11492.5\n", nil
		}
		if strings.HasSuffix(c, "pgrep") {
			return "", ExitError{1}
		}
		return "", errors.New("unexpected system command: " + c)
	}}
}
func writeTestASAR(t *testing.T, p string, files map[string]string) {
	t.Helper()
	entries := map[string]any{}
	data := []byte{}
	for n, s := range files {
		entries[n] = map[string]any{"offset": stringInt(len(data)), "size": len(s)}
		data = append(data, []byte(s)...)
	}
	j, _ := json.Marshal(map[string]any{"files": entries})
	header := make([]byte, 16)
	binary.LittleEndian.PutUint32(header[4:], uint32(8+len(j)))
	binary.LittleEndian.PutUint32(header[12:], uint32(len(j)))
	if e := os.WriteFile(p, append(append(header, j...), data...), 0644); e != nil {
		t.Fatal(e)
	}
}
func stringInt(n int) string { b, _ := json.Marshal(n); return string(b) }
func TestLinuxInstallAndIndependentPreferences(t *testing.T) {
	for flags := 0; flags < 8; flags++ {
		t.Run(stringInt(flags), func(t *testing.T) {
			i := linuxFixture(t)
			f := Features{flags&1 != 0, flags&2 != 0, flags&4 != 0}
			s, e := i.Check()
			if e != nil || !s.ClaudeInstalled {
				t.Fatalf("check: %+v %v", s, e)
			}
			r, e := i.Install(f)
			if e != nil || !r.Changed {
				t.Fatalf("install: %+v %v", r, e)
			}
			s, e = i.Check()
			if e != nil || !s.ExtensionInstalled || s.Features != f {
				t.Fatalf("preferences: %+v %v", s, e)
			}
			r, e = i.Install(f)
			if e != nil || r.Changed {
				t.Fatalf("repeat: %+v %v", r, e)
			}
			desktop, e := os.ReadFile(filepath.Join(i.Home, ".local/share/applications/com.anthropic.Claude.desktop"))
			if e != nil {
				t.Fatal(e)
			}
			if strings.Count(string(desktop), "REACT_PROFILE=1") != 2 {
				t.Fatal("desktop actions must inherit the environment")
			}
			if _, e = os.Stat(filepath.Join(i.Home, ".local/share/Claude Desktop Tweaks/.extension-install.lock")); !os.IsNotExist(e) {
				t.Fatal("lock left behind")
			}
		})
	}
}
func TestLinuxPreservesForeignFilesAndRejectsOpenApp(t *testing.T) {
	for _, kind := range []string{"launcher", "extension", "running", "hook", "distribution"} {
		t.Run(kind, func(t *testing.T) {
			i := linuxFixture(t)
			switch kind {
			case "launcher":
				p := filepath.Join(i.Home, ".local/share/applications/com.anthropic.Claude.desktop")
				os.MkdirAll(filepath.Dir(p), 0700)
				os.WriteFile(p, []byte("foreign"), 0600)
			case "extension":
				os.MkdirAll(i.target(), 0700)
				os.WriteFile(filepath.Join(i.target(), "content.js"), []byte("foreign"), 0600)
			case "running":
				prev := i.Run
				i.Run = func(c string, a ...string) (string, error) {
					if strings.HasSuffix(c, "pgrep") {
						return "42", nil
					}
					return prev(c, a...)
				}
			case "hook":
				os.WriteFile(filepath.Join(i.SystemRoot, "usr/lib/claude-desktop/resources/app.asar"), []byte("unsupported"), 0644)
			case "distribution":
				os.WriteFile(filepath.Join(i.SystemRoot, "etc/os-release"), []byte("ID=fedora\nVERSION_ID=42\n"), 0644)
			}
			if _, e := i.Install(DefaultFeatures()); e == nil {
				t.Fatal("unsafe install accepted")
			}
			if _, e := os.Stat(i.receiptPath()); !os.IsNotExist(e) {
				t.Fatal("receipt written despite rejection")
			}
		})
	}
}
func TestLinuxRequiresPrerequisiteConsent(t *testing.T) {
	i := linuxFixture(t)
	if e := i.InstallClaude(false); e == nil {
		t.Fatal("download without consent")
	}
}

func TestLinuxOfficialArchive(t *testing.T) {
	p := os.Getenv("CDT_TEST_ASAR")
	if p == "" {
		t.Skip("set CDT_TEST_ASAR to a read-only official archive")
	}
	if e := linuxHook(p); e != nil {
		t.Fatal(e)
	}
}
func TestLinuxXDGPathsAndForeignSymlinks(t *testing.T) {
	i := linuxFixture(t)
	i.ConfigHome = filepath.Join(i.Home, "custom config")
	i.DataHome = filepath.Join(i.Home, "custom data")
	if _, e := i.Install(Features{RTL: true}); e != nil {
		t.Fatal(e)
	}
	if !strings.HasPrefix(i.target(), i.ConfigHome) || !strings.HasPrefix(i.linuxLauncher(), i.DataHome) {
		t.Fatal("XDG paths ignored")
	}
	i = linuxFixture(t)
	i.DataHome = t.TempDir()
	if _, e := i.Install(DefaultFeatures()); e == nil {
		t.Fatal("external XDG directory accepted")
	}
	i = linuxFixture(t)
	os.MkdirAll(filepath.Join(i.Home, ".local/share"), 0700)
	outside := t.TempDir()
	os.Symlink(outside, filepath.Join(i.Home, ".local/share/applications"))
	if _, e := i.Install(DefaultFeatures()); e == nil {
		t.Fatal("symbolic launcher parent accepted")
	}
	entries, _ := os.ReadDir(outside)
	if len(entries) != 0 {
		t.Fatal("foreign directory changed")
	}
}
func TestLinuxRollbackAfterLauncherFailure(t *testing.T) {
	i := linuxFixture(t)
	// Introduce the conflict during the second app-running check, after preflight.
	prev := i.Run
	checks := 0
	i.Run = func(c string, a ...string) (string, error) {
		if strings.HasSuffix(c, "pgrep") {
			checks++
			if checks == 2 {
				os.MkdirAll(filepath.Join(i.Home, ".local/share"), 0700)
				os.WriteFile(filepath.Join(i.Home, ".local/share/applications"), []byte("foreign file"), 0600)
			}
		}
		return prev(c, a...)
	}
	if _, e := i.Install(DefaultFeatures()); e == nil {
		t.Fatal("unsafe launcher accepted")
	}
	if _, e := os.Stat(i.target()); !os.IsNotExist(e) {
		t.Fatal("extension was not rolled back")
	}
	if _, e := os.Stat(filepath.Join(i.stateDir(), ".extension-install.lock")); !os.IsNotExist(e) {
		t.Fatal("lock leaked after failure")
	}
}
func TestLinuxDesktopActionsAndConflictingCommands(t *testing.T) {
	i := linuxFixture(t)
	p := i.systemPath("usr/share/applications/com.anthropic.Claude.desktop")
	os.WriteFile(p, []byte("[Desktop Entry]\nExec=/usr/bin/claude-desktop %U\n[Desktop Action NewChat]\nExec=other-app\n"), 0644)
	if _, e := i.Install(DefaultFeatures()); e == nil {
		t.Fatal("unknown vendor command accepted")
	}
}

func TestLinuxPrerequisiteInstallIsExplicitAndUsesSignedRepository(t *testing.T) {
	i := linuxFixture(t)
	installed := false
	calls := 0
	i.Run = func(c string, a ...string) (string, error) {
		switch c {
		case "/usr/bin/dpkg-query":
			if installed {
				return "install ok installed\t5.11492.5\n", nil
			}
			return "", ExitError{1}
		case "/usr/bin/pgrep":
			return "", ExitError{1}
		case "/usr/bin/pkexec":
			calls++
			if len(a) != 3 || a[0] != "/bin/sh" || a[1] != "-c" || !strings.Contains(a[2], "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE") || !strings.Contains(a[2], "signed-by=") {
				t.Fatal("unverified package source")
			}
			installed = true
			return "", nil
		}
		return "", errors.New("unexpected command")
	}
	if e := i.InstallClaude(false); e == nil || calls != 0 {
		t.Fatal("consent bypassed")
	}
	if e := i.InstallClaude(true); e != nil || calls != 1 {
		t.Fatalf("explicit install: %v, calls=%d", e, calls)
	}
}

func TestLinuxSettingsCanBeChangedAndDisabled(t *testing.T) {
	i := linuxFixture(t)
	for _, flags := range []Features{DefaultFeatures(), {Font: true}, {Theme: true}, {RTL: true}, {}} {
		if _, e := i.Install(flags); e != nil {
			t.Fatal(e)
		}
		s, e := i.Check()
		if e != nil || s.Features != flags || !s.ExtensionInstalled {
			t.Fatalf("changed settings: %+v %v", s, e)
		}
	}
}
func TestLinuxReceiptConflictRollsBackPublishedFiles(t *testing.T) {
	i := linuxFixture(t)
	outside := filepath.Join(t.TempDir(), "foreign")
	os.WriteFile(outside, []byte("preserve me"), 0600)
	prev := i.Run
	checks := 0
	i.Run = func(c string, a ...string) (string, error) {
		if strings.HasSuffix(c, "pgrep") {
			checks++
			if checks == 2 {
				os.Symlink(outside, i.receiptPath())
			}
		}
		return prev(c, a...)
	}
	if _, e := i.Install(DefaultFeatures()); e == nil {
		t.Fatal("concurrent receipt accepted")
	}
	for _, p := range []string{i.target(), i.linuxLauncher(), filepath.Join(i.stateDir(), ".extension-install.lock")} {
		if _, e := os.Lstat(p); !os.IsNotExist(e) {
			t.Fatalf("rollback left %s", p)
		}
	}
	b, _ := os.ReadFile(outside)
	if string(b) != "preserve me" {
		t.Fatal("foreign file changed")
	}
}

func TestLinuxPrerequisitesDownloadClaudeOnlyFromVendorIndex(t *testing.T) {
	if !strings.Contains(linuxPrerequisites, "Dir::Etc::sourceparts=-") || !strings.Contains(linuxPrerequisites, "Dir::State::lists=$scratch/lists") || !strings.Contains(linuxPrerequisites, "download claude-desktop") || strings.Contains(linuxPrerequisites, "apt-get install -y claude-desktop\n") {
		t.Fatal("Claude package may be selected from an unrelated repository")
	}
}

func TestLinuxCrossFilesystemUpdate(t *testing.T) {
	home := os.Getenv("CDT_CROSS_FS_HOME")
	if home == "" {
		t.Skip("requires isolated Linux XDG mounts")
	}
	i := linuxFixture(t)
	i.Home = home
	i.ConfigHome = filepath.Join(home, "config")
	i.DataHome = filepath.Join(home, "data")
	if _, e := i.Install(DefaultFeatures()); e != nil {
		t.Fatal(e)
	}
	r, e := i.Install(Features{RTL: true})
	if e != nil {
		t.Fatal(e)
	}
	if r.Backup == "" {
		t.Fatal("missing previous-extension backup")
	}
	s, e := i.Check()
	if e != nil || s.Features != (Features{RTL: true}) {
		t.Fatalf("settings: %+v %v", s, e)
	}
}

func TestLinuxVendorKeyRejectsAdditionalPrimaryKeys(t *testing.T) {
	for _, tc := range []struct {
		name, metadata string
		valid          bool
	}{
		{"vendor", "pub:::::::::\nfpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:\nsub:::::::::\nfpr:::::::::SUBKEY:\n", true},
		{"extra primary", "pub:::::::::\nfpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:\npub:::::::::\nfpr:::::::::ATTACKER:\n", false},
		{"wrong key", "pub:::::::::\nfpr:::::::::ATTACKER:\n", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			os.WriteFile(filepath.Join(dir, "gpg"), []byte("#!/bin/sh\ncat \"$CDT_KEY_FIXTURE\"\n"), 0700)
			os.WriteFile(filepath.Join(dir, "metadata"), []byte(tc.metadata), 0600)
			cmd := exec.Command("/bin/sh", "-c", "set -eu\nscratch=$CDT_SCRATCH\n"+linuxKeyVerification)
			cmd.Env = append(os.Environ(), "PATH="+dir+":/usr/bin:/bin", "CDT_KEY_FIXTURE="+filepath.Join(dir, "metadata"), "CDT_SCRATCH="+dir)
			out, e := cmd.CombinedOutput()
			if (e == nil) != tc.valid {
				t.Fatalf("key acceptance: valid=%v error=%v output=%s", tc.valid, e, out)
			}
		})
	}
}
