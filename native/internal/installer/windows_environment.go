package installer

import "errors"

func (s windowsSystem) environmentReady() bool {
	return s.EnvironmentValue != nil && *s.EnvironmentValue == "1" && s.EnvironmentKind == "String"
}
func nullablePowerShell(value *string) string {
	if value == nil {
		return "$null"
	}
	return powerShellLiteral(*value)
}

// Change only the named user environment value, preserving raw expanded strings.
func windowsEnvironmentScript(name string, expected *string, expectedKind string, desired *string, desiredKind string, allowAlreadyDesired bool) string {
	already := "$false"
	if allowAlreadyDesired {
		already = "$true"
	}
	return `# CDT_ENVIRONMENT
$ErrorActionPreference='Stop'
$name=` + powerShellLiteral(name) + `
$expectedValue=` + nullablePowerShell(expected) + `
$expectedKind=` + powerShellLiteral(expectedKind) + `
$desiredValue=` + nullablePowerShell(desired) + `
$desiredKind=` + powerShellLiteral(desiredKind) + `
$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
try {
 $currentValue=$null
 $currentKind=''
 if ($key.GetValueNames() -contains $name) {
  $currentKind=$key.GetValueKind($name).ToString()
  if ($currentKind -notin @('String','ExpandString')) {throw 'Unsupported environment value type.'}
  $currentValue=[string]$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
 }
 if (` + already + ` -and $currentValue -ceq $desiredValue -and $currentKind -ceq $desiredKind) {return}
 if ($currentValue -cne $expectedValue -or $currentKind -cne $expectedKind) {throw 'The user environment changed during setup; the new value was preserved.'}
 if ($null -eq $desiredValue) {$key.DeleteValue($name,$false)}
 else {$key.SetValue($name,$desiredValue,([Microsoft.Win32.RegistryValueKind]$desiredKind))}
 $key.Flush()
} finally {$key.Dispose()}
`
}
func (i *Installer) setWindowsEnvironment(before *string, kind string) (func() error, error) {
	one := "1"
	if before != nil && *before == one && kind == "String" {
		return func() error { return nil }, i.notifyWindowsEnvironment()
	}
	undo := func() error {
		if _, e := i.powershell(windowsEnvironmentScript("REACT_PROFILE", &one, "String", before, kind, true)); e != nil {
			return errors.New("could not restore the user launch environment; preserve the receipt and backups")
		}
		return i.notifyWindowsEnvironment()
	}
	if _, e := i.powershell(windowsEnvironmentScript("REACT_PROFILE", before, kind, &one, "String", false)); e != nil {
		return undo, errors.New("could not configure the user launch environment")
	}
	if e := i.notifyWindowsEnvironment(); e != nil {
		return undo, e
	}
	return undo, nil
}

func (i *Installer) notifyWindowsEnvironment() error {
	if i.NotifyEnvironment != nil {
		return i.NotifyEnvironment()
	}
	return notifyEnvironmentChange()
}
