//go:build !windows

package installer

// Windows orchestration is tested with fake system commands on Unix.
func notifyEnvironmentChange() error { return nil }
