//go:build !windows

package installer

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type fakeSystem struct {
	env                         string
	hasEnv, loaded, running, hs bool
	fail                        string
	calls                       []string
}

func (f *fakeSystem) run(command string, args ...string) (string, error) {
	op := filepath.Base(command) + " " + strings.Join(args, " ")
	f.calls = append(f.calls, op)
	if strings.HasSuffix(command, "pgrep") {
		active := f.running
		if args[1] == "Hammerspoon" {
			active = f.hs
		}
		if active {
			return "1", nil
		}
		return "", ExitError{1}
	}
	if len(args) == 0 {
		return "", errors.New("missing args")
	}
	a := args[0]
	if a == f.fail {
		return "", errors.New("injected failure")
	}
	switch a {
	case "getenv":
		if f.hasEnv {
			return f.env + "\n", nil
		}
		return "", ExitError{1}
	case "print":
		if f.loaded {
			return "ok", nil
		}
		return "", ExitError{1}
	case "bootstrap":
		f.loaded = true
	case "bootout":
		f.loaded = false
	case "setenv":
		f.hasEnv = true
		f.env = args[2]
	case "unsetenv":
		f.hasEnv = false
		f.env = ""
	}
	return "", nil
}
func fixture(t *testing.T) (*Installer, *fakeSystem) {
	t.Helper()
	f := &fakeSystem{}
	apps := t.TempDir()
	app := filepath.Join(apps, "Claude.app/Contents/MacOS")
	if err := os.MkdirAll(app, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(app, "Claude"), []byte("fixture"), 0700); err != nil {
		t.Fatal(err)
	}
	return &Installer{Home: t.TempDir(), Platform: "darwin", Run: f.run, Applications: apps}, f
}
func TestIndependentPayloads(t *testing.T) {
	for i := 0; i < 8; i++ {
		f := Features{i&1 != 0, i&2 != 0, i&4 != 0}
		files, err := Payload(f)
		if err != nil {
			t.Fatal(err)
		}
		b, _ := json.Marshal(f)
		if !bytes.Contains(files["content.js"], b) || bytes.Contains(files["content.js"], []byte("__CDT_FEATURES__")) {
			t.Fatal("wrong embedded feature selection")
		}
	}
}
func TestInstallAndRepeat(t *testing.T) {
	i, s := fixture(t)
	f := Features{true, false, true}
	r, err := i.Install(f)
	if err != nil {
		t.Fatal(err)
	}
	if !r.Changed || !s.loaded || s.env != "1" {
		t.Fatal("startup not configured")
	}
	r, err = i.Install(f)
	if err != nil || r.Changed {
		t.Fatalf("not idempotent: %+v %v", r, err)
	}
	record, err := i.ReadReceipt()
	if err != nil || record.Features != f || record.PreviousReactProfile != nil {
		t.Fatal("preferences or rollback lost")
	}
}
func TestClosedAppGuard(t *testing.T) {
	i, s := fixture(t)
	s.running = true
	if _, err := i.Install(Features{}); err == nil {
		t.Fatal("running Claude accepted")
	}
	files, _ := os.ReadDir(i.Home)
	if len(files) != 0 {
		t.Fatal("files written")
	}
}
func TestRollbackOnRegistrationFailure(t *testing.T) {
	i, s := fixture(t)
	s.hasEnv = true
	s.env = "previous"
	s.fail = "setenv"
	_, err := i.Install(Features{true, true, true})
	if err == nil {
		t.Fatal("failure ignored")
	}
	if s.loaded || s.env != "previous" {
		t.Fatal("system state not restored")
	}
	if _, err = os.Stat(i.target()); !os.IsNotExist(err) {
		t.Fatal("extension left installed")
	}
}
func TestUnknownExtensionAndSymlinkPreserved(t *testing.T) {
	i, _ := fixture(t)
	if err := os.MkdirAll(i.target(), 0700); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(i.target(), "manifest.json")
	os.WriteFile(file, []byte("{}"), 0600)
	if _, err := i.Install(Features{}); err == nil {
		t.Fatal("unowned extension replaced")
	}
	b, _ := os.ReadFile(file)
	if string(b) != "{}" {
		t.Fatal("user file changed")
	}
	i, _ = fixture(t)
	outside := t.TempDir()
	os.Symlink(outside, filepath.Join(i.Home, "Library"))
	if _, err := i.Install(Features{}); err == nil {
		t.Fatal("symlink accepted")
	}
	entries, _ := os.ReadDir(outside)
	if len(entries) != 0 {
		t.Fatal("symlink target changed")
	}
}
func TestOwnedUpgradeAndAllOff(t *testing.T) {
	i, _ := fixture(t)
	if _, err := i.Install(Features{true, true, true}); err != nil {
		t.Fatal(err)
	}
	r, err := i.Install(Features{})
	if err != nil || !r.Changed || r.Backup == "" {
		t.Fatal("upgrade missing backup", err)
	}
	record, err := i.ReadReceipt()
	if err != nil || record.Features != (Features{}) {
		t.Fatal("all-off not saved")
	}
}
func TestLegacyMigrationGuardAndBackup(t *testing.T) {
	i, s := fixture(t)
	p := filepath.Join(i.Home, ".hammerspoon/init.lua")
	os.MkdirAll(filepath.Dir(p), 0700)
	original := "keep()\n-- BEGIN Claude Desktop Tweaks\nold()\n-- END Claude Desktop Tweaks\nafter()\n"
	os.WriteFile(p, []byte(original), 0600)
	s.hs = true
	if _, err := i.Install(Features{}); err == nil {
		t.Fatal("active controller replaced")
	}
	s.hs = false
	if _, err := i.Install(Features{}); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(p)
	if string(b) != "keep()\nafter()\n" {
		t.Fatal("unrelated config changed")
	}
	r, _ := i.ReadReceipt()
	b, _ = os.ReadFile(r.HammerspoonBackup)
	if string(b) != original {
		t.Fatal("backup lost")
	}
}
func TestLockPreventsConcurrentInstall(t *testing.T) {
	i, _ := fixture(t)
	os.MkdirAll(i.stateDir(), 0700)
	os.WriteFile(filepath.Join(i.stateDir(), ".extension-install.lock"), []byte("busy"), 0600)
	if _, err := i.Install(Features{}); err == nil {
		t.Fatal("concurrent install allowed")
	}
}

