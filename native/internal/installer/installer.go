// Package installer owns local extension files and transactional startup setup.
package installer

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"
)

const ExtensionID = "fmkadmapgofadopljbjfkapdkoienihi"
const Label = "local.claude-desktop-tweaks.environment"
const markerBegin = "-- BEGIN Claude Desktop Tweaks"
const markerEnd = "-- END Claude Desktop Tweaks"

//go:embed payload/*
var embedded embed.FS

type Features struct {
	Font       bool   `json:"font"`
	Theme      bool   `json:"theme"`
	RTL        bool   `json:"rtl"`
	FontFamily string `json:"fontFamily,omitempty"`
	ThemeName  string `json:"themeName,omitempty"`
}

func DefaultFeatures() Features { return Features{Font: true, Theme: true, RTL: true} }

type Receipt struct {
	Features                 Features `json:"features"`
	ExtensionSHA256          string   `json:"extensionSha256"`
	PreviousReactProfile     *string  `json:"previousReactProfile"`
	PreviousReactProfileKind string   `json:"previousReactProfileKind,omitempty"`
	HammerspoonBackup        string   `json:"hammerspoonBackup"`
	LauncherSHA256           string   `json:"launcherSha256,omitempty"`
}
type Result struct {
	Changed bool   `json:"changed"`
	Backup  string `json:"backup,omitempty"`
}
type Runner func(string, ...string) (string, error)
type Installer struct {
	Home              string
	Platform          string
	Run               Runner
	Applications      string
	SystemRoot        string
	ConfigHome        string
	DataHome          string
	windows           windowsSystem
	NotifyEnvironment func() error
}
type ExitError struct{ Code int }

func (e ExitError) Error() string       { return fmt.Sprintf("system command exited with status %d", e.Code) }
func exitCode(err error, code int) bool { var e ExitError; return errors.As(err, &e) && e.Code == code }
func RunSystem(command string, args ...string) (string, error) {
	timeout := 15 * time.Second
	if command == "/usr/bin/curl" || command == "/usr/bin/pkexec" || command == "powershell.exe" {
		timeout = 10 * time.Minute
	}
	if command == "/usr/bin/hdiutil" || command == "/usr/bin/ditto" {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, command, args...)
	if e := configureSystemCommand(cmd); e != nil {
		return "", fmt.Errorf("could not prepare %s", filepath.Base(command))
	}
	var output bytes.Buffer
	cmd.Stdout = &output
	err := cmd.Run()
	if ctx.Err() != nil {
		return "", fmt.Errorf("%s timed out", filepath.Base(command))
	}
	if err != nil {
		var e *exec.ExitError
		if errors.As(err, &e) {
			return "", ExitError{e.ExitCode()}
		}
		return "", fmt.Errorf("could not run %s", filepath.Base(command))
	}
	return output.String(), nil
}
func New() (*Installer, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	return &Installer{Home: home, Platform: runtime.GOOS, Run: RunSystem, Applications: "/Applications", ConfigHome: os.Getenv("XDG_CONFIG_HOME"), DataHome: os.Getenv("XDG_DATA_HOME")}, nil
}
func Payload(f Features) (map[string][]byte, error) {
	if err := f.Validate(); err != nil {
		return nil, err
	}
	files := map[string][]byte{}
	names, err := embedded.ReadDir("payload")
	if err != nil {
		return nil, err
	}
	for _, entry := range names {
		b, err := embedded.ReadFile("payload/" + entry.Name())
		if err != nil {
			return nil, err
		}
		files[entry.Name()] = b
	}
	source := files["content.js"]
	if bytes.Count(source, []byte("__CDT_FEATURES__")) != 1 {
		return nil, errors.New("invalid embedded controller")
	}
	flags, _ := json.Marshal(f)
	files["content.js"] = bytes.Replace(source, []byte("__CDT_FEATURES__"), flags, 1)
	return files, nil
}
func (f Features) Validate() error {
	if f.FontFamily != "" && f.FontFamily != "estedad" && f.FontFamily != "vazirmatn" {
		return errors.New("invalid font selection")
	}
	if f.ThemeName != "" && f.ThemeName != "nord" && f.ThemeName != "gruvbox" {
		return errors.New("invalid theme selection")
	}
	return nil
}
func hash(b []byte) string { s := sha256.Sum256(b); return hex.EncodeToString(s[:]) }
func token() string {
	var b [12]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}
