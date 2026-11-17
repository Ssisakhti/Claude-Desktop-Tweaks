// Package ui presents the English setup wizard and saved preferences.
package ui

import (
	tea "charm.land/bubbletea/v2"
	"github.com/Ssisakhti/Claude-Desktop-Tweaks/native/internal/installer"
	"time"
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
	backend                                  Backend
	status                                   installer.Status
	draft                                    installer.Features
	screen, returnTo, operation, editingFrom string
	width, height, cursor, frame             int
	initialized, exitPending                 bool
	err                                      error
	result                                   installer.Result
}

func New(b Backend) Model {
	return Model{backend: b, draft: installer.DefaultFeatures(), screen: "loading", width: 80, height: 30}
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
func (m *Model) goTo(screen string) {
	m.screen = screen
	m.cursor = 0
	switch screen {
	case "font":
		if !m.draft.Font {
			m.cursor = 2
		} else if m.draft.FontFamily == "vazirmatn" {
			m.cursor = 1
		}
	case "theme":
		if !m.draft.Theme {
			m.cursor = 2
		} else if m.draft.ThemeName == "gruvbox" {
			m.cursor = 1
		}
	case "direction":
		if !m.draft.RTL {
			m.cursor = 1
		}
	}
}
func (m *Model) choose() {
	switch m.screen {
	case "font":
		m.draft.Font = m.cursor != 2
		if m.cursor == 1 {
			m.draft.FontFamily = "vazirmatn"
		} else if m.cursor == 0 {
			m.draft.FontFamily = ""
		}
	case "theme":
		m.draft.Theme = m.cursor != 2
		if m.cursor == 1 {
			m.draft.ThemeName = "gruvbox"
		} else if m.cursor == 0 {
			m.draft.ThemeName = ""
		}
	case "direction":
		m.draft.RTL = m.cursor == 0
	}
}
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
		if !m.status.ClaudeInstalled {
			m.goTo("download")
		} else if m.returnTo == "apply" {
			m.returnTo = ""
			if m.status.ClaudeRunning {
				m.goTo("blocked")
			} else {
				m.screen = "working"
				m.operation = "install"
				return m, tea.Batch(func() tea.Msg { r, e := m.backend.Install(m.draft); return installed{r, e} }, pulse())
			}
		} else if m.returnTo == "blocked" {
			m.returnTo = ""
			if m.status.ClaudeRunning {
				m.goTo("blocked")
			} else {
				m.goTo("review")
				m.cursor = 3
			}
		} else if m.returnTo != "" {
			m.goTo(m.returnTo)
			m.returnTo = ""
		} else if m.status.ExtensionInstalled {
			m.goTo("settings")
		} else {
			m.goTo("font")
		}
		return m, nil
	case installed:
		m.err = msg.err
		if msg.err != nil {
			m.screen = "error"
			m.returnTo = "review"
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
		m.err = msg.err
		if m.exitPending {
			return m, tea.Quit
		}
		if msg.err != nil {
			m.screen = "error"
			return m, nil
		}
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
		case "font", "theme", "direction":
			count := 3
			if m.screen == "direction" {
				count = 2
			}
			if key == "up" {
				m.cursor = (m.cursor + count - 1) % count
				m.choose()
			}
			if key == "down" {
				m.cursor = (m.cursor + 1) % count
				m.choose()
			}
			if key == "enter" {
				m.choose()
				if m.editingFrom != "" {
					target := m.editingFrom
					m.editingFrom = ""
					m.goTo(target)
				} else {
					switch m.screen {
					case "font":
						m.goTo("theme")
					case "theme":
						m.goTo("direction")
					case "direction":
						m.goTo("review")
					}
				}
			}
			if key == "esc" {
				if m.editingFrom != "" {
					target := m.editingFrom
					m.editingFrom = ""
					m.goTo(target)
				} else {
					switch m.screen {
					case "font":
						if m.status.ExtensionInstalled {
							m.goTo("settings")
						}
					case "theme":
						m.goTo("font")
					case "direction":
						m.goTo("theme")
					}
				}
			}
		case "settings", "review":
			if key == "up" {
				m.cursor = (m.cursor + 3) % 4
			}
			if key == "down" {
				m.cursor = (m.cursor + 1) % 4
			}
			if key == "esc" {
				if m.screen == "review" {
					if m.status.ExtensionInstalled {
						m.goTo("settings")
					} else {
						m.goTo("direction")
					}
				}
			}
			if key == "r" {
				m.returnTo = m.screen
				m.screen = "loading"
				return m, m.check()
			}
			if key == "enter" {
				if m.cursor < 3 {
					m.editingFrom = m.screen
					m.goTo([]string{"font", "theme", "direction"}[m.cursor])
				} else if m.screen == "settings" {
					m.goTo("review")
					m.cursor = 3
				} else if !m.status.ClaudeRunning {
					m.returnTo = "apply"
					m.screen = "loading"
					return m, m.check()
				} else {
					m.goTo("blocked")
				}
			}
		case "blocked":
			if key == "up" || key == "down" {
				m.cursor = 1 - m.cursor
			}
			if key == "esc" || (key == "enter" && m.cursor == 1) {
				m.goTo("review")
				m.cursor = 3
			}
			if key == "r" || (key == "enter" && m.cursor == 0) {
				m.returnTo = "blocked"
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
				return m, tea.Quit
			}
		case "done":
			if key == "enter" {
				m.goTo("settings")
			}
		case "error":
			if key == "enter" || key == "r" {
				m.err = nil
				m.screen = "loading"
				return m, m.check()
			}
			if key == "esc" {
				m.err = nil
				if m.status.ClaudeInstalled {
					m.goTo("review")
				} else {
					m.goTo("download")
				}
			}
		}
	}
	return m, nil
}
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
