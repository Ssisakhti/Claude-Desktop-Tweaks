// Package ui presents the English Nord setup and settings dashboard.
package ui

import (
	tea "charm.land/bubbletea/v2"
	lip "charm.land/lipgloss/v2"
	"errors"
	"fmt"
	"github.com/Ssisakhti/Claude-Desktop-Tweaks/native/internal/installer"
	"github.com/charmbracelet/x/ansi"
	"strings"
	"time"
	"unicode"
)

type Backend interface {
	Check() (installer.Status, error)
	Install(installer.Features) (installer.Result, error)
	InstallClaude(bool) error
}
type checked struct {
	status installer.Status
	err    error
}
type installed struct {
	result installer.Result
	err    error
}
type downloaded struct{ err error }
type tick time.Time

type Model struct {
	backend                      Backend
	status                       installer.Status
	draft                        installer.Features
	screen, returnTo, operation  string
	width, height, cursor, frame int
	initialized                  bool
	exitPending                  bool
	err                          error
	result                       installer.Result
}

func New(b Backend) Model {
	return Model{backend: b, draft: installer.DefaultFeatures(), screen: "loading", width: 100, height: 36}
}
func (m Model) Init() tea.Cmd { return m.check() }
func (m Model) check() tea.Cmd {
	return func() tea.Msg { s, e := m.backend.Check(); return checked{s, e} }
}
func pulse() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg { return tick(t) })
}
func (m Model) dirty() bool { return m.initialized && m.draft != m.status.Features }
func (m Model) busy() bool  { return m.screen == "working" }
func (m Model) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := message.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case checked:
		m.status.Platform = msg.status.Platform
		if msg.err != nil {
			m.err = msg.err
			m.screen = "error"
			return m, nil
		}
		m.status = msg.status
		if !m.initialized {
			m.draft = msg.status.Features
			m.initialized = true
		}
		m.screen = "check"
		if m.returnTo != "" {
			m.screen = m.returnTo
			m.returnTo = ""
		}
		return m, nil
	case installed:
		m.err = nil
		if msg.err != nil {
			m.err = msg.err
			m.screen = "error"
		} else {
			m.result = msg.result
			m.status.Features = m.draft
			m.status.ExtensionInstalled = true
			m.screen = "done"
		}
		if m.exitPending {
			return m, tea.Quit
		}
		return m, nil
	case downloaded:
		m.err = nil
		if msg.err != nil {
			m.err = msg.err
			m.screen = "error"
			if m.exitPending {
				return m, tea.Quit
			}
			return m, nil
		}
		if m.exitPending {
			return m, tea.Quit
		}
		m.returnTo = "features"
		m.screen = "loading"
		return m, m.check()
	case tick:
		if m.busy() {
			m.frame++
			return m, pulse()
		}
		return m, nil
	case tea.KeyPressMsg:
		key := msg.String()
		if m.busy() {
			if key == "q" || key == "ctrl+c" {
				m.exitPending = true
			}
			return m, nil
		}
		if m.screen == "discard" {
			if key == "y" {
				return m, tea.Quit
			}
			if key == "n" || key == "esc" || key == "enter" {
				m.screen = m.returnTo
			}
			return m, nil
		}
		if key == "q" || key == "ctrl+c" {
			if m.dirty() {
				m.returnTo = m.screen
				m.screen = "discard"
				return m, nil
			}
			return m, tea.Quit
		}
		if m.width < 60 || m.height < 22 {
			return m, nil
		}
		switch m.screen {
		case "check":
			if key == "enter" {
				if m.status.ClaudeInstalled {
					m.screen = "features"
				} else {
					m.screen = "download"
				}
			}
			if key == "r" {
				m.screen = "loading"
				return m, m.check()
			}
		case "download":
			if key == "y" {
				m.screen = "working"
				m.operation = "download"
				return m, tea.Batch(func() tea.Msg { return downloaded{m.backend.InstallClaude(true)} }, pulse())
			}
			if key == "n" || key == "esc" {
				m.screen = "check"
			}
		case "features":
			switch key {
			case "up", "k":
				m.cursor = (m.cursor + 2) % 3
			case "down", "j", "tab":
				m.cursor = (m.cursor + 1) % 3
			case "1", "2", "3":
				m.cursor = int(key[0] - '1')
				m.toggle()
			case "space", " ":
				m.toggle()
			case "enter":
				m.screen = "review"
			case "esc":
				m.screen = "check"
			}
		case "review":
			if key == "esc" {
				m.screen = "features"
			}
			if key == "r" {
				m.returnTo = "review"
				m.screen = "loading"
				return m, m.check()
			}
			if key == "enter" && !m.status.ClaudeRunning {
				m.screen = "working"
				m.operation = "install"
				return m, tea.Batch(func() tea.Msg { r, e := m.backend.Install(m.draft); return installed{r, e} }, pulse())
			}
		case "done":
			if key == "enter" {
				m.screen = "features"
			}
		case "error":
			if key == "enter" || key == "r" {
				m.err = nil
				m.screen = "loading"
				return m, m.check()
			}
			if key == "esc" {
				m.screen = "features"
			}
		}
	}
	return m, nil
}
func (m *Model) toggle() {
	switch m.cursor {
	case 0:
		m.draft.Font = !m.draft.Font
	case 1:
		m.draft.Theme = !m.draft.Theme
	case 2:
		m.draft.RTL = !m.draft.RTL
	}
}