func (i *Installer) target() string {
	if i.Platform == "windows" {
		return filepath.Join(i.windowsProfile(), "extensions", ExtensionID)
	}
	if i.Platform == "linux" {
		return filepath.Join(i.linuxConfig(), "Claude/extensions", ExtensionID)
	}
	return filepath.Join(i.Home, "Library/Application Support/Claude/extensions", ExtensionID)
}
func (i *Installer) stateDir() string {
	if i.Platform == "windows" {
		return filepath.Join(i.windows.LocalAppData, "Claude Desktop Tweaks")
	}
	if i.Platform == "linux" {
		return filepath.Join(i.linuxData(), "Claude Desktop Tweaks")
	}
	return filepath.Join(i.Home, "Library/Application Support/Claude Desktop Tweaks")
}
func (i *Installer) receiptPath() string {
	return filepath.Join(i.stateDir(), "extension-startup.json")
}
func agentXML() []byte {
	return []byte(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>` + Label + `</string>
<key>ProgramArguments</key><array><string>/bin/launchctl</string><string>setenv</string><string>REACT_PROFILE</string><string>1</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
`)
}

type safeFS struct {
	root *os.Root
	home string
}

func (i *Installer) files() (*safeFS, error) {
	if !filepath.IsAbs(i.Home) {
		return nil, errors.New("absolute home directory required")
	}
	s, err := os.Lstat(i.Home)
	if err != nil {
		return nil, err
	}
	if !ownedDir(s, i.Home) {
		return nil, errors.New("home directory is not safe")
	}
	r, err := os.OpenRoot(i.Home)
	return &safeFS{r, i.Home}, err
}
func (f *safeFS) rel(p string) (string, error) {
	r, err := filepath.Rel(f.home, p)
	if err != nil || r == ".." || strings.HasPrefix(r, ".."+string(os.PathSeparator)) || filepath.IsAbs(r) {
		return "", errors.New("installation path is outside home")
	}
	return r, nil
}
func (f *safeFS) stat(p string) (os.FileInfo, error) {
	r, e := f.rel(p)
	if e != nil {
		return nil, e
	}
	s, e := f.root.Lstat(r)
	if os.IsNotExist(e) {
		return nil, nil
	}
	return s, e
}
func (f *safeFS) parents(p string, create bool) error {
	r, err := f.rel(p)
	if err != nil {
		return err
	}
	current := "."
	for _, part := range strings.Split(r, string(os.PathSeparator)) {
		if part == "." || part == "" {
			continue
		}
		current = filepath.Join(current, part)
		s, err := f.root.Lstat(current)
		if os.IsNotExist(err) {
			if !create {
				continue
			}
			if err = f.root.Mkdir(current, 0700); err != nil {
				return err
			}
			s, err = f.root.Lstat(current)
		}
		if err != nil {
			return err
		}
		if !ownedDir(s, filepath.Join(f.home, current)) {
			return fmt.Errorf("installation directory is unowned, writable by others, or symbolic: %s", filepath.ToSlash(current))
		}
	}
	return nil
}
func (f *safeFS) read(p string) ([]byte, error) {
	if err := f.parents(filepath.Dir(p), false); err != nil {
		return nil, err
	}
	s, err := f.stat(p)
	if err != nil || s == nil {
		return nil, err
	}
	if !s.Mode().IsRegular() || !owned(s, p) || s.Size() > 4*1024*1024 {
		return nil, errors.New("invalid installation file")
	}
	r, _ := f.rel(p)
	file, err := f.root.OpenFile(r, os.O_RDONLY|noFollowFlag, 0)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	now, err := file.Stat()
	if err != nil {
		return nil, err
	}
	if !os.SameFile(s, now) {
		return nil, errors.New("installation file changed")
	}
	b, err := io.ReadAll(io.LimitReader(file, 4*1024*1024+1))
	if len(b) > 4*1024*1024 {
		return nil, errors.New("installation file too large")
	}
	return b, err
}
func (f *safeFS) rename(a, b string) error {
	ra, e := f.rel(a)
	if e != nil {
		return e
	}
	rb, e := f.rel(b)
	if e != nil {
		return e
	}
	if e = f.parents(filepath.Dir(a), false); e != nil {
		return e
	}
	if e = f.parents(filepath.Dir(b), false); e != nil {
		return e
	}
	return f.root.Rename(ra, rb)
}
func (f *safeFS) remove(p string) error {
	r, e := f.rel(p)
	if e != nil {
		return e
	}
	return f.root.RemoveAll(r)
}

// createdFile is the I/O boundary for an exclusively created regular file.
// Its descriptor and failed-write cleanup belong to writeCreated.
type createdFile interface {
	Write([]byte) (int, error)
	Sync() error
	Close() error
	Stat() (os.FileInfo, error)
}

func (f *safeFS) exclusive(p string, b []byte) error {
	_, err := f.createExclusive(p, b)
	return err
}
func (f *safeFS) createExclusive(p string, b []byte) (os.FileInfo, error) {
	if err := f.parents(filepath.Dir(p), true); err != nil {
		return nil, err
	}
	r, err := f.rel(p)
	if err != nil {
		return nil, err
	}
	file, err := f.root.OpenFile(r, os.O_WRONLY|os.O_CREATE|os.O_EXCL|noFollowFlag, 0600)
	if err != nil {
		return nil, err
	}
	return f.writeCreated(p, file, b)
}
func (f *safeFS) writeCreated(p string, file createdFile, b []byte) (identity os.FileInfo, retErr error) {
	identity, retErr = file.Stat()
	defer func() {
		retErr = errors.Join(retErr, file.Close())
		if retErr == nil {
			return
		}
		if identity == nil {
			retErr = errors.Join(retErr, errors.New("created file identity is unavailable for cleanup; preserve it for inspection"))
			return
		}
		if err := f.removeCreated(p, identity); err != nil {
			retErr = errors.Join(retErr, fmt.Errorf("created file cleanup failed: %w", err))
		}
	}()
	if retErr != nil {
		identity = nil
		return identity, retErr
	}
	n, err := file.Write(b)
	if err != nil {
		return identity, err
	}
	if n != len(b) {
		return identity, io.ErrShortWrite
	}
	return identity, file.Sync()
}

// Remove only the captured regular file, never recursively remove a replacement.
func (f *safeFS) removeCreated(p string, identity os.FileInfo) error {
	if identity == nil || !identity.Mode().IsRegular() || !owned(identity, p) {
		return errors.New("created file identity cannot be verified")
	}
	if err := f.parents(filepath.Dir(p), false); err != nil {
		return err
	}
	current, err := f.stat(p)
	if err != nil {
		return err
	}
	if current == nil {
		return nil
	}
	if !current.Mode().IsRegular() || !owned(current, p) || !os.SameFile(current, identity) {
		return errors.New("created file was replaced; the replacement was preserved")
	}
	r, err := f.rel(p)
	if err != nil {
		return err
	}
	if err = f.root.Remove(r); os.IsNotExist(err) {
		return nil
	}
	return err
}
func (f *safeFS) write(p string, data, before []byte) error {
	current, err := f.read(p)
	if err != nil {
		return err
	}
	if !bytes.Equal(current, before) || (current == nil) != (before == nil) {
		return errors.New("installation file changed concurrently")
	}
	if bytes.Equal(current, data) {
		return nil
	}
	tmp := p + ".cdt-" + token()
	if err = f.exclusive(tmp, data); err != nil {
		return err
	}
	defer f.remove(tmp)
	current, err = f.read(p)
	if err != nil {
		return err
	}
	if !bytes.Equal(current, before) || (current == nil) != (before == nil) {
		return errors.New("installation file changed concurrently")
	}
	return f.rename(tmp, p)
}
func decodeReceipt(b []byte) (Receipt, error) {
	r := Receipt{Features: DefaultFeatures()}
	if b == nil {
		return r, nil
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		return r, errors.New("invalid preference record")
	}
	if raw == nil {
		return r, errors.New("invalid preference record")
	}
	if flags, ok := raw["features"]; ok {
		var fields map[string]any
		if json.Unmarshal(flags, &fields) != nil || len(fields) < 3 || len(fields) > 5 {
			return r, errors.New("invalid feature selection")
		}
		for k, v := range fields {
			switch k {
			case "font", "theme", "rtl":
			case "fontFamily":
				if name, ok := v.(string); !ok || (name != "estedad" && name != "vazirmatn") {
					return r, errors.New("invalid font selection")
				}
			case "themeName":
				if name, ok := v.(string); !ok || (name != "nord" && name != "gruvbox") {
					return r, errors.New("invalid theme selection")
				}
			default:
				return r, errors.New("invalid feature selection")
			}
		}
		for _, k := range []string{"font", "theme", "rtl"} {
			if _, ok := fields[k].(bool); !ok {
				return r, errors.New("invalid feature selection")
			}
		}
	}
	if err := json.Unmarshal(b, &r); err != nil {
		return r, errors.New("invalid preference record")
	}
	return r, nil
}
func (i *Installer) ReadReceipt() (Receipt, error) {
	f, err := i.files()
	if err != nil {
		return Receipt{}, err
	}
	defer f.root.Close()
	b, err := f.read(i.receiptPath())
	if err != nil {
		return Receipt{}, err
	}
	return decodeReceipt(b)
}
func (i *Installer) closed(name string) error {
	_, err := i.Run("/usr/bin/pgrep", "-x", name)
	if err == nil {
		return fmt.Errorf("Quit %s, then retry. Your work is preserved; this installer never quits apps.", name)
	}
	if !exitCode(err, 1) {
		return errors.New("could not verify that the application is closed")
	}
	return nil
}
func migrateConfig(b []byte) ([]byte, error) {
	if b == nil {
		return nil, nil
	}
	s := string(b)
	a, z := strings.Index(s, markerBegin), strings.Index(s, markerEnd)
	if (a < 0) != (z < 0) || a >= 0 && (z < a || strings.Count(s, markerBegin) != 1 || strings.Count(s, markerEnd) != 1) {
		return nil, errors.New("legacy configuration markers are ambiguous")
	}
	if a < 0 {
		return b, nil
	}
	tail := s[z+len(markerEnd):]
	if strings.HasPrefix(tail, "\r\n") {
		tail = strings.TrimPrefix(tail, "\r\n")
	} else {
		tail = strings.TrimPrefix(tail, "\n")
	}
	return []byte(s[:a] + tail), nil
}

func (i *Installer) Install(features Features) (result Result, retErr error) {
	if i.Platform == "windows" {
		return i.installWindows(features)
	}
	if i.Platform == "linux" {
		return i.installLinux(features)
	}
	if i.Platform != "darwin" {
		return result, errors.New("automatic installation supports macOS only")
	}
	if i.Run == nil {
		return result, errors.New("system runner unavailable")
	}
	if err := i.closed("Claude"); err != nil {
		return result, err
	}
	if i.claudePath() == "" {
		return result, errors.New("Claude Desktop is missing; return to the system check to install it")
	}
	f, err := i.files()
	if err != nil {
		return result, err
	}
	defer f.root.Close()
	target, state := i.target(), i.stateDir()
	agent := filepath.Join(i.Home, "Library/LaunchAgents", Label+".plist")
	config := filepath.Join(i.Home, ".hammerspoon/init.lua")
	for _, p := range []string{target, state, filepath.Dir(agent), filepath.Dir(config)} {
		if err = f.parents(p, false); err != nil {
			return result, err
		}
	}
	original, err := f.read(config)
	if err != nil {
		return result, err
	}
	updated, err := migrateConfig(original)
	if err != nil {
		return result, err
	}
	migrate := !bytes.Equal(original, updated)
	if migrate {
		if err = i.closed("Hammerspoon"); err != nil {
			return result, err
		}
	}
	files, err := Payload(features)
	if err != nil {
		return result, err
	}
	oldReceipt, err := f.read(i.receiptPath())
	if err != nil {
		return result, err
	}
	previous, err := decodeReceipt(oldReceipt)
	if err != nil {
		return result, err
	}
	installed, err := f.stat(target)
	if err != nil {
		return result, err
	}
	matches := func() (bool, error) {
		for name, data := range files {
			b, e := f.read(filepath.Join(target, name))
			if e != nil {
				return false, e
			}
			if !bytes.Equal(b, data) {
				return false, nil
			}
		}
		return true, nil
	}
	same := false
	if installed != nil {
		source, e := f.read(filepath.Join(target, "content.js"))
		if e != nil {
			return result, e
		}
		manifest, e := f.read(filepath.Join(target, "manifest.json"))
		if e != nil {
			return result, e
		}
		var m struct {
			Name string `json:"name"`
		}
		if json.Unmarshal(manifest, &m) != nil || !ownedManifestName(m.Name) || source == nil {
			return result, errors.New("existing extension is not owned by this installer")
		}
		if err = i.guardUpdateVersion(f); err != nil {
			return result, err
		}
		same, err = matches()
		if err != nil {
			return result, err
		}
		if previous.ExtensionSHA256 != hash(source) && !same {
			return result, errors.New("existing extension ownership cannot be verified; preserve it before installing")
		}
	}
	oldAgent, err := f.read(agent)
	if err != nil {
		return result, err
	}
	normalize := func(b []byte) string {
		return regexp.MustCompile(`>\s+<`).ReplaceAllString(strings.TrimSpace(string(b)), "><")
	}
	if oldAgent != nil && normalize(oldAgent) != normalize(agentXML()) {
		return result, errors.New("existing startup agent is not owned by this installer")
	}
	env, envErr := i.Run("/bin/launchctl", "getenv", "REACT_PROFILE")
	if envErr != nil && !exitCode(envErr, 1) {
		return result, errors.New("could not read launch environment")
	}
	var beforeEnv *string
	if envErr == nil {
		v := strings.TrimSuffix(env, "\n")
		beforeEnv = &v
	}
	domain := fmt.Sprintf("gui/%d", os.Getuid())
	_, printErr := i.Run("/bin/launchctl", "print", domain+"/"+Label)
	loaded := printErr == nil
	if printErr != nil {
		var ee ExitError
		if !errors.As(printErr, &ee) {
			return result, errors.New("could not check startup job")
		}
	}
	if loaded && oldAgent == nil {
		return result, errors.New("unowned startup job already registered")
	}
	if err = f.parents(state, true); err != nil {
		return result, err
	}
	lock := filepath.Join(state, ".extension-install.lock")
	lockInfo, err := f.createExclusive(lock, []byte(token()))
	if err != nil {
		if lockInfo == nil && errors.Is(err, os.ErrExist) {
			return result, errors.New("another installation may be running; preserve the installation lock and retry later")
		}
		return result, fmt.Errorf("could not create installation lock: %w", err)
	}
	defer func() {
		if err := f.removeCreated(lock, lockInfo); err != nil {
			if retErr == nil {
				retErr = fmt.Errorf("installation finished but lock cleanup failed: %w", err)
			} else {
				retErr = errors.Join(retErr, fmt.Errorf("installation lock cleanup failed: %w", err))
			}
		}
	}()
	backup := filepath.Join(state, "backups", time.Now().UTC().Format("20060102T150405.000000000")+"-"+token())
	backupCreated := false
	backupDir := func() error {
		if backupCreated {
			return nil
		}
		if e := f.parents(backup, true); e != nil {
			return e
		}
		backupCreated = true
		result.Backup = backup
		return nil
	}
	undo := []func() error{}
	registrationAttempted, envTouched := false, false
	stage := ""
	defer func() {
		if stage != "" {
			_ = f.remove(stage)
		}
		if retErr == nil {
			return
		}
		failures := []string{}
		if registrationAttempted {
			if _, e := i.Run("/bin/launchctl", "print", domain+"/"+Label); e == nil {
				if _, e = i.Run("/bin/launchctl", "bootout", domain+"/"+Label); e != nil {
					failures = append(failures, "startup job")
				}
			}
		}
		if envTouched {
			current, e := i.Run("/bin/launchctl", "getenv", "REACT_PROFILE")
			current = strings.TrimSuffix(current, "\n")
			isBefore := (e != nil && exitCode(e, 1) && beforeEnv == nil) || (e == nil && beforeEnv != nil && current == *beforeEnv)
			if !isBefore {
				if e != nil || current != "1" {
					failures = append(failures, "launch environment")
				} else {
					args := []string{"unsetenv", "REACT_PROFILE"}
					if beforeEnv != nil {
						args = []string{"setenv", "REACT_PROFILE", *beforeEnv}
					}
					if _, e = i.Run("/bin/launchctl", args...); e != nil {
						failures = append(failures, "launch environment")
					}
				}
			}
		}
		for n := len(undo) - 1; n >= 0; n-- {
			if e := undo[n](); e != nil {
				failures = append(failures, "files")
			}
		}
		if len(failures) > 0 {
			retErr = fmt.Errorf("%w Rollback needs attention (%s); preserve installation backups.", retErr, strings.Join(failures, ", "))
		}
	}()
	write := func(p string, data, before []byte) error {
		if bytes.Equal(data, before) {
			return nil
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
				return errors.New("concurrent change preserved")
			}
			if before == nil {
				return f.remove(p)
			}
			return f.write(p, before, data)
		})
		return nil
	}
	if err = i.closed("Claude"); err != nil {
		return result, err
	}
	if migrate {
		if err = i.closed("Hammerspoon"); err != nil {
			return result, err
		}
	}
	if !same {
		if installed != nil {
			if err = i.guardUpdateVersion(f); err != nil {
				return result, err
			}
		}
		if err = f.parents(filepath.Dir(target), true); err != nil {
			return result, err
		}
		stage = target + ".stage-" + token()
		if err = f.parents(stage, true); err != nil {
			return result, err
		}
		for name, data := range files {
			if err = f.exclusive(filepath.Join(stage, name), data); err != nil {
				return result, err
			}
		}
		now, e := f.stat(target)
		if e != nil {
			return result, e
		}
		if (now == nil) != (installed == nil) || now != nil && !os.SameFile(now, installed) {
			return result, errors.New("extension changed concurrently")
		}
		if installed != nil {
			if err = backupDir(); err != nil {
				return result, err
			}
			if err = f.rename(target, filepath.Join(backup, "extension")); err != nil {
				return result, err
			}
		}
		if err = f.rename(stage, target); err != nil {
			if installed != nil {
				_ = f.rename(filepath.Join(backup, "extension"), target)
			}
			return result, err
		}
		stage = ""
		identity, _ := f.stat(target)
		undo = append(undo, func() error {
			now, e := f.stat(target)
			if e != nil || now == nil || !os.SameFile(now, identity) {
				return errors.New("concurrent extension preserved")
			}
			ok, e := matches()
			if e != nil || !ok {
				return errors.New("concurrent extension preserved")
			}
			r, _ := f.rel(target)
			dir, e := f.root.Open(r)
			if e != nil {
				return e
			}
			entries, e := dir.ReadDir(-1)
			dir.Close()
			if e != nil || len(entries) != len(files) {
				return errors.New("concurrent extension preserved")
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
	if oldAgent == nil {
		if err = write(agent, agentXML(), nil); err != nil {
			return result, err
		}
	}
	if !loaded {
		registrationAttempted = true
		envTouched = true
		if _, err = i.Run("/bin/launchctl", "bootstrap", domain, agent); err != nil {
			return result, errors.New("startup registration failed")
		}
	}
	envTouched = true
	if _, err = i.Run("/bin/launchctl", "setenv", "REACT_PROFILE", "1"); err != nil {
		return result, errors.New("startup environment update failed")
	}
	verify, e := i.Run("/bin/launchctl", "getenv", "REACT_PROFILE")
	if e != nil || strings.TrimSpace(verify) != "1" {
		return result, errors.New("launch environment verification failed")
	}
	if _, err = i.Run("/bin/launchctl", "print", domain+"/"+Label); err != nil {
		return result, errors.New("startup verification failed")
	}
	hsBackup := previous.HammerspoonBackup
	if migrate {
		hsBackup = config + ".before-claude-desktop-tweaks-" + token() + ".bak"
		if err = f.exclusive(hsBackup, original); err != nil {
			return result, err
		}
		if err = write(config, updated, original); err != nil {
			return result, err
		}
	}
	record := map[string]any{}
	if oldReceipt != nil {
		if err = json.Unmarshal(oldReceipt, &record); err != nil {
			return result, err
		}
	}
	previousEnv := beforeEnv
	if oldReceipt != nil {
		previousEnv = previous.PreviousReactProfile
	}
	record["installerVersion"] = 2
	record["features"] = features
	record["extensionSha256"] = hash(files["content.js"])
	record["agentLabel"] = Label
	record["agentPath"] = agent
	record["previousReactProfile"] = previousEnv
	record["hammerspoonBackup"] = hsBackup
	if previous.ExtensionSHA256 != hash(files["content.js"]) {
		record["coldStartAfterPermanentSetupVerified"] = false
		delete(record, "normalLaunchAcceptance")
	}
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return result, err
	}
	data = append(data, '\n')
	if oldReceipt != nil && !bytes.Equal(data, oldReceipt) {
		if err = backupDir(); err != nil {
			return result, err
		}
		if err = f.exclusive(filepath.Join(backup, "extension-startup.json"), oldReceipt); err != nil {
			return result, err
		}
	}
	if err = write(i.receiptPath(), data, oldReceipt); err != nil {
		return result, err
	}
	result.Changed = !same || oldAgent == nil || !bytes.Equal(data, oldReceipt) || migrate || !loaded || beforeEnv == nil || *beforeEnv != "1"
	return result, nil
}

// Licenses makes all distribution notices available without installing files.
func Licenses() (string, error) {
	var result strings.Builder
	for _, name := range []string{"LICENSE", "Estedad-OFL.txt", "Nord-LICENSE", "Vazirmatn-OFL.txt", "Gruvbox-NOTICE.md", "Terminal-LICENSES.txt"} {
		b, e := embedded.ReadFile("payload/" + name)
		if e != nil {
			return "", e
		}
		result.WriteString("\n=== " + name + " ===\n")
		result.Write(b)
	}
	return result.String(), nil
}
