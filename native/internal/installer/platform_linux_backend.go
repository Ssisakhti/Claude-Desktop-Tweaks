package installer

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func (i *Installer) linuxConfig() string {
	if filepath.IsAbs(i.ConfigHome) {
		return filepath.Clean(i.ConfigHome)
	}
	return filepath.Join(i.Home, ".config")
}
func (i *Installer) linuxData() string {
	if filepath.IsAbs(i.DataHome) {
		return filepath.Clean(i.DataHome)
	}
	return filepath.Join(i.Home, ".local/share")
}
func (i *Installer) systemPath(p string) string {
	root := i.SystemRoot
	if root == "" {
		root = "/"
	}
	return filepath.Join(root, p)
}
func (i *Installer) linuxLauncher() string {
	return filepath.Join(i.linuxData(), "applications/com.anthropic.Claude.desktop")
}

func (i *Installer) linuxDistribution() error {
	b, e := os.ReadFile(i.systemPath("etc/os-release"))
	if e != nil {
		return errors.New("could not identify Linux; Ubuntu 22.04+ or Debian 12+ is required")
	}
	fields := map[string]string{}
	for _, line := range strings.Split(string(b), "\n") {
		k, v, ok := strings.Cut(line, "=")
		if ok {
			fields[k] = strings.Trim(v, "\"'")
		}
	}
	parts := strings.Split(fields["VERSION_ID"], ".")
	major, e := strconv.Atoi(parts[0])
	if e != nil {
		return errors.New("could not identify the Linux release")
	}
	if fields["ID"] == "ubuntu" && (major > 22 || major == 22 && len(parts) > 1 && parts[1] >= "04") || fields["ID"] == "debian" && major >= 12 {
		return nil
	}
	return errors.New("this installer supports official Claude Desktop on Ubuntu 22.04+ or Debian 12+")
}
func (i *Installer) linuxRunning() (bool, error) {
	if i.Run == nil {
		return false, errors.New("system runner unavailable")
	}
	_, e := i.Run("/usr/bin/pgrep", "-u", strconv.Itoa(os.Getuid()), "-x", "claude-desktop|Claude")
	if e == nil {
		return true, nil
	}
	if exitCode(e, 1) {
		return false, nil
	}
	return false, errors.New("could not check whether Claude is running")
}
func (i *Installer) linuxPackage() (bool, error) {
	out, e := i.Run("/usr/bin/dpkg-query", "-W", "-f=${Status}\t${Version}\n", "claude-desktop")
	if exitCode(e, 1) {
		return false, nil
	}
	if e != nil {
		return false, errors.New("could not inspect the official Claude package with dpkg-query")
	}
	if !strings.HasPrefix(out, "install ok installed\t") {
		return false, nil
	}
	if os.Getenv("CLAUDE_USER_DATA_DIR") != "" {
		return false, errors.New("custom CLAUDE_USER_DATA_DIR is not supported; use the standard Claude profile")
	}
	if s, e := os.Stat(i.systemPath("usr/bin/claude-desktop")); e != nil || !s.Mode().IsRegular() {
		return false, errors.New("the installed Claude executable is missing")
	}
	return true, nil
}

func (i *Installer) checkLinux() (Status, error) {
	s := Status{Platform: "linux", Features: DefaultFeatures()}
	if e := i.linuxDistribution(); e != nil {
		return s, e
	}
	installed, e := i.linuxPackage()
	if e != nil {
		return s, e
	}
	s.ClaudeInstalled = installed
	if installed {
		if e = linuxHook(i.systemPath("usr/lib/claude-desktop/resources/app.asar")); e != nil {
			return s, e
		}
	}
	s.ClaudeRunning, e = i.linuxRunning()
	if e != nil {
		return s, e
	}
	f, e := i.files()
	if e != nil {
		return s, e
	}
	defer f.root.Close()
	for _, p := range []string{i.target(), i.receiptPath(), i.linuxLauncher()} {
		if _, e = f.rel(p); e != nil {
			return s, errors.New("XDG configuration and data directories must be inside your home directory")
		}
	}
	b, e := f.read(i.receiptPath())
	if e != nil {
		return s, e
	}
	r, e := decodeReceipt(b)
	if e != nil {
		return s, e
	}
	s.Features = r.Features
	if b != nil {
		source, e := f.read(filepath.Join(i.target(), "content.js"))
		if e != nil {
			return s, e
		}
		launcher, e := f.read(i.linuxLauncher())
		if e != nil {
			return s, e
		}
		s.ExtensionInstalled = source != nil && hash(source) == r.ExtensionSHA256 && launcher != nil && hash(launcher) == r.LauncherSHA256
	}
	return s, nil
}

