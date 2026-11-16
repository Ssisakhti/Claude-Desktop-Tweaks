package ui

import (
	tea "charm.land/bubbletea/v2"
	"errors"
	"github.com/Ssisakhti/Claude-Desktop-Tweaks/native/internal/installer"
	"github.com/charmbracelet/x/ansi"
	"strings"
	"testing"
)

type fakeBackend struct {
	status              installer.Status
	installs, downloads int
	fail                error
}

func (b *fakeBackend) Check() (installer.Status, error) { return b.status, nil }
func (b *fakeBackend) Install(f installer.Features) (installer.Result, error) {
	b.installs++
	return installer.Result{Changed: true}, b.fail
}
func (b *fakeBackend) InstallClaude(yes bool) error {
	if !yes {
		return errors.New("missing consent")
	}
	b.downloads++
	return b.fail
}
func ready() (Model, *fakeBackend) {
	b := &fakeBackend{status: installer.Status{Platform: "darwin", ClaudeInstalled: true, Features: installer.DefaultFeatures()}}
	m := New(b)
	next, _ := m.Update(m.Init()())
	return next.(Model), b
}
func press(m Model, code rune) (Model, tea.Cmd) {
	next, cmd := m.Update(tea.KeyPressMsg{Code: code})
	return next.(Model), cmd
}
func TestIndependentSwitchesAndConfirmation(t *testing.T) {
	m, b := ready()
	m, _ = press(m, tea.KeyEnter)
	for n := 0; n < 3; n++ {
		m, _ = press(m, ' ')
		m, _ = press(m, tea.KeyDown)
	}
	if m.draft != (installer.Features{}) {
		t.Fatal("switches not independent")
	}
	m, cmd := press(m, tea.KeyEnter)
	if m.screen != "review" || cmd != nil || b.installs != 0 {
		t.Fatal("applied without review")
	}
	_, cmd = press(m, tea.KeyEnter)
	if cmd == nil {
		t.Fatal("apply missing")
	}
	runEffect(cmd)
	if b.installs != 1 {
		t.Fatal("apply not run")
	}
}
func TestDownloadRequiresY(t *testing.T) {
	m, b := ready()
	m.status.ClaudeInstalled = false
	m, _ = press(m, tea.KeyEnter)
	if m.screen != "download" {
		t.Fatal("download page missing")
	}
	_, cmd := press(m, tea.KeyEnter)
	if cmd != nil || b.downloads != 0 {
		t.Fatal("default consent is not no")
	}
	m, cmd = press(m, 'y')
	if cmd == nil {
		t.Fatal("consent ignored")
	}
	runEffect(cmd)
	if b.downloads != 1 {
		t.Fatal("download missing")
	}
	_, cmd = press(m, 'q')
	if cmd != nil {
		t.Fatal("quit allowed during transaction")
	}
}
func TestRunningClaudeDoesNotStartInstall(t *testing.T) {
	m, b := ready()
	m.status.ClaudeRunning = true
	m.screen = "review"
	_, cmd := press(m, tea.KeyEnter)
	if cmd != nil || b.installs != 0 {
		t.Fatal("running app accepted")
	}
}
func TestUnsavedExitRequiresConfirmation(t *testing.T) {
	m, _ := ready()
	m.screen = "features"
	m, _ = press(m, ' ')
	m, cmd := press(m, 'q')
	if m.screen != "discard" || cmd != nil {
		t.Fatal("draft discarded silently")
	}
	m, _ = press(m, tea.KeyEsc)
	if m.screen != "features" {
		t.Fatal("cancel lost settings")
	}
}
func TestLayoutFitsSupportedTerminalSizes(t *testing.T) {
	m, _ := ready()
	for _, size := range [][2]int{{40, 16}, {60, 24}, {80, 30}, {120, 40}} {
		for _, screen := range []string{"check", "features", "review", "download", "working", "done", "error"} {
			m.width, m.height = size[0], size[1]
			m.screen = screen
			m.err = errors.New("test error\x1b[2J\x07\r line")
			view := m.View().Content
			plain := ansi.Strip(view)
			if strings.ContainsAny(plain, "\x07\r") {
				t.Fatal("unsafe control text")
			}
			for _, line := range strings.Split(plain, "\n") {
				if ansi.StringWidth(line) > size[0] {
					t.Fatalf("%s exceeds width %d: %q", screen, size[0], line)
				}
			}
			if len(strings.Split(plain, "\n")) > size[1] {
				t.Fatalf("%s exceeds height %d", screen, size[1])
			}
		}
	}
}
func TestSavedSettingsAndInstallErrors(t *testing.T) {
	m, b := ready()
	m.screen = "review"
	b.fail = errors.New("Quit Claude and retry")
	m, cmd := press(m, tea.KeyEnter)
	next, _ := m.Update(runEffect(cmd))
	m = next.(Model)
	if m.screen != "error" || m.status.ExtensionInstalled {
		t.Fatal("failure shown as installed")
	}
	if !strings.Contains(ansi.Strip(m.View().Content), "Quit Claude") {
		t.Fatal("error hidden")
	}
}

func runEffect(cmd tea.Cmd) tea.Msg {
	msg := cmd()
	if batch, ok := msg.(tea.BatchMsg); ok {
		for _, c := range batch {
			v := runEffect(c)
			switch v.(type) {
			case installed, downloaded:
				return v
			}
		}
	}
	return msg
}

func TestNarrowWindowStillConfirmsUnsavedExit(t *testing.T) {
	m, _ := ready()
	m.screen = "features"
	m, _ = press(m, ' ')
	m.width = 59
	m, cmd := press(m, 'q')
	if m.screen != "discard" || cmd != nil {
		t.Fatal("narrow window discarded unsaved choices")
	}
	if !strings.Contains(ansi.Strip(m.View().Content), "Discard") {
		t.Fatal("confirmation invisible")
	}
	m, _ = press(m, tea.KeyEnter)
	if m.screen != "features" {
		t.Fatal("default discard choice was not no")
	}
}
func TestBusyExitIsDeferredUntilCleanup(t *testing.T) {
	m, _ := ready()
	m.screen = "working"
	m, cmd := press(m, 'q')
	if cmd != nil {
		t.Fatal("busy program quit early")
	}
	next, cmd := m.Update(installed{result: installer.Result{Changed: true}})
	if cmd == nil {
		t.Fatal("deferred exit was lost")
	}
	if _, ok := cmd().(tea.QuitMsg); !ok {
		t.Fatal("did not quit after completion")
	}
	if next.(Model).screen != "done" {
		t.Fatal("completion state lost")
	}
}
