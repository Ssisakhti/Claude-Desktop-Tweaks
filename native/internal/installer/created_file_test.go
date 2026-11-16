//go:build !windows

package installer

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

type faultingFile struct {
	*os.File
	writeErr, syncErr, closeErr error
	short                       bool
	afterWrite                  func()
}

func (f *faultingFile) Write(b []byte) (int, error) {
	if f.writeErr != nil || f.short {
		n, err := f.File.Write(b[:len(b)/2])
		if f.afterWrite != nil {
			f.afterWrite()
		}
		if err != nil {
			return n, err
		}
		return n, f.writeErr
	}
	return f.File.Write(b)
}
func (f *faultingFile) Sync() error {
	if err := f.File.Sync(); err != nil {
		return err
	}
	return f.syncErr
}
func (f *faultingFile) Close() error { return errors.Join(f.File.Close(), f.closeErr) }
func createdFixture(t *testing.T) (*safeFS, string, *os.File) {
	t.Helper()
	i, _ := fixture(t)
	f, err := i.files()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { f.root.Close() })
	p := filepath.Join(i.Home, "new-file")
	file, err := os.OpenFile(p, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	return f, p, file
}
func TestFailedCreatedFileIsRemovedAndRetrySucceeds(t *testing.T) {
	for _, tc := range []struct {
		name                              string
		writeErr, syncErr, closeErr, want error
		short                             bool
	}{
		{name: "disk full during write", writeErr: syscall.ENOSPC, want: syscall.ENOSPC},
		{name: "I/O error during sync", syncErr: syscall.EIO, want: syscall.EIO},
		{name: "I/O error during close", closeErr: syscall.EIO, want: syscall.EIO},
		{name: "short write without error", short: true, want: io.ErrShortWrite},
		{name: "write and close failures", writeErr: syscall.ENOSPC, closeErr: syscall.EIO, want: syscall.ENOSPC},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f, p, file := createdFixture(t)
			fault := &faultingFile{File: file, writeErr: tc.writeErr, syncErr: tc.syncErr, closeErr: tc.closeErr, short: tc.short}
			_, err := f.writeCreated(p, fault, []byte("installation lock token"))
			if !errors.Is(err, tc.want) {
				t.Fatalf("original I/O error lost: %v", err)
			}
			if tc.closeErr != nil && !errors.Is(err, tc.closeErr) {
				t.Fatalf("close error lost: %v", err)
			}
			if _, err = file.Stat(); !errors.Is(err, os.ErrClosed) {
				t.Fatalf("descriptor left open: %v", err)
			}
			if _, err = os.Lstat(p); !os.IsNotExist(err) {
				t.Fatalf("failed exclusive write left a file: %v", err)
			}
			if err = f.exclusive(p, []byte("retry succeeded")); err != nil {
				t.Fatalf("retry blocked: %v", err)
			}
		})
	}
}
func TestFailedCreatedFilePreservesReplacements(t *testing.T) {
	for _, kind := range []string{"file", "directory", "symlink"} {
		t.Run(kind, func(t *testing.T) {
			f, p, file := createdFixture(t)
			outside := filepath.Join(t.TempDir(), "foreign")
			if err := os.WriteFile(outside, []byte("foreign data"), 0600); err != nil {
				t.Fatal(err)
			}
			fault := &faultingFile{File: file, writeErr: syscall.ENOSPC, afterWrite: func() {
				if err := os.Remove(p); err != nil {
					t.Fatal(err)
				}
				switch kind {
				case "file":
					if err := os.WriteFile(p, []byte("foreign data"), 0600); err != nil {
						t.Fatal(err)
					}
				case "directory":
					if err := os.Mkdir(p, 0700); err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(filepath.Join(p, "keep"), []byte("foreign data"), 0600); err != nil {
						t.Fatal(err)
					}
				case "symlink":
					if err := os.Symlink(outside, p); err != nil {
						t.Fatal(err)
					}
				}
			}}
			_, err := f.writeCreated(p, fault, []byte("lock token"))
			if !errors.Is(err, syscall.ENOSPC) || !strings.Contains(err.Error(), "replaced") {
				t.Fatalf("replacement not reported: %v", err)
			}
			readPath := p
			if kind == "directory" {
				readPath = filepath.Join(p, "keep")
			}
			b, err := os.ReadFile(readPath)
			if err != nil || string(b) != "foreign data" {
				t.Fatalf("foreign replacement changed: %q %v", b, err)
			}
			if kind == "symlink" {
				s, err := os.Lstat(p)
				if err != nil || s.Mode()&os.ModeSymlink == 0 {
					t.Fatal("replacement link removed")
				}
			}
		})
	}
}
func TestFailedCreatedFileReportsCleanupPermissionError(t *testing.T) {
	if os.Getuid() == 0 {
		t.Skip("root can unlink in read-only directories")
	}
	f, p, file := createdFixture(t)
	dir := filepath.Dir(p)
	t.Cleanup(func() { os.Chmod(dir, 0700) })
	fault := &faultingFile{File: file, writeErr: syscall.ENOSPC, afterWrite: func() {
		if err := os.Chmod(dir, 0500); err != nil {
			t.Fatal(err)
		}
	}}
	_, err := f.writeCreated(p, fault, []byte("lock token"))
	if !errors.Is(err, syscall.ENOSPC) || !errors.Is(err, os.ErrPermission) || !strings.Contains(err.Error(), "cleanup") {
		t.Fatalf("cleanup failure hidden: %v", err)
	}
}

func TestLockReleasePreservesReplacementAndReportsFailure(t *testing.T) {
	i, s := fixture(t)
	run := i.Run
	replaced := false
	i.Run = func(command string, args ...string) (string, error) {
		output, err := run(command, args...)
		if command == "/bin/launchctl" && args[0] == "print" && s.loaded && !replaced {
			replaced = true
			p := filepath.Join(i.stateDir(), ".extension-install.lock")
			// Keep the original inode alive while installing a foreign replacement.
			original, e := os.Open(p)
			if e != nil {
				t.Fatal(e)
			}
			t.Cleanup(func() { original.Close() })
			if e = os.Remove(p); e != nil {
				t.Fatal(e)
			}
			if e = os.WriteFile(p, []byte("foreign lock"), 0600); e != nil {
				t.Fatal(e)
			}
		}
		return output, err
	}
	_, err := i.Install(DefaultFeatures())
	if err == nil || !strings.Contains(err.Error(), "lock cleanup failed") || !strings.Contains(err.Error(), "replaced") {
		t.Fatalf("lock release failure hidden: %v", err)
	}
	b, e := os.ReadFile(filepath.Join(i.stateDir(), ".extension-install.lock"))
	if e != nil || string(b) != "foreign lock" {
		t.Fatalf("foreign lock was not preserved: %q %v", b, e)
	}
	receipt, e := i.ReadReceipt()
	if e != nil || receipt.Features != DefaultFeatures() {
		t.Fatal("completed installation files were lost")
	}
}
