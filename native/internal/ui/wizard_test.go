package ui

import (
	tea "charm.land/bubbletea/v2"
	"encoding/json"
	"fmt"
	"github.com/Ssisakhti/Claude-Desktop-Tweaks/native/internal/installer"
	"github.com/charmbracelet/x/ansi"
	"strings"
	"testing"
)

func TestWizardMakesOneIndependentChoicePerStep(t *testing.T) {
	m, b := ready()
	if m.screen != "font" {
		t.Fatal("checks must lead directly to font", m.screen)
	}
	m, _ = press(m, tea.KeyDown)
	m, _ = press(m, tea.KeyEnter)
	if m.screen != "theme" || m.draft.FontFamily != "vazirmatn" {
		t.Fatal("font choice lost")
	}
	m, _ = press(m, tea.KeyDown)
	m, _ = press(m, tea.KeyEnter)
	if m.screen != "direction" || m.draft.ThemeName != "gruvbox" {
		t.Fatal("theme choice lost")
	}
	m, _ = press(m, tea.KeyDown)
	m, _ = press(m, tea.KeyEnter)
	if m.screen != "review" || m.draft.RTL || !m.draft.Font || !m.draft.Theme || b.installs != 0 {
		t.Fatal("independence/review broken")
	}
	for n := 0; n < 3; n++ {
		m, _ = press(m, tea.KeyDown)
	}
	m, cmd := press(m, tea.KeyEnter)
	if cmd == nil {
		t.Fatal("apply action absent")
	}
	runFlow(m, cmd)
	if b.installs != 1 {
		t.Fatal("did not apply")
	}
}
func TestSavedDashboardEditsOnlyRequestedChoice(t *testing.T) {
	b := &fakeBackend{status: installer.Status{ClaudeInstalled: true, ExtensionInstalled: true, Features: installer.Features{Font: true, Theme: true, RTL: true, FontFamily: "vazirmatn", ThemeName: "gruvbox"}}}
	m := New(b)
	v, _ := m.Update(m.Init()())
	m = v.(Model)
	if m.screen != "settings" {
		t.Fatal("saved setup should show settings")
	}
	m, _ = press(m, tea.KeyDown)
	m, _ = press(m, tea.KeyEnter)
	if m.screen != "theme" {
		t.Fatal("wrong edit")
	}
	m, _ = press(m, tea.KeyDown)
	m, _ = press(m, tea.KeyEnter)
	if m.screen != "settings" || m.draft.Theme || m.draft.FontFamily != "vazirmatn" || !m.draft.RTL {
		t.Fatal("edit changed other choices")
	}
}
func TestBackAndEscapePreserveSelections(t *testing.T) {
	m, _ := ready()
	m, _ = press(m, tea.KeyDown)
	m, _ = press(m, tea.KeyEnter)
	m, _ = press(m, tea.KeyEsc)
	if m.screen != "font" || m.draft.FontFamily != "vazirmatn" || m.cursor != 1 {
		t.Fatal("back lost selection")
	}
}
func TestThemePreviewChangesBeforeApplying(t *testing.T) {
	m, b := ready()
	m.screen = "theme"
	m.height = 30
	a := m.View().Content
	m, _ = press(m, tea.KeyDown)
	z := m.View().Content
	if a == z || !strings.Contains(ansi.Strip(z), "Gruvbox Dark") || !strings.Contains(ansi.Strip(z), "Preview") || b.installs != 0 {
		t.Fatal("preview missing or applied")
	}
}
func TestReviewRowsStayAlignedAndFooterVisible(t *testing.T) {
	for _, size := range [][2]int{{60, 22}, {60, 24}, {80, 24}, {100, 36}} {
		m, _ := ready()
		m.width, m.height = size[0], size[1]
		m.screen = "review"
		s := ansi.Strip(m.View().Content)
		for _, label := range []string{"Font", "Theme", "Direction", "Enter", "Esc"} {
			if !strings.Contains(s, label) {
				t.Fatal("hidden review content", size, label, s)
			}
		}
		for _, line := range strings.Split(s, "\n") {
			if ansi.StringWidth(line) > size[0] {
				t.Fatal("overflow", line)
			}
		}
		var positions []int
		for _, line := range strings.Split(s, "\n") {
			for _, value := range []string{"Estedad", "Nord", "Automatic"} {
				if p := strings.Index(line, value); p >= 0 {
					positions = append(positions, ansi.StringWidth(line[:p]))
				}
			}
		}
		if len(positions) != 3 || positions[0] != positions[1] || positions[1] != positions[2] {
			t.Fatal("misaligned values", positions, s)
		}
	}
}

func TestInitialCheckRetryKeepsFirstInstallWizard(t *testing.T) {
	b := &fakeBackend{status: installer.Status{ClaudeInstalled: true, Features: installer.DefaultFeatures()}}
	m := New(b)
	next, _ := m.Update(checked{err: fmt.Errorf("temporary check failure")})
	m = next.(Model)
	m, cmd := press(m, tea.KeyEnter)
	next, _ = m.Update(cmd())
	m = next.(Model)
	if m.screen != "font" {
		t.Fatal("retry skipped the first-install choices", m.screen)
	}
}

