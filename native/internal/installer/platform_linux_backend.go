package installer

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
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
	config := i.linuxConfig()
	if strings.ContainsAny(config, "\x00\n\r") {
		return nil, errors.New("the configuration directory cannot contain line breaks or NUL characters")
	}
	// Desktop entries decode string escapes before parsing Exec arguments.
	argument := "XDG_CONFIG_HOME=" + config
	argument = strings.NewReplacer("\\", "\\\\", "\"", "\\\"", "`", "\\`", "$", "\\$", "%", "%%").Replace(argument)
	argument = `"` + strings.ReplaceAll(argument, "\\", "\\\\") + `"`
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
		if strings.HasPrefix(line, "DBusActivatable=") {
			lines[n] = "DBusActivatable=false"
		}
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
		lines[n] = "Exec=/usr/bin/env REACT_PROFILE=1 " + argument + " /usr/bin/claude-desktop" + tail
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
	return i.installUserExtension(features, files, desktop, i.linuxLauncher(), i.linuxRunning)
}
