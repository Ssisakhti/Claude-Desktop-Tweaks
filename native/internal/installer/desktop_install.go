package installer

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// Shared transaction for user-owned extension, launcher, and receipt files.
func (i *Installer) installUserExtension(features Features, files map[string][]byte, desktop []byte, launcher string, isRunning func() (bool, error)) (result Result, retErr error) {
	f, e := i.files()
	if e != nil {
		return result, e
	}
	defer f.root.Close()
	target, state := i.target(), i.stateDir()
	oldReceipt, e := f.read(i.receiptPath())
	if e != nil {
		return result, e
	}
	previous, e := decodeReceipt(oldReceipt)
	if e != nil {
		return result, e
	}
	var oldLauncher []byte
	if launcher != "" {
		oldLauncher, e = f.read(launcher)
	}
	if e != nil {
		return result, e
	}
	if oldLauncher != nil && (previous.LauncherSHA256 == "" || hash(oldLauncher) != previous.LauncherSHA256) {
		return result, errors.New("an existing Claude launcher is not owned by this installer; it was preserved")
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
	if i.Platform == "windows" {
		record.LauncherSHA256 = ""
		record.PreviousReactProfile = i.windows.EnvironmentValue
		record.PreviousReactProfileKind = i.windows.EnvironmentKind
		if oldReceipt != nil {
			record.PreviousReactProfile = previous.PreviousReactProfile
			record.PreviousReactProfileKind = previous.PreviousReactProfileKind
		}
	}
	receipt, e := json.MarshalIndent(record, "", "  ")
	if e != nil {
		return result, e
	}
	receipt = append(receipt, '\n')
	if same && bytes.Equal(oldLauncher, desktop) && bytes.Equal(oldReceipt, receipt) && (i.Platform != "windows" || i.windows.environmentReady()) {
		return result, nil
	}
	if e = f.parents(state, true); e != nil {
		return result, e
	}
	lock := filepath.Join(state, ".extension-install.lock")
	beforeEnvironment, beforeKind := i.windows.EnvironmentValue, i.windows.EnvironmentKind
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
	running, e := isRunning()
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
	if launcher != "" {
		if e = write(launcher, desktop, oldLauncher); e != nil {
			return result, e
		}
	}
	if i.Platform == "windows" {
		restore, err := i.setWindowsEnvironment(beforeEnvironment, beforeKind)
		undo = append(undo, restore)
		if err != nil {
			return result, err
		}
	}
	if e = write(i.receiptPath(), receipt, oldReceipt); e != nil {
		return result, e
	}
	result.Changed = true
	return result, nil
}
