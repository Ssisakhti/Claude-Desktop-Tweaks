package installer

import (
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf16"
)

type windowsPackage struct {
	Family  string `json:"family"`
	Root    string `json:"root"`
	Version string `json:"version"`
}
type windowsSystem struct {
	EnvironmentValue *string         `json:"environmentValue"`
	EnvironmentKind  string          `json:"environmentKind"`
	Build            int             `json:"build"`
	Architecture     string          `json:"architecture"`
	LocalAppData     string          `json:"localAppData"`
	RoamingAppData   string          `json:"roamingAppData"`
	Running          bool            `json:"running"`
	Package          *windowsPackage `json:"package"`
}

const windowsDiscovery = `# CDT_DISCOVERY
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$packages=@(Get-AppxPackage -Name Claude | Where-Object {$_.PackageFamilyName -eq 'Claude_pzs8sxrjxfjjc' -and $_.Architecture.ToString() -eq 'X64'})
if ($packages.Count -gt 1) {throw 'More than one Claude package is registered. Resolve the duplicate installation first.'}
$environment=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
$environmentValue=$null
$environmentKind=''
try {
 if ($null -ne $environment -and $environment.GetValueNames() -contains 'REACT_PROFILE') {
  $environmentKind=$environment.GetValueKind('REACT_PROFILE').ToString()
  if ($environmentKind -notin @('String','ExpandString')) {throw 'Unsupported REACT_PROFILE value type.'}
  $environmentValue=[string]$environment.GetValue('REACT_PROFILE',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
 }
} finally {if ($null -ne $environment) {$environment.Dispose()}}
$package=$null
if ($packages.Count -eq 1) {
 $p=$packages[0]
 if ($p.Status.ToString() -ne 'Ok') {throw 'The official Claude package needs repair before setup.'}
 $signature=Get-AuthenticodeSignature -LiteralPath (Join-Path $p.InstallLocation 'app\claude.exe')
 if ($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Anthropic, PBC*') {throw 'Claude vendor signature verification failed.'}
 $package=@{family=$p.PackageFamilyName;root=$p.InstallLocation;version=$p.Version.ToString()}
}
@{environmentValue=$environmentValue;environmentKind=$environmentKind;build=[int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber;architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();localAppData=[Environment]::GetFolderPath('LocalApplicationData');roamingAppData=[Environment]::GetFolderPath('ApplicationData');running=@(Get-Process -Name Claude -ErrorAction SilentlyContinue).Count -gt 0;package=$package} | ConvertTo-Json -Compress -Depth 4
`

func powerShellLiteral(value string) string { return "'" + strings.ReplaceAll(value, "'", "''") + "'" }
func (i *Installer) powershell(script string) (string, error) {
	if i.Run == nil {
		return "", errors.New("system runner unavailable")
	}
	units := utf16.Encode([]rune(script))
	b := make([]byte, len(units)*2)
	for n, u := range units {
		binary.LittleEndian.PutUint16(b[n*2:], u)
	}
	return i.Run("powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", base64.StdEncoding.EncodeToString(b))
}
func (i *Installer) discoverWindows() error {
	out, e := i.powershell(windowsDiscovery)
	if e != nil {
		return errors.New("could not verify Windows or the official Claude package; check your PowerShell access and Claude installation")
	}
	var system windowsSystem
	if json.Unmarshal([]byte(strings.TrimSpace(strings.TrimPrefix(out, "\ufeff"))), &system) != nil {
		return errors.New("invalid Windows setup information")
	}
	if system.Build < 22000 || system.Architecture != "X64" {
		return errors.New("Windows 11 x64 is required")
	}
	if os.Getenv("CLAUDE_USER_DATA_DIR") != "" {
		return errors.New("custom CLAUDE_USER_DATA_DIR profiles are not supported")
	}
	if system.Package != nil && system.Package.Family != "Claude_pzs8sxrjxfjjc" {
		return errors.New("this Claude package is not supported")
	}
	for _, p := range []string{system.LocalAppData, system.RoamingAppData} {
		rel, e := filepath.Rel(i.Home, p)
		if !filepath.IsAbs(p) || e != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
			return errors.New("Windows application-data directories must be inside your user profile")
		}
	}
	i.windows = system
	return nil
}
func (i *Installer) windowsProfile() string {
	return filepath.Join(i.windows.LocalAppData, "Claude-Data", "claude_pzs8sxrjxfjjc")
}
func (i *Installer) windowsRunning() (bool, error) {
	if e := i.discoverWindows(); e != nil {
		return false, e
	}
	return i.windows.Running, nil
}
func (i *Installer) checkWindows() (Status, error) {
	s := Status{Platform: "windows", Features: DefaultFeatures()}
	if e := i.discoverWindows(); e != nil {
		return s, e
	}
	s.ClaudeInstalled = i.windows.Package != nil
	s.ClaudeRunning = i.windows.Running
	if s.ClaudeInstalled {
		if e := linuxHook(filepath.Join(i.windows.Package.Root, "app/resources/app.asar")); e != nil {
			return s, e
		}
		if info, e := os.Stat(i.windowsProfile()); e != nil || !info.IsDir() {
			return s, errors.New("open Claude once, then quit it and retry; setup requires the standard MSIX user profile")
		}
	}
	f, e := i.files()
	if e != nil {
		return s, e
	}
	defer f.root.Close()
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
		content, e := f.read(filepath.Join(i.target(), "content.js"))
		if e != nil {
			return s, e
		}
		s.ExtensionInstalled = content != nil && hash(content) == r.ExtensionSHA256 && i.windows.environmentReady()
	}
	return s, nil
}
func (i *Installer) installWindows(features Features) (Result, error) {
	s, e := i.checkWindows()
	if e != nil {
		return Result{}, e
	}
	if !s.ClaudeInstalled {
		return Result{}, errors.New("Claude Desktop is missing; install the official Windows app first")
	}
	if s.ClaudeRunning {
		return Result{}, errors.New("Quit Claude, then retry. This installer never quits apps")
	}
	files, e := Payload(features)
	if e != nil {
		return Result{}, e
	}
	return i.installUserExtension(features, files, nil, "", i.windowsRunning)
}

const windowsPrerequisite = `$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
try {
 [IO.Directory]::CreateDirectory($directory) | Out-Null
 $setup=Join-Path $directory 'ClaudeSetup.exe'
 Invoke-WebRequest -UseBasicParsing -Uri 'https://claude.ai/api/desktop/win32/x64/setup/latest/redirect' -OutFile $setup
 $signature=Get-AuthenticodeSignature -LiteralPath $setup
 if ($signature.Status.ToString() -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Anthropic, PBC*') {throw 'Official Claude Setup signature verification failed.'}
 $process=Start-Process -FilePath $setup -Wait -PassThru
 if ($process.ExitCode -ne 0) {throw 'Claude Setup did not finish successfully.'}
} finally {if (Test-Path -LiteralPath $directory) {Remove-Item -LiteralPath $directory -Recurse -Force}}
`

func (i *Installer) installWindowsClaude() error {
	if e := i.discoverWindows(); e != nil {
		return e
	}
	if i.windows.Package != nil {
		return nil
	}
	if i.windows.Running {
		return errors.New("quit Claude before installing the official package")
	}
	if _, e := i.powershell(windowsPrerequisite); e != nil {
		return errors.New("official Claude Setup did not finish; use claude.com/download if the download or system permission prompt is blocked, then reopen settings")
	}
	if e := i.discoverWindows(); e != nil {
		return e
	}
	if i.windows.Package == nil {
		return errors.New("the official Claude MSIX package was not registered; finish Claude Setup and retry")
	}
	return nil
}
