package installer

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestWindowsUserEnvironmentPreservesRawValueAndType(t *testing.T) {
	i, e := New()
	if e != nil {
		t.Fatal(e)
	}
	name := fmt.Sprintf("CDT_TEST_%d", os.Getpid())
	raw := "%USERPROFILE%\\sample"
	cleanup := func() {
		_, _ = i.powershell(`$k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment');try{$k.DeleteValue(` + powerShellLiteral(name) + `,$false)}finally{$k.Dispose()}`)
	}
	cleanup()
	t.Cleanup(cleanup)
	if _, e = i.powershell(windowsEnvironmentScript(name, nil, "", &raw, "ExpandString", false)); e != nil {
		t.Fatal(e)
	}
	one := "1"
	if _, e = i.powershell(windowsEnvironmentScript(name, &raw, "ExpandString", &one, "String", false)); e != nil {
		t.Fatal(e)
	}
	if _, e = i.powershell(windowsEnvironmentScript(name, &one, "String", &raw, "ExpandString", true)); e != nil {
		t.Fatal(e)
	}
	if _, e = i.powershell(windowsEnvironmentScript(name, &raw, "ExpandString", nil, "", false)); e != nil {
		t.Fatal(e)
	}
}
func TestWindowsUserEnvironmentPreservesConcurrentChange(t *testing.T) {
	i, e := New()
	if e != nil {
		t.Fatal(e)
	}
	name := fmt.Sprintf("CDT_CONFLICT_%d", os.Getpid())
	foreign := "foreign"
	one := "1"
	if _, e = i.powershell(windowsEnvironmentScript(name, nil, "", &foreign, "String", false)); e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { _, _ = i.powershell(windowsEnvironmentScript(name, &foreign, "String", nil, "", false)) })
	if _, e = i.powershell(windowsEnvironmentScript(name, nil, "", &one, "String", false)); e == nil {
		t.Fatal("concurrent setting overwritten")
	}
	if _, e = i.powershell(windowsEnvironmentScript(name, &foreign, "String", nil, "", false)); e != nil {
		t.Fatal("foreign value was not preserved")
	}
}

func TestWindowsRejectsWritableInstallationHome(t *testing.T) {
	i := windowsFixture(t)
	script := `$ErrorActionPreference='Stop';$path=` + powerShellLiteral(i.Home) + `;$acl=Get-Acl -LiteralPath $path;$rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),'Modify','ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule);Set-Acl -LiteralPath $path -AclObject $acl`
	system, e := New()
	if e != nil {
		t.Fatal(e)
	}
	system.Run = func(command string, args ...string) (string, error) {
		cmd := exec.Command(command, args...)
		if e := configureSystemCommand(cmd); e != nil {
			return "", e
		}
		out, e := cmd.Output()
		if failure, ok := e.(*exec.ExitError); ok {
			out = append(out, failure.Stderr...)
		}
		return string(out), e
	}
	if out, e := system.powershell("try {" + script + "} catch {Write-Output $_.Exception.Message;exit 1}"); e != nil {
		t.Fatalf("permission fixture: %v: %s", e, out)
	}
	if _, e = i.Check(); e == nil {
		t.Fatal("a home writable by another account was accepted")
	}
}

func TestWindowsOnlyValidatesInitializedProfileCandidatePermissions(t *testing.T) {
	for _, initialized := range []bool{false, true} {
		t.Run(fmt.Sprint(initialized), func(t *testing.T) {
			i, system := windowsFixtureSystem(t)
			parent := filepath.Join(system.LocalAppData, "Packages")
			if e := os.MkdirAll(parent, 0700); e != nil {
				t.Fatal(e)
			}
			if initialized {
				profile := filepath.Join(parent, "Claude_pzs8sxrjxfjjc", "LocalCache", "Roaming", "Claude")
				if e := os.MkdirAll(profile, 0700); e != nil {
					t.Fatal(e)
				}
				if e := os.WriteFile(filepath.Join(profile, "Local State"), []byte("{}"), 0600); e != nil {
					t.Fatal(e)
				}
				if e := os.Remove(filepath.Join(system.LocalAppData, "Claude-Data", "claude_pzs8sxrjxfjjc", "Local State")); e != nil {
					t.Fatal(e)
				}
			}
			// Grant an unrelated Windows group write access in a temporary tree.
			// An unused tree must be ignored; a selected one must remain unsafe.
			cmd := exec.Command("icacls.exe", parent, "/grant", "*S-1-5-32-545:(OI)(CI)M")
			if out, e := cmd.CombinedOutput(); e != nil {
				t.Fatalf("ACL fixture: %v: %s", e, out)
			}
			_, e := i.Install(DefaultFeatures())
			if initialized && e == nil {
				t.Fatal("writable selected profile was accepted")
			}
			if !initialized && e != nil {
				t.Fatal("unused candidate blocked installation", e)
			}
		})
	}
}
func TestWindowsRejectsJunctionParent(t *testing.T) {
	i := windowsFixture(t)
	if _, e := i.Check(); e != nil {
		t.Fatal(e)
	}
	parent := filepath.Join(i.windows.LocalAppData, "Claude-Data")
	if e := os.RemoveAll(parent); e != nil {
		t.Fatal(e)
	}
	outside := t.TempDir()
	command := exec.Command("cmd.exe", "/c", "mklink", "/J", parent, outside)
	if out, e := command.CombinedOutput(); e != nil {
		t.Fatalf("junction fixture: %v %s", e, out)
	}
	t.Cleanup(func() { _ = os.Remove(parent) })
	f, e := i.files()
	if e != nil {
		t.Fatal(e)
	}
	defer f.root.Close()
	if e = f.parents(filepath.Join(parent, "new directory"), true); e == nil {
		t.Fatal("junction installation parent accepted")
	}
	entries, e := os.ReadDir(outside)
	if e != nil || len(entries) != 0 {
		t.Fatal("external directory changed")
	}
}

func TestWindowsDiscoveryWithoutRuntimeArchitecture(t *testing.T) {
	i, e := New()
	if e != nil {
		t.Fatal(e)
	}
	i.Run = func(command string, args ...string) (string, error) {
		cmd := exec.Command(command, args...)
		if e := configureSystemCommand(cmd); e != nil {
			return "", e
		}
		out, e := cmd.Output()
		if failure, ok := e.(*exec.ExitError); ok {
			out = append(out, failure.Stderr...)
		}
		return string(out), e
	}
	prefix := `$legacy=Add-Type -PassThru -TypeDefinition 'namespace CdtFixture { public static class LegacyRuntimeInformation { public static object OSArchitecture { get { return null; } } } }';$aliases=[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators');$aliases::Add('Runtime.InteropServices.RuntimeInformation',$legacy);`
	body := `if ($null -ne [Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {throw 'Missing-property fixture was not loaded.'};` + windowsDiscovery
	out, e := i.powershell(prefix + "& ([scriptblock]::Create(" + powerShellLiteral(body) + "))")
	if e != nil {
		t.Fatalf("discovery relied on RuntimeInformation.OSArchitecture: %v %s", e, out)
	}
	var status windowsSystem
	if e = json.Unmarshal([]byte(strings.TrimSpace(out)), &status); e != nil {
		t.Fatal(e)
	}
	if status.Architecture != "X64" || status.Build < 22000 {
		t.Fatalf("unexpected native Windows discovery: %+v", status)
	}
}
