//go:build !windows

package main

import (
	"bufio"
	tea "charm.land/bubbletea/v2"
	"context"
	"fmt"
	"github.com/Ssisakhti/Claude-Desktop-Tweaks/native/internal/installer"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"syscall"
	"testing"
	"time"
)

type signalFixture struct{ directory string }

func (s signalFixture) Check() (installer.Status, error) {
	return installer.Status{Platform: "darwin", ClaudeInstalled: true, Features: installer.DefaultFeatures()}, nil
}
func (s signalFixture) Install(installer.Features) (installer.Result, error) {
	fmt.Println("STARTED")
	defer os.WriteFile(filepath.Join(s.directory, "cleaned"), []byte("complete"), 0600)
	for {
		if _, e := os.Stat(filepath.Join(s.directory, "release")); e == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	return installer.Result{Changed: true}, nil
}
func (s signalFixture) InstallClaude(bool) error { return nil }
func TestSignalHelper(t *testing.T) {
	directory := os.Getenv("CDT_SIGNAL_FIXTURE")
	if directory == "" {
		return
	}
	err := runInterface(signalFixture{directory}, tea.WithInput(os.Stdin), tea.WithOutput(io.Discard), tea.WithoutRenderer(), tea.WithWindowSize(100, 36), tea.WithFilter(func(_ tea.Model, msg tea.Msg) tea.Msg {
		if reflect.TypeOf(msg) != nil && reflect.TypeOf(msg).Name() == "checked" {
			fmt.Println("READY")
		}
		return msg
	}))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(directory, "cleaned")); err != nil {
		t.Fatal("program returned before operation cleanup")
	}
}
func TestSIGTERMWaitsForTransactionCleanup(t *testing.T) {
	directory := t.TempDir()
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestSignalHelper$")
	cmd.Env = append(os.Environ(), "CDT_SIGNAL_FIXTURE="+directory)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = cmd.Process.Kill() }()
	lines := make(chan string, 32)
	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
		close(lines)
	}()
	waitFor := func(want string) {
		t.Helper()
		for {
			select {
			case line, ok := <-lines:
				if !ok {
					t.Fatalf("child exited before %s", want)
				}
				if line == want {
					return
				}
			case <-ctx.Done():
				t.Fatalf("timeout waiting for %s", want)
			}
		}
	}
	waitFor("READY")
	if _, err = io.WriteString(stdin, "\r\r\r"); err != nil {
		t.Fatal(err)
	}
	waitFor("STARTED")
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	if err = cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	select {
	case err = <-done:
		t.Fatalf("process exited before cleanup was released: %v", err)
	case <-time.After(100 * time.Millisecond):
	}
	if err = os.WriteFile(filepath.Join(directory, "release"), []byte("continue"), 0600); err != nil {
		t.Fatal(err)
	}
	select {
	case err = <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal("program failed to finish after cleanup")
	}
	if _, err = os.Stat(filepath.Join(directory, "cleaned")); err != nil {
		t.Fatal("transaction cleanup was skipped")
	}
}
