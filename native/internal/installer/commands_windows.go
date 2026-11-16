package installer

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows"
)

// Windows PowerShell must not load incompatible modules inherited from pwsh 7.
func configureSystemCommand(cmd *exec.Cmd) error {
	if !strings.EqualFold(filepath.Base(cmd.Path), "powershell.exe") {
		return nil
	}
	system, e := windows.GetSystemDirectory()
	if e != nil {
		return e
	}
	directory := filepath.Join(system, "WindowsPowerShell", "v1.0")
	cmd.Path = filepath.Join(directory, "powershell.exe")
	cmd.Args[0] = cmd.Path
	cmd.Err = nil
	env := []string{}
	for _, entry := range os.Environ() {
		name := strings.SplitN(entry, "=", 2)[0]
		if !strings.EqualFold(name, "PSModulePath") && !strings.EqualFold(name, "PSModuleAnalysisCachePath") {
			env = append(env, entry)
		}
	}
	cmd.Env = append(env, "PSModulePath="+filepath.Join(directory, "Modules"))
	return nil
}