func TestMissingClaudeBlocksInstallation(t *testing.T) {
	i, _ := fixture(t)
	i.Applications = t.TempDir()
	if _, err := i.Install(Features{}); err == nil {
		t.Fatal("installed without Claude")
	}
	entries, _ := os.ReadDir(i.Home)
	if len(entries) != 0 {
		t.Fatal("files written without prerequisite")
	}
}

func TestFormattedLegacyAgentIsAcceptedWithoutRewriting(t *testing.T) {
	i, _ := fixture(t)
	if _, e := i.Install(DefaultFeatures()); e != nil {
		t.Fatal(e)
	}
	agent := filepath.Join(i.Home, "Library/LaunchAgents", Label+".plist")
	b, _ := os.ReadFile(agent)
	formatted := strings.ReplaceAll(string(b), "><", ">\n\t<")
	os.WriteFile(agent, []byte(formatted), 0600)
	if _, e := i.Install(DefaultFeatures()); e != nil {
		t.Fatal(e)
	}
	now, _ := os.ReadFile(agent)
	if string(now) != formatted {
		t.Fatal("existing agent reformatted")
	}
}

func TestMigrationPreservesBlankLineAfterCRLFBlock(t *testing.T) {
	original := []byte("before()\r\n" + markerBegin + "\r\nold()\r\n" + markerEnd + "\r\n\nnext()\n")
	got, e := migrateConfig(original)
	if e != nil || string(got) != "before()\r\n\nnext()\n" {
		t.Fatalf("unrelated whitespace changed: %q %v", got, e)
	}
}
