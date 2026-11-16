$ErrorActionPreference='Stop'
# Model Windows PowerShell resolving a RuntimeInformation type without the property.
$legacyType=Add-Type -PassThru -TypeDefinition 'namespace CdtFixture { public static class LegacyRuntimeInformation { public static object OSArchitecture { get { return null; } } } }'
$aliases=[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
$aliases::Add('Runtime.InteropServices.RuntimeInformation',$legacyType)
$installerPath=Join-Path $PSScriptRoot '../scripts/install.ps1'
& ([scriptblock]::Create(@'
if ($null -ne [Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {throw 'The missing-property fixture was not loaded.'}
. $installerPath
$script:ReachedInstall=$false
function Get-ReleaseBytes { param([string]$Url,[int]$Limit) return ,[byte[]]@(0) }
function Install-SettingsBinary { param($ProfileRoot,$DataHome,$Release,$Binary,$Checksums) $script:ReachedInstall=$true; return 'verified-fixture.exe' }
function Get-ItemProperty {
 param([string]$Path)
 if ($Path -like '*CurrentVersion') {return [pscustomobject]@{CurrentBuildNumber='26100'}}
 if ($Path -like '*Session Manager*Environment') {return [pscustomobject]@{PROCESSOR_ARCHITECTURE='AMD64'}}
 throw 'Unexpected registry query in the platform fixture.'
}
Invoke-ClaudeTweaksInstall 'v1.3.0' $true
if (-not $script:ReachedInstall) {throw 'Supported x64 Windows was rejected.'}
foreach ($architecture in @('ARM64','x86','')) {
 $script:TestArchitecture=$architecture
 function Get-ItemProperty {
  param([string]$Path)
  if ($Path -like '*CurrentVersion') {return [pscustomobject]@{CurrentBuildNumber='26100'}}
  return [pscustomobject]@{PROCESSOR_ARCHITECTURE=$script:TestArchitecture}
 }
 $script:ReachedInstall=$false
 $rejected=$false
 try {Invoke-ClaudeTweaksInstall 'v1.3.0' $true} catch {
  if ($_.Exception.Message -ne 'This installer supports Windows 11 x64.') {throw}
  $rejected=$true
 }
 if (-not $rejected -or $script:ReachedInstall) {throw 'Unsupported architecture reached installation.'}
}
Write-Host 'PowerShell platform checks passed without RuntimeInformation.OSArchitecture.'

'@))
