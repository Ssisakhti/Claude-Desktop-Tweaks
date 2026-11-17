package ui

import (
	tea "charm.land/bubbletea/v2"
	lip "charm.land/lipgloss/v2"
	"fmt"
	"github.com/charmbracelet/x/ansi"
	"strings"
	"unicode"
)

var (
	night  = lip.Color("#2e3440")
	edge   = lip.Color("#4c566a")
	snow   = lip.Color("#eceff4")
	muted  = lip.Color("#d8dee9")
	frost  = lip.Color("#88c0d0")
	green  = lip.Color("#a3be8c")
	red    = lip.Color("#bf616a")
	text   = lip.NewStyle().Foreground(snow)
	dim    = lip.NewStyle().Foreground(muted)
	accent = lip.NewStyle().Foreground(frost).Bold(true)
)

func safe(s string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || r == '\u202e' || r == '\u202d' || r == '\u2066' || r == '\u2067' || r == '\u2068' || r == '\u2069' {
			return -1
		}
		return r
	}, ansi.Strip(s))
}
func fit(s string, w, h int) string {
	lines := strings.Split(s, "\n")
	for n, line := range lines {
		lines[n] = ansi.Truncate(line, w, "")
	}
	if len(lines) > h {
		lines = lines[:max(0, h)]
	}
	return strings.Join(lines, "\n")
}
func (m Model) View() tea.View {
	w, h := max(1, m.width), max(1, m.height)
	v := tea.NewView("")
	v.AltScreen = true
	v.BackgroundColor = night
	v.ForegroundColor = snow
	v.WindowTitle = "Claude Desktop Tweaks"
	if w < 60 || h < 22 {
		body := "CLAUDE DESKTOP TWEAKS\n\nPlease enlarge this terminal.\nMinimum: 60 columns x 22 rows.\n\nQ Exit"
		if m.screen == "discard" {
			body = "Discard unsaved choices? [y/N]\n\nY Exit    Enter Keep editing"
		}
		v.Content = fit(body, w, h)
		return v
	}
	width := min(w-4, 72)
	header := accent.Render("CLAUDE DESKTOP TWEAKS") + "\n" + dim.Render(m.platformName()) + "\n" + m.steps()
	body := m.body(width, h)
	// Header and footer have reserved space. Long status/error prose wraps only
	// inside the body, never into action hints. Fixed maximum width avoids drift.
	budget := h - 8
	lines := strings.Split(body, "\n")
	body = fit(body, width, budget)
	if len(lines) > budget {
		body = fit(body, width, budget-1) + "\n" + dim.Render("… Resize the window to see more details.")
	}
	padding := max(0, budget-len(strings.Split(body, "\n")))
	content := header + "\n\n" + body + strings.Repeat("\n", padding) + "\n\n" + m.help()
	v.Content = lip.NewStyle().Foreground(snow).Background(night).Padding(1, 2).Render(fit(content, width, h-2))
	return v
}
func (m Model) steps() string {
	if m.screen == "settings" {
		return dim.Render("Saved preferences")
	}
	if m.screen == "loading" || m.screen == "download" {
		return dim.Render("Setup check")
	}
	n := map[string]int{"font": 0, "theme": 1, "direction": 2, "review": 3, "working": 3, "done": 3}[m.screen]
	labels := []string{"Font", "Theme", "Direction", "Apply"}
	for i, label := range labels {
		if i == n {
			labels[i] = accent.Render(label)
		} else {
			labels[i] = dim.Render(label)
		}
	}
	return strings.Join(labels, "  ─  ")
}
func (m Model) body(w, h int) string {
	heading := func(title, sub string) string { return text.Bold(true).Render(title) + "\n" + dim.Width(w).Render(sub) }
	switch m.screen {
	case "loading":
		return heading("Checking your setup…", "Reading saved choices. No changes yet.")
	case "font", "theme", "direction":
		step := map[string]int{"font": 1, "theme": 2, "direction": 3}[m.screen]
		title := map[string]string{"font": "Choose your Persian font", "theme": "Choose your theme", "direction": "Persian text direction"}[m.screen]
		hint := map[string]string{"font": "For Persian text in chats and artifacts.", "theme": "Preview only. Claude changes after Apply.", "direction": "Automatic keeps Persian RTL and English LTR."}[m.screen]
		rows := []string{heading(fmt.Sprintf("%d of 4 · %s", step, title), hint), ""}
		names := map[string][]string{"font": {"Estedad", "Vazirmatn", "Use Claude default"}, "theme": {"Nord  ·  Cool blue-gray", "Gruvbox Dark  ·  Warm, high contrast", "Use Claude default"}, "direction": {"Automatic", "Use Claude default"}}[m.screen]
		for i, name := range names {
			mark := "  ○ "
			if i == m.cursor {
				mark = "› ● "
			}
			row := mark + name
			if i == m.cursor {
				row = lip.NewStyle().Foreground(frost).Background(edge).Bold(true).Width(w).Render(row)
			} else {
				row = text.Render(row)
			}
			rows = append(rows, row)
			if i < len(names)-1 {
				rows = append(rows, "")
			}
		}
		if m.screen == "theme" {
			rows = append(rows, "", m.themePreview(w))
		}
		if m.screen == "font" {
			rows = append(rows, "", dim.Width(w).Render("Variable weights 100–900. The terminal uses its own font."))
		}
		return strings.Join(rows, "\n")
	case "settings", "review":
		title, sub := "Your preferences", "Choose a row to edit. Apply when ready."
		if m.screen == "review" {
			title = "4 of 4 · Review your choices"
			sub = "Choose a row to edit, or apply below."
		}
		rows := []string{heading(title, sub), "", m.summary(w, true), ""}
		if m.screen == "review" {
			note := "✓ Claude found · closed and ready"
			if m.status.ClaudeRunning {
				note = "Claude is open. Save your work and quit it."
			}
			rows = append(rows, dim.Width(w).Render(note), "")
		} else if m.dirty() {
			rows = append(rows, dim.Render("Unsaved changes"), "")
		}
		action := "Review changes"
		if m.screen == "review" {
			action = "Apply changes"
			if m.status.ClaudeRunning {
				action = "Check again"
			}
		}
		mark := "  "
		if m.cursor == 3 {
			mark = "› "
		}
		button := mark + "[ " + action + " ]"
		if m.cursor == 3 {
			button = accent.Render(button)
		}
		rows = append(rows, button)
		return strings.Join(rows, "\n")
	case "working":
		title, sub := "Applying your choices", "Backing up the extension and checking startup."
		if m.operation == "download" {
			title = "Installing Claude Desktop"
			sub = "Downloading and verifying the official app."
		}
		frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
		return heading(frames[m.frame%len(frames)]+" "+title, sub) + "\n\n" + m.summary(w, false) + "\n\n" + dim.Width(w).Render("Keep this window open until setup finishes.")
	case "done":
		return heading("✓ Your preferences are installed", "Open Claude normally to apply your choices.") + "\n\n" + m.summary(w, false)
	case "error":
		detail := "Setup could not finish."
		if m.err != nil {
			detail = safe(m.err.Error())
		}
		return heading("Setup needs attention", "Your choices are saved in this session.") + "\n\n" + lip.NewStyle().Foreground(red).Width(w).Render(detail) + "\n\n" + dim.Width(w).Render("Retry the check or go back to your choices.")
	case "discard":
		return heading("Leave without applying?", "Installed preferences stay as they are.") + "\n\nDiscard unsaved choices? [y/N]"
	case "download":
		if m.status.Platform == "windows" {
			return heading("Claude Desktop is missing.", "Install the official Windows app first.") + "\n\n" + text.Width(w).Render("Source       Anthropic's official Claude Setup\nVerification Windows vendor signature\nPermission   Approve any system prompt yourself") + "\n\n" + dim.Width(w).Render("This downloads and opens Claude Setup. After installation, open Claude once, quit it, and return here. No download starts until you approve.") + "\n\n" + accent.Render("Approve Claude Setup download?  [y/N]")
		}

		if m.status.Platform == "linux" {
			return heading("Claude Desktop is missing.", "Install the official Ubuntu or Debian package.") + "\n\n" + text.Width(w).Render("Source       Anthropic's signed apt repository\nDestination  System package manager\nVerification Vendor key fingerprint and apt signatures") + "\n\n" + dim.Width(w).Render("Installs Claude and required packages. A system permission prompt will request administrator approval. Requires PolicyKit (pkexec). Repository settings stay available for future updates. No installation starts until you approve.") + "\n\n" + accent.Render("Approve package installation?  [y/N]")
		}
		return heading("Claude Desktop is missing.", "Install the official app before applying your tweaks.") + "\n\n" + text.Width(w).Render("Source       Anthropic's official download\nDestination  Your Applications folder\nVerification Vendor signature and macOS checks") + "\n\n" + dim.Width(w).Render("This downloads Claude and copies the verified app. Your existing apps are preserved. No download starts until you approve.") + "\n\n" + accent.Render("Approve download and installation?  [y/N]")
	}
	return ""
}
func (m Model) summary(w int, editable bool) string {
	font := "Use Claude default"
	if m.draft.Font {
		font = "Estedad"
		if m.draft.FontFamily == "vazirmatn" {
			font = "Vazirmatn"
		}
	}
	theme := "Use Claude default"
	if m.draft.Theme {
		theme = "Nord"
		if m.draft.ThemeName == "gruvbox" {
			theme = "Gruvbox Dark"
		}
	}
	direction := "Use Claude default"
	if m.draft.RTL {
		direction = "Automatic"
	}
	labels := []string{"Font", "Theme", "Direction"}
	values := []string{font, theme, direction}
	rows := []string{}
	for i, label := range labels {
		mark := "  "
		if editable && i == m.cursor {
			mark = "› "
		}
		// A fixed label column and explicit Edit column tie each value to its row.
		row := fmt.Sprintf("%s%-12s%-22s", mark, label, values[i])
		if editable {
			row += "  Edit"
		}
		if editable && i == m.cursor {
			row = lip.NewStyle().Foreground(frost).Background(edge).Bold(true).Width(w).Render(row)
		} else {
			row = text.Render(row)
		}
		rows = append(rows, row, "")
	}
	return strings.TrimSuffix(strings.Join(rows, "\n"), "\n")
}
func (m Model) themePreview(w int) string {
	bg, surface, fg, highlight, secondary := "#2e3440", "#3b4252", "#eceff4", "#88c0d0", "#d8dee9"
	title := "Preview · Nord"
	if m.cursor == 1 {
		bg, surface, fg, highlight, secondary = "#1d2021", "#282828", "#fbf1c7", "#fabd2f", "#d5c4a1"
		title = "Preview · Gruvbox Dark"
	}
	if m.cursor == 2 {
		return dim.Width(w).Render("Preview · Claude default\nYour Claude appearance settings stay in control.")
	}
	line := func(s string) string {
		return lip.NewStyle().Foreground(lip.Color(fg)).Background(lip.Color(bg)).Width(w).Padding(0, 2).Render(s)
	}
	accentStyle := lip.NewStyle().Foreground(lip.Color(highlight)).Background(lip.Color(bg))
	composer := lip.NewStyle().Foreground(lip.Color(secondary)).Background(lip.Color(surface)).Render("  Write a message…  ")
	return line(title) + "\n" + line("Claude   A clearer workspace.") + "\n" + line(accentStyle.Render("Link  ·  Selected item")) + "\n" + line(composer)
}
func (m Model) help() string {
	switch m.screen {
	case "font", "theme", "direction":
		return accent.Render("↑↓ Choose    Enter Next    Esc Back    Q Exit")
	case "settings", "review":
		return accent.Render("↑↓ Choose    Enter Select    Esc Back    Q Exit")
	case "download":
		return accent.Render("Y Approve and install    N Exit")
	case "working":
		if m.exitPending {
			return dim.Render("Finishing safely before closing…")
		}
		return dim.Render("Applying · please wait")
	case "done":
		return accent.Render("Enter Settings    Q Exit")
	case "error":
		return accent.Render("Enter Retry    Esc Back    Q Exit")
	case "discard":
		return accent.Render("Y Discard    Enter Keep editing")
	default:
		return dim.Render("Checking · Q Exit")
	}
}
