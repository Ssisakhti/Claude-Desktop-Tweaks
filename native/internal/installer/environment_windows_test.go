package installer

import (
	"fmt"
	"os"
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