func TestRunningClaudeHasDedicatedWaitScreenOnEachPlatform(t *testing.T) {
	for _, platform := range []string{"darwin", "linux", "windows"} {
		m, b := ready()
		m.status.Platform = platform
		m.status.ClaudeRunning = true
		m.screen = "review"
		m.cursor = 3
		m, cmd := press(m, tea.KeyEnter)
		if m.screen != "blocked" || cmd != nil || b.installs != 0 {
			t.Fatal("open app did not stop apply", platform, m.screen)
		}
		view := ansi.Strip(m.View().Content)
		for _, s := range []string{"Claude is still open", "Check again", "Back", "Your choices will stay here"} {
			if !strings.Contains(view, s) {
				t.Fatal("missing wait screen text", s)
			}
		}
		choices := m.draft
		m, _ = press(m, tea.KeyDown)
		m, _ = press(m, tea.KeyEnter)
		if m.screen != "review" || m.draft != choices {
			t.Fatal("back lost choices")
		}
	}
}
func TestBlockedRefreshPreservesDraftAndRequiresSeparateApply(t *testing.T) {
	m, b := ready()
	m.draft.FontFamily = "vazirmatn"
	m.draft.ThemeName = "gruvbox"
	m.screen = "blocked"
	m.status.ClaudeRunning = true
	m, cmd := press(m, tea.KeyEnter)
	if cmd == nil {
		t.Fatal("refresh missing")
	}
	next, _ := m.Update(cmd())
	m = next.(Model)
	if m.screen != "review" || m.draft.FontFamily != "vazirmatn" || b.installs != 0 {
		t.Fatal("refresh applied or reset choices")
	}
}

func TestClaudeOpenedAfterInitialCheckUsesBlockedScreen(t *testing.T) {
	m, b := ready()
	m.screen = "review"
	m.cursor = 3
	b.status.ClaudeRunning = true
	m, cmd := press(m, tea.KeyEnter)
	if cmd == nil {
		t.Fatal("fresh check missing")
	}
	next, _ := m.Update(cmd())
	m = next.(Model)
	if m.screen != "blocked" || b.installs != 0 {
		t.Fatal("stale check bypassed blocked screen", m.screen, b.installs)
	}
}

func TestUpdateShowsVersionsAndPreservesSavedChoices(t *testing.T) {
	for _, platform := range []string{"darwin", "linux", "windows"} {
		b := &fakeBackend{}
		raw := `{"platform":"` + platform + `","claudeInstalled":true,"extensionInstalled":true,"installationDetected":true,"installedVersion":"1.4.1","availableVersion":"1.5.0","updateAvailable":true,"features":{"font":true,"theme":false,"rtl":true,"fontFamily":"vazirmatn","themeName":"gruvbox"}}`
		if e := json.Unmarshal([]byte(raw), &b.status); e != nil {
			t.Fatal(e)
		}
		m := New(b)
		next, _ := m.Update(m.Init()())
		m = next.(Model)
		view := ansi.Strip(m.View().Content)
		for _, want := range []string{"Installed", "1.4.1", "Available", "1.5.0", "Update"} {
			if !strings.Contains(view, want) {
				t.Fatal("missing update UI", platform, want, view)
			}
		}
		expected := m.draft
		for n := 0; n < 3; n++ {
			m, _ = press(m, tea.KeyDown)
		}
		m, _ = press(m, tea.KeyEnter)
		if m.screen != "review" || m.draft != expected || b.installs != 0 {
			t.Fatal("update did not preserve choices and review")
		}
		m, cmd := press(m, tea.KeyEnter)
		m = runFlow(m, cmd)
		if m.screen != "done" || m.draft != expected || b.installs != 1 || b.lastFeatures != expected {
			t.Fatal("update did not finish")
		}
	}
}

func TestVersionRowsAndUpdateActionFitCompactTerminal(t *testing.T) {
	m, _ := ready()
	m.status.InstalledVersion = "1.4.1"
	m.status.AvailableVersion = "1.5.0"
	m.status.InstallationDetected = true
	m.status.UpdateAvailable = true
	for _, screen := range []string{"settings", "review"} {
		for _, height := range []int{22, 24, 30} {
			m.screen = screen
			m.width = 60
			m.height = height
			s := ansi.Strip(m.View().Content)
			for _, label := range []string{"Installed", "1.4.1", "Available", "1.5.0", "[ Update ]", "Enter"} {
				if !strings.Contains(s, label) {
					t.Fatal("version/update action hidden", screen, height, label, s)
				}
			}
		}
	}
}
func TestNewerInstalledVersionCannotBeAppliedFromTheInterface(t *testing.T) {
	m, b := ready()
	m.screen = "review"
	m.cursor = 3
	m.status.InstalledVersion = "9.0.0"
	m.status.AvailableVersion = "1.5.0"
	m, cmd := press(m, tea.KeyEnter)
	if m.screen != "settings" || cmd != nil || b.installs != 0 {
		t.Fatal("older installer allowed apply")
	}
}

func TestCurrentVersionDoesNotAdvertiseAnUpdate(t *testing.T) {
	for _, version := range []string{"1.5.0", "1.5.0.0"} {
		m, _ := ready()
		m.status.InstalledVersion = version
		m.status.AvailableVersion = "1.5.0"
		m.status.InstallationDetected = true
		for _, screen := range []string{"settings", "review"} {
			m.screen = screen
			view := ansi.Strip(m.View().Content)
			if !strings.Contains(view, version) || !strings.Contains(view, "Up to date") {
				t.Fatal("current version status missing", view)
			}
			if strings.Contains(view, "Available") || strings.Contains(view, "[ Update ]") {
				t.Fatal("current version advertised as an update", view)
			}
		}
	}
}