func (i *Installer) linuxDesktop() ([]byte, error) {
	b, e := os.ReadFile(i.systemPath("usr/share/applications/com.anthropic.Claude.desktop"))
	if e != nil {
		return nil, e
	}
	if len(b) > 128<<10 {
		return nil, errors.New("unexpected Claude desktop entry")
	}
	lines := strings.Split(string(b), "\n")
	count := 0
	for n, line := range lines {
		if !strings.HasPrefix(line, "Exec=") {
			continue
		}
		value := strings.TrimPrefix(line, "Exec=")
		var tail string
		if value == "claude-desktop" || strings.HasPrefix(value, "claude-desktop ") {
			tail = strings.TrimPrefix(value, "claude-desktop")
		} else if value == "/usr/bin/claude-desktop" || strings.HasPrefix(value, "/usr/bin/claude-desktop ") {
			tail = strings.TrimPrefix(value, "/usr/bin/claude-desktop")
		} else {
			return nil, errors.New("unsupported Claude desktop launch command")
		}
		lines[n] = "Exec=/usr/bin/env REACT_PROFILE=1 /usr/bin/claude-desktop" + tail
		count++
	}
	if count == 0 || !bytes.Contains(b, []byte("[Desktop Entry]")) {
		return nil, errors.New("unsupported Claude desktop entry")
	}
	return []byte("# Managed by Claude Desktop Tweaks.\n" + strings.Join(lines, "\n")), nil
}

