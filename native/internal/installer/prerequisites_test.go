//go:build !windows

package installer

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckDoesNotWrite(t *testing.T) {
	i, _ := fixture(t)
	i.Applications = t.TempDir()
	s, err := i.Check()
	if err != nil {
		t.Fatal(err)
	}
	if s.ClaudeInstalled || s.ExtensionInstalled || s.Features != DefaultFeatures() {
		t.Fatal("incorrect status")
	}
	entries, _ := os.ReadDir(i.Home)
	if len(entries) != 0 {
		t.Fatal("check wrote files")
	}
}
func TestPrerequisiteConsent(t *testing.T) {
	i, s := fixture(t)
	if err := i.InstallClaude(false); err == nil {
		t.Fatal("consent bypass")
	}
	if len(s.calls) != 0 {
		t.Fatal("command ran without consent")
	}
}
func TestRejectUnverifiedClaudeDownload(t *testing.T) {
	i, _ := fixture(t)
	i.Applications = t.TempDir()
	calls := []string{}
	i.Run = func(c string, a ...string) (string, error) {
		calls = append(calls, c)
		if strings.Contains(c, "codesign") {
			return "", errors.New("untrusted")
		}
		return "", nil
	}
	if err := i.InstallClaude(true); err == nil {
		t.Fatal("untrusted app installed")
	}
	for _, c := range calls {
		if strings.Contains(c, "ditto") {
			t.Fatal("copied before vendor verification")
		}
	}
	if _, err := os.Stat(filepath.Join(i.Home, "Applications/Claude.app")); !os.IsNotExist(err) {
		t.Fatal("app created")
	}
}
func TestExistingClaudeIsNeverReplaced(t *testing.T) {
	i, s := fixture(t)
	i.Applications = t.TempDir()
	app := filepath.Join(i.Applications, "Claude.app/Contents/MacOS/Claude")
	os.MkdirAll(filepath.Dir(app), 0700)
	os.WriteFile(app, []byte("existing"), 0700)
	if err := i.InstallClaude(true); err != nil {
		t.Fatal(err)
	}
	if len(s.calls) != 0 {
		t.Fatal("existing app touched")
	}
	b, _ := os.ReadFile(app)
	if string(b) != "existing" {
		t.Fatal("changed existing app")
	}
}
func TestReceiptSymlinkRejected(t *testing.T) {
	i, _ := fixture(t)
	i.Applications = t.TempDir()
	os.MkdirAll(i.stateDir(), 0700)
	file := filepath.Join(t.TempDir(), "record")
	os.WriteFile(file, []byte("{}"), 0600)
	os.Symlink(file, i.receiptPath())
	if _, err := i.Check(); err == nil {
		t.Fatal("symlink receipt accepted")
	}
}
