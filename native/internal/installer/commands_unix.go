//go:build !windows

package installer

import "os/exec"

func configureSystemCommand(_ *exec.Cmd) error { return nil }
