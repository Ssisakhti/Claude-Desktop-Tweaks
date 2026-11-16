$ErrorActionPreference='Stop'
. "$PSScriptRoot/../scripts/install.ps1"
$homeDirectory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('cdt-bootstrap-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($homeDirectory) | Out-Null
try {
 $data=Join-Path $homeDirectory 'data with spaces'
 $bytes=[Text.Encoding]::UTF8.GetBytes('standalone fixture')
 $sha=[Security.Cryptography.SHA256]::Create()
 try {$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
 $checksums="$hash  claude-tweaks_windows_amd64.exe`n"
 $target=Install-SettingsBinary $homeDirectory $data 'v1.3.0' $bytes $checksums
 if (-not (Test-Path -LiteralPath $target)) {throw 'Verified executable not installed.'}
 $repeat=Install-SettingsBinary $homeDirectory $data 'v1.3.0' $bytes $checksums
 if ($repeat -ne $target) {throw 'Repeat installation changed the target.'}
 $rejected=$false
 try {Install-SettingsBinary $homeDirectory $data 'v1.3.1' $bytes (('0'*64)+'  claude-tweaks_windows_amd64.exe') | Out-Null} catch {$rejected=$true}
 if (-not $rejected -or (Test-Path (Join-Path $data 'Claude Desktop Tweaks/releases/v1.3.1'))) {throw 'Bad checksum installed files.'}
 [IO.File]::WriteAllText($target,'foreign')
 $rejected=$false
 try {Install-SettingsBinary $homeDirectory $data 'v1.3.0' $bytes $checksums | Out-Null} catch {$rejected=$true}
 if (-not $rejected -or [IO.File]::ReadAllText($target) -ne 'foreign') {throw 'Foreign executable was overwritten.'}
 $rejected=$false
 try {Install-SettingsBinary $homeDirectory $data '../escape' $bytes $checksums | Out-Null} catch {$rejected=$true}
 if (-not $rejected) {throw 'Unsafe release version accepted.'}
 Write-Host 'Windows bootstrap checks passed.'
} finally {Remove-Item -LiteralPath $homeDirectory -Recurse -Force}
