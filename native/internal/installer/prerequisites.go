package installer

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

type Status struct {
	Platform           string   `json:"platform"`
	ClaudeInstalled    bool     `json:"claudeInstalled"`
	ClaudeRunning      bool     `json:"claudeRunning"`
	ExtensionInstalled bool     `json:"extensionInstalled"`
	Features           Features `json:"features"`
}

func (i *Installer) claudePath() string {
	apps := i.Applications
	if apps == "" {
		apps = "/Applications"
	}
	for _, p := range []string{filepath.Join(apps, "Claude.app"), filepath.Join(i.Home, "Applications/Claude.app")} {
		if s, e := os.Stat(filepath.Join(p, "Contents/MacOS/Claude")); e == nil && s.Mode().IsRegular() {
			return p
		}
	}
	return ""
}
func (i *Installer) Check() (Status, error) {
	if i.Platform == "linux" {
		return i.checkLinux()
	}
	s := Status{Platform: i.Platform, Features: DefaultFeatures()}
	if i.Platform != "darwin" {
		return s, errors.New("this installer currently supports macOS only")
	}
	s.ClaudeInstalled = i.claudePath() != ""
	_, err := i.Run("/usr/bin/pgrep", "-x", "Claude")
	s.ClaudeRunning = err == nil
	if err != nil && !exitCode(err, 1) {
		return s, errors.New("could not check whether Claude is running")
	}
	f, err := i.files()
	if err != nil {
		return s, err
	}
	defer f.root.Close()
	b, err := f.read(i.receiptPath())
	if err != nil {
		return s, err
	}
	record, err := decodeReceipt(b)
	if err != nil {
		return s, err
	}
	s.Features = record.Features
	if b != nil {
		source, e := f.read(filepath.Join(i.target(), "content.js"))
		if e != nil {
			return s, e
		}
		s.ExtensionInstalled = source != nil && hash(source) == record.ExtensionSHA256
	}
	return s, nil
}

// InstallClaude requires a separate affirmative consent step in the interface.
func (i *Installer) InstallClaude(confirmed bool) (retErr error) {
	if !confirmed {
		return errors.New("explicit confirmation is required before downloading Claude")
	}
	if i.Platform == "linux" {
		return i.installLinuxClaude()
	}
	if i.Platform != "darwin" {
		return errors.New("this installer currently supports macOS only")
	}
	if i.claudePath() != "" {
		return nil
	}
	f, err := i.files()
	if err != nil {
		return err
	}
	defer f.root.Close()
	dir, err := os.MkdirTemp("", "claude-tweaks-download-")
	if err != nil {
		return err
	}
	mount, dmg := filepath.Join(dir, "mount"), filepath.Join(dir, "Claude.dmg")
	mounted := false
	stage := ""
	defer func() {
		if mounted {
			if _, e := i.Run("/usr/bin/hdiutil", "detach", mount); e != nil {
				retErr = errors.New("the download disk is still mounted; eject the Claude disk in Finder before retrying")
				return
			}
		}
		if stage != "" {
			_ = f.remove(stage)
		}
		_ = os.RemoveAll(dir)
	}()
	command := func(c string, args ...string) error {
		_, e := i.Run(c, args...)
		if e != nil {
			return fmt.Errorf("%s failed; your existing apps were preserved", filepath.Base(c))
		}
		return nil
	}
	if err = command("/usr/bin/curl", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2", "--max-time", "600", "--output", dmg, "https://claude.ai/api/desktop/darwin/universal/dmg/latest/redirect"); err != nil {
		return err
	}
	if err = os.Mkdir(mount, 0700); err != nil {
		return err
	}
	if err = command("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg); err != nil {
		return err
	}
	mounted = true
	source := filepath.Join(mount, "Claude.app")
	requirement := `=identifier "com.anthropic.claudefordesktop" and anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW"`
	if err = command("/usr/bin/codesign", "--verify", "--deep", "--strict", "-R", requirement, source); err != nil {
		return err
	}
	if err = command("/usr/sbin/spctl", "--assess", "--type", "execute", source); err != nil {
		return err
	}
	parent := filepath.Join(i.Home, "Applications")
	if err = f.parents(parent, true); err != nil {
		return err
	}
	target := filepath.Join(parent, "Claude.app")
	if s, e := f.stat(target); e != nil {
		return e
	} else if s != nil {
		return errors.New("an existing Claude app was preserved; choose its location manually")
	}
	stage = filepath.Join(parent, ".claude-tweaks-"+token())
	if err = f.parents(stage, true); err != nil {
		return err
	}
	if err = command("/usr/bin/ditto", source, filepath.Join(stage, "Claude.app")); err != nil {
		return err
	}
	if err = command("/usr/bin/codesign", "--verify", "--deep", "--strict", "-R", requirement, filepath.Join(stage, "Claude.app")); err != nil {
		return err
	}
	if s, e := f.stat(target); e != nil {
		return e
	} else if s != nil {
		return errors.New("Claude appeared during installation; the existing app was preserved")
	}
	if err = f.rename(filepath.Join(stage, "Claude.app"), target); err != nil {
		return err
	}
	return nil
}