var (
	night  = lip.Color("#2e3440")
	panel  = lip.Color("#3b4252")
	edge   = lip.Color("#4c566a")
	snow   = lip.Color("#eceff4")
	muted  = lip.Color("#d8dee9")
	frost  = lip.Color("#88c0d0")
	green  = lip.Color("#a3be8c")
	yellow = lip.Color("#ebcb8b")
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
func badge(s string, on bool) string {
	c := edge
	fg := snow
	if on {
		c = green
		fg = night
	}
	return lip.NewStyle().Foreground(fg).Background(c).Padding(0, 1).Bold(true).Render(s)
}
func pair(left, right string, w int) string {
	return left + strings.Repeat(" ", max(1, w-lip.Width(left)-lip.Width(right))) + right
}
func (m Model) View() tea.View {
	w, h := max(1, m.width), max(1, m.height)
	if w < 60 || h < 22 {
		content := "CLAUDE TWEAKS\n\nPlease enlarge this terminal.\nMinimum size: 60 columns x 22 rows.\n\nQ  Exit"
		if m.screen == "discard" {
			content = "CLAUDE TWEAKS\n\nDiscard unsaved choices? [y/N]\nY Discard and exit\nN Keep editing"
		}
		v := tea.NewView(fit(content, w, h))
		v.AltScreen = true
		v.BackgroundColor = night
		v.ForegroundColor = snow
		return v
	}
	width := min(w-4, 108)
	header := pair(accent.Render("◈  CLAUDE TWEAKS"), badge(" "+m.platformName()+" ", false), width)
	step := 0
	if m.screen == "features" || m.screen == "review" || m.screen == "discard" {
		step = 1
	}
	if m.screen == "done" || m.busy() {
		step = 2
	}
	labels := []string{"01  System check", "02  Make it yours", "03  Apply"}
	for n, label := range labels {
		if n == step {
			labels[n] = accent.Render(label)
		} else {
			labels[n] = dim.Render(label)
		}
	}
	header += "\n" + dim.Render("A quieter workspace. Your way.") + "\n\n" + strings.Join(labels, "   ──   ")
	bodyWidth := width
	wide := width >= 96 && h >= 32
	if wide {
		bodyWidth = width - 32
	}
	body := m.body(bodyWidth, h)
	if wide {
		body = lip.JoinHorizontal(lip.Top, body, "  ", m.sidebar(30))
	}
	footer := m.help()
	if m.screen == "features" {
		state := "Saved preferences"
		if !m.status.ExtensionInstalled {
			state = "Not installed yet"
		} else if m.dirty() {
			state = "Unsaved changes"
		}
		footer = dim.Render(state) + "\n" + footer
	}
	content := header + "\n\n" + body + "\n\n" + footer
	// Compact height keeps every action visible; wrapping is measured in terminal cells.
	content = fit(content, width, h-2)
	canvas := lip.NewStyle().Background(night).Foreground(snow).Width(w).Height(h).Padding(1, 2).Render(content)
	v := tea.NewView(canvas)
	v.AltScreen = true
	v.BackgroundColor = night
	v.ForegroundColor = snow
	v.WindowTitle = "Claude Desktop Tweaks"
	return v
}
func (m Model) body(w, h int) string {
	heading := func(title, sub string) string { return text.Bold(true).Render(title) + "\n" + dim.Width(w).Render(sub) }
	switch m.screen {
	case "loading":
		return heading("Checking your setup…", "Reading local settings. No changes are being made.")
	case "check":
		claude := "Missing · approval required"
		if m.status.ClaudeInstalled {
			claude = "Found"
		}
		closed := "Closed · ready to apply"
		if m.status.ClaudeRunning {
			closed = "Open · quit before applying"
		}
		saved := "New setup"
		if m.status.ExtensionInstalled {
			saved = "Installed · settings restored"
		}
		rows := []string{heading("Everything starts here.", "Your choices stay on this computer."), "", pair(m.platformName(), badge("READY", true), w), pair("Claude Desktop", text.Render(claude), w), pair("Application status", dim.Render(closed), w), pair("Your preferences", dim.Render(saved), w), "", accent.Render("One executable. No Node.js or Go required."), dim.Width(w).Render("Uses a local extension. Claude's app files and your conversations stay unchanged.")}
		return strings.Join(rows, "\n")
	case "features":
		rows := []string{heading("Make Claude feel like yours.", "Choose any combination. Change it any time."), ""}
		names := []string{"Persian font", "Theme", "Right-to-left"}
		descs := []string{"Estedad variable · weights 100–900", "Nord · Polar Night surfaces · Frost accents", "Mixed Persian and English · content-aware"}
		values := []bool{m.draft.Font, m.draft.Theme, m.draft.RTL}
		for n, name := range names {
			on, mark := "OFF", "○"
			if values[n] {
				on, mark = "ON", "●"
			}
			border := edge
			if n == m.cursor {
				border = frost
			}
			title := pair(fmt.Sprintf("%s  %d  %s", mark, n+1, name), badge(on, values[n]), w-4)
			card := lip.NewStyle().Border(lip.RoundedBorder()).BorderForeground(border).Background(panel).Padding(0, 1).Width(w).Render(text.Render(title) + "\n" + dim.Render(descs[n]))
			if h < 30 {
				card = lip.NewStyle().BorderLeft(true).BorderStyle(lip.ThickBorder()).BorderForeground(border).Width(w).Render(title)
			}
			rows = append(rows, card)
		}
		return strings.Join(rows, "\n")
	case "review":
		note := "Claude is closed. Ready when you are."
		color := green
		if m.status.ClaudeRunning {
			note = "Claude is open. Save your work and quit it, then press R."
			color = yellow
		}
		return heading("Your setup, ready to apply.", "Review your choices before anything changes.") + "\n\n" + m.summary(w) + "\n\n" + lip.NewStyle().Foreground(color).Width(w).Render(note) + "\n\n" + dim.Width(w).Render(m.startupHint())
	case "download":
		if m.status.Platform == "windows" {
			return heading("Claude Desktop is missing.", "Install the official Windows app first.") + "\n\n" + text.Width(w).Render("Source       Anthropic's official Claude Setup\nVerification Windows vendor signature\nPermission   Approve any system prompt yourself") + "\n\n" + dim.Width(w).Render("This downloads and opens Claude Setup. After installation, open Claude once, quit it, and return here. No download starts until you approve.") + "\n\n" + accent.Render("Approve Claude Setup download?  [y/N]")
		}

		if m.status.Platform == "linux" {
			return heading("Claude Desktop is missing.", "Install the official Ubuntu or Debian package.") + "\n\n" + text.Width(w).Render("Source       Anthropic's signed apt repository\nDestination  System package manager\nVerification Vendor key fingerprint and apt signatures") + "\n\n" + dim.Width(w).Render("Installs Claude and required packages. A system permission prompt will request administrator approval. Requires PolicyKit (pkexec). Repository settings stay available for future updates. No installation starts until you approve.") + "\n\n" + accent.Render("Approve package installation?  [y/N]")
		}
		return heading("Claude Desktop is missing.", "Install the official app before applying your tweaks.") + "\n\n" + text.Width(w).Render("Source       Anthropic's official download\nDestination  Your Applications folder\nVerification Vendor signature and macOS checks") + "\n\n" + dim.Width(w).Render("This downloads Claude and copies the verified app. Your existing apps are preserved. No download starts until you approve.") + "\n\n" + accent.Render("Approve download and installation?  [y/N]")
	case "working":
		label := "Applying your choices"
		detail := "Creating a backup, installing the extension, and checking startup."
		if m.operation == "download" {
			label = "Installing Claude Desktop"
			detail = "Downloading from Anthropic, verifying the app, and installing it."
		}
		frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
		return heading(accent.Render(frames[m.frame%len(frames)]+"  "+label), detail) + "\n\n" + m.summary(w) + "\n\n" + dim.Width(w).Render("Please keep this window open until setup finishes. Your apps will not be quit automatically.")
	case "done":

		return heading(lip.NewStyle().Foreground(green).Render("✓  You are all set."), "Your preferences have been installed.") + "\n\n" + m.summary(w) + "\n\n" + accent.Render("Open Claude normally to apply your choices.") + "\n" + dim.Width(w).Render("Run claude-tweaks again whenever you want to change them.")
	case "error":
		e := m.err
		if e == nil {
			e = errors.New("setup could not finish")
		}
		return heading(lip.NewStyle().Foreground(red).Render("Let's fix this before continuing."), "Setup did not complete. Review the message below.") + "\n\n" + text.Width(w).Render(safe(e.Error())) + "\n\n" + dim.Width(w).Render("You can retry the checks or return to your choices. Existing backups are preserved.")
	case "discard":
		return heading("Leave without applying?", "Your installed preferences will stay as they are.") + "\n\n" + accent.Render("Discard your unsaved choices?  [y/N]")
	}
	return ""
}
func (m Model) summary(w int) string {
	items := []struct {
		name, value string
		on          bool
	}{{"Persian font", "Estedad · 100–900", m.draft.Font}, {"Theme", "Nord", m.draft.Theme}, {"Text direction", "Automatic RTL", m.draft.RTL}}
	lines := []string{}
	for _, i := range items {
		value := "Off"
		if i.on {
			value = i.value
		}
		lines = append(lines, pair(i.name, text.Render(value), w))
	}
	if !m.draft.Font && !m.draft.Theme && !m.draft.RTL {
		lines = append(lines, "", dim.Width(w).Render("All features off · use Claude's default appearance."))
	}
	return strings.Join(lines, "\n")
}
func (m Model) sidebar(w int) string {
	swatches := ""
	for _, c := range []string{"#8fbcbb", "#88c0d0", "#81a1c1", "#5e81ac"} {
		swatches += lip.NewStyle().Background(lip.Color(c)).Render("    ")
	}
	title := "YOUR WORKSPACE"
	body := accent.Render(title) + "\n\n" + text.Bold(true).Render("Less friction.\nMore focus.") + "\n\n" + swatches + "\n\n" + dim.Width(w-4).Render("Font, color, and direction.\nThree independent choices.\nOne calmer Claude.") + "\n\n" + text.Render("LOCAL BY DESIGN") + "\n" + dim.Width(w-4).Render("No account. No analytics.\nNo conversation access.") + "\n\n" + dim.Width(w-4).Render("Estedad is a compact\nvariable WOFF2 font.")
	return lip.NewStyle().Border(lip.RoundedBorder()).BorderForeground(edge).Padding(1, 1).Width(w).Render(body)
}
func (m Model) help() string {
	switch m.screen {
	case "features":
		return accent.Render("↑↓ Move   Space Toggle   Enter Review") + "\n" + dim.Render("1–3 Toggle directly   Esc Back   Q Exit")
	case "review":
		if m.status.ClaudeRunning {
			return accent.Render("R Check again   Esc Edit   Q Exit")
		}
		return accent.Render("Enter Apply choices   Esc Edit   Q Exit")
	case "download":
		return accent.Render("Y Approve and install   N Back   Q Exit")
	case "working":
		if m.exitPending {
			return dim.Render("Exit requested · finishing safely before closing")
		}
		return dim.Render("Working safely · please wait")
	case "done":
		return accent.Render("Enter Change settings   Q Exit")
	case "error":
		return accent.Render("Enter Retry checks   Esc Edit   Q Exit")
	case "discard":
		return accent.Render("Y Discard and exit   N Keep editing")
	default:
		return accent.Render("Enter Continue   R Refresh   Q Exit")
	}
}
func fit(s string, w, h int) string {
	lines := strings.Split(s, "\n")
	for n, line := range lines {
		lines[n] = ansi.Truncate(line, w, "")
	}
	if len(lines) > h {
		lines = lines[:h]
	}
	return strings.Join(lines, "\n")
}

// Error reports the final failure after the terminal has been restored.
func (m Model) Error() error { return m.err }

func (m Model) platformName() string {
	if m.status.Platform == "windows" {
		return "Windows 11"
	}
	if m.status.Platform == "linux" {
		return "Linux"
	}
	return "macOS"
}

func (m Model) startupHint() string {
	return "The current extension is backed up when replaced. Open Claude normally after setup."
}
