//go:build !windows

package installer

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"testing"
	"time"
)

// A per-process file-size limit reproduces a real failed disk write without
// filling a disk or changing the parent process's resource limits.
func TestDiskWriteFailureAllowsImmediateInstallRetry(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestDiskWriteFailureHelper$")
	cmd.Env = append(os.Environ(), "CDT_DISK_FAILURE_HELPER=1")
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("disk-write regression: %v\n%s", err, output)
	}
}
func TestDiskWriteFailureHelper(t *testing.T) {
	if os.Getenv("CDT_DISK_FAILURE_HELPER") != "1" {
		return
	}
	i, _ := fixture(t)
	var previous syscall.Rlimit
	if err := syscall.Getrlimit(syscall.RLIMIT_FSIZE, &previous); err != nil {
		t.Fatal(err)
	}
	signal.Ignore(syscall.SIGXFSZ)
	limited := previous
	limited.Cur = 0
	if err := syscall.Setrlimit(syscall.RLIMIT_FSIZE, &limited); err != nil {
		t.Fatal(err)
	}
	defer syscall.Setrlimit(syscall.RLIMIT_FSIZE, &previous)
	_, writeErr := i.Install(DefaultFeatures())
	if err := syscall.Setrlimit(syscall.RLIMIT_FSIZE, &previous); err != nil {
		t.Fatal(err)
	}
	if writeErr == nil {
		t.Fatal("the real disk-write failure was ignored")
	}
	if _, err := os.Lstat(i.stateDir() + "/.extension-install.lock"); !os.IsNotExist(err) {
		t.Fatalf("failed acquisition left an installation lock: %v", err)
	}
	if !errors.Is(writeErr, syscall.EFBIG) {
		t.Fatalf("disk error was reported as another installation: %v", writeErr)
	}
	if _, err := i.Install(DefaultFeatures()); err != nil {
		t.Fatalf("retry after the disk write recovers was blocked: %v", err)
	}
}