func (i *Installer) installLinux(features Features) (result Result, retErr error) {
	s, e := i.checkLinux()
	if e != nil {
		return result, e
	}
	if !s.ClaudeInstalled {
		return result, errors.New("Claude Desktop is missing; install the official package first")
	}
	if s.ClaudeRunning {
		return result, errors.New("Quit Claude, then retry. This installer never quits apps")
	}
	desktop, e := i.linuxDesktop()
	if e != nil {
		return result, e
	}
	files, e := Payload(features)
	if e != nil {
		return result, e
	}
	f, e := i.files()
	if e != nil {
		return result, e
	}
	defer f.root.Close()
	target, state, launcher := i.target(), i.stateDir(), i.linuxLauncher()
	oldReceipt, e := f.read(i.receiptPath())
	if e != nil {
		return result, e
	}
	previous, e := decodeReceipt(oldReceipt)
	if e != nil {
		return result, e
	}
	oldLauncher, e := f.read(launcher)
	if e != nil {
		return result, e
	}
	if oldLauncher != nil && (previous.LauncherSHA256 == "" || hash(oldLauncher) != previous.LauncherSHA256) {
		return result, errors.New("an existing Claude desktop entry is not owned by this installer; it was preserved")
	}
	installed, e := f.stat(target)
	if e != nil {
		return result, e
	}
	if installed != nil {
		source, e := f.read(filepath.Join(target, "content.js"))
		if e != nil {
			return result, e
		}
		if source == nil || previous.ExtensionSHA256 == "" || hash(source) != previous.ExtensionSHA256 {
			return result, errors.New("an existing extension is not owned by this installer; it was preserved")
		}
	}
	same := installed != nil
	for name, b := range files {
		if !same {
			break
		}
		now, e := f.read(filepath.Join(target, name))
		if e != nil {
			return result, e
		}
		same = bytes.Equal(now, b)
	}
	record := Receipt{Features: features, ExtensionSHA256: hash(files["content.js"]), LauncherSHA256: hash(desktop)}
	receipt, e := json.MarshalIndent(record, "", "  ")
	if e != nil {
		return result, e
	}
	receipt = append(receipt, '\n')
	if same && bytes.Equal(oldLauncher, desktop) && bytes.Equal(oldReceipt, receipt) {
		return result, nil
	}
	if e = f.parents(state, true); e != nil {
		return result, e
	}
	lock := filepath.Join(state, ".extension-install.lock")
	identity, e := f.createExclusive(lock, []byte(token()))
	if e != nil {
		return result, fmt.Errorf("could not acquire installation lock: %w", e)
	}
	defer func() {
		if e := f.removeCreated(lock, identity); e != nil {
			retErr = errors.Join(retErr, fmt.Errorf("installation lock cleanup failed: %w", e))
		}
	}()
	undo := []func() error{}
	stage := ""
	defer func() {
		if stage != "" {
			_ = f.remove(stage)
		}
		if retErr != nil {
			for n := len(undo) - 1; n >= 0; n-- {
				if e := undo[n](); e != nil {
					retErr = errors.Join(retErr, fmt.Errorf("rollback needs attention; preserve backups: %w", e))
				}
			}
		}
	}()
	running, e := i.linuxRunning()
	if e != nil {
		return result, e
	}
	if running {
		return result, errors.New("Claude opened during setup; quit it and retry")
	}
	backup := filepath.Join(filepath.Dir(target), ".claude-desktop-tweaks-backups", time.Now().UTC().Format("20060102T150405.000000000")+"-"+token())
	if e = f.parents(backup, true); e != nil {
		return result, e
	}
	result.Backup = backup
	write := func(p string, data, before []byte) error {
		if bytes.Equal(data, before) {
			return nil
		}
		if before != nil {
			if e := f.exclusive(filepath.Join(backup, filepath.Base(p)), before); e != nil {
				return e
			}
		}
		if e := f.parents(filepath.Dir(p), true); e != nil {
			return e
		}
		if e := f.write(p, data, before); e != nil {
			return e
		}
		undo = append(undo, func() error {
			now, e := f.read(p)
			if e != nil {
				return e
			}
			if !bytes.Equal(now, data) {
				return errors.New("concurrent file change preserved")
			}
			if before == nil {
				return f.remove(p)
			}
			return f.write(p, before, data)
		})
		return nil
	}
	if !same {
		if e = f.parents(filepath.Dir(target), true); e != nil {
			return result, e
		}
		stage = target + ".stage-" + token()
		if e = f.parents(stage, true); e != nil {
			return result, e
		}
		for name, b := range files {
			if e = f.exclusive(filepath.Join(stage, name), b); e != nil {
				return result, e
			}
		}
		now, e := f.stat(target)
		if e != nil {
			return result, e
		}
		if (now == nil) != (installed == nil) || now != nil && !os.SameFile(now, installed) {
			return result, errors.New("concurrent extension change preserved")
		}
		if installed != nil {
			if e = f.rename(target, filepath.Join(backup, "extension")); e != nil {
				return result, e
			}
		}
		if e = f.rename(stage, target); e != nil {
			if installed != nil {
				e = errors.Join(e, f.rename(filepath.Join(backup, "extension"), target))
			}
			return result, e
		}
		stage = ""
		published, e := f.stat(target)
		if e != nil {
			return result, e
		}
		undo = append(undo, func() error {
			now, e := f.stat(target)
			if e != nil {
				return e
			}
			if now == nil || !os.SameFile(now, published) {
				return errors.New("concurrent extension preserved")
			}
			for name, b := range files {
				now, e := f.read(filepath.Join(target, name))
				if e != nil || !bytes.Equal(now, b) {
					return errors.New("concurrent extension content preserved")
				}
			}
			rel, _ := f.rel(target)
			dir, e := f.root.Open(rel)
			if e != nil {
				return e
			}
			entries, e := dir.ReadDir(-1)
			dir.Close()
			if e != nil {
				return e
			}
			if len(entries) != len(files) {
				return errors.New("concurrent extension files preserved")
			}
			if e = f.remove(target); e != nil {
				return e
			}
			if installed != nil {
				return f.rename(filepath.Join(backup, "extension"), target)
			}
			return nil
		})
	}
	if e = write(launcher, desktop, oldLauncher); e != nil {
		return result, e
	}
	if e = write(i.receiptPath(), receipt, oldReceipt); e != nil {
		return result, e
	}
	result.Changed = true
	return result, nil
}
