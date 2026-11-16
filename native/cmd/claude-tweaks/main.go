package main

import (
	tea "charm.land/bubbletea/v2"
	"encoding/json"
	"fmt"
	"github.com/Ssisakhti/Claude-Desktop-Tweaks/native/internal/installer"
	"github.com/Ssisakhti/Claude-Desktop-Tweaks/native/internal/ui"
	"github.com/charmbracelet/x/term"
	"os"
	"os/signal"
	"syscall"
)

var version = "dev"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 1 {
		switch args[0] {
		case "--licenses":
			b, err := installer.Licenses()
			if err != nil {
				return err
			}
			fmt.Print(b)
			return nil
		case "--version":
			fmt.Println("Claude Desktop Tweaks " + version)
			return nil
		case "--help", "-h":
			fmt.Println("Claude Desktop Tweaks\n\nRun without arguments for interactive setup and settings.\n--check     Read-only system status as JSON\n--version   Show version\n--licenses  Show bundled license notices\n\nmacOS, Ubuntu 22.04+, Debian 12+. No Node.js or Go required. Quit Claude before applying changes.")
			return nil
		}
	}
	if len(args) > 0 && (len(args) != 1 || args[0] != "--check") {
		return fmt.Errorf("unknown option; use --help")
	}
	service, err := installer.New()
	if err != nil {
		return err
	}
	if len(args) == 1 {
		s, err := service.Check()
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(s)
	}
	if !term.IsTerminal(os.Stdin.Fd()) || !term.IsTerminal(os.Stdout.Fd()) {
		return fmt.Errorf("interactive setup needs a terminal; use --check for read-only status")
	}
	return runInterface(service)
}

func runInterface(service installer.Operations, options ...tea.ProgramOption) error {
	session := installer.NewSession(service)
	options = append(options, tea.WithoutSignalHandler())
	program := tea.NewProgram(ui.New(session), options...)
	signals := make(chan os.Signal, 4)
	done := make(chan struct{})
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer func() { session.Close(); signal.Stop(signals); close(done) }()
	go func() {
		for {
			select {
			case <-signals:
				program.Send(tea.KeyPressMsg{Code: 'c', Mod: tea.ModCtrl})
			case <-done:
				return
			}
		}
	}()
	final, err := program.Run()
	if err != nil {
		return err
	}
	if model, ok := final.(ui.Model); ok {
		return model.Error()
	}
	return nil
}
