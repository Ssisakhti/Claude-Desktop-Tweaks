param([string]$Version = 'latest', [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'

function Get-ReleaseBytes([string]$Url, [int]$Limit = 67108864) {
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(180)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Claude-Desktop-Tweaks/1.0')
    try {
        $uri = [Uri]$Url
        for ($redirect = 0; $redirect -le 8; $redirect++) {
            if ($uri.Scheme -ne 'https' -or $uri.UserInfo) { throw 'Only HTTPS downloads are allowed.' }
            $response = $client.GetAsync($uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try {
                if ([int]$response.StatusCode -in @(301,302,303,307,308)) {
                    $uri = [Uri]::new($uri, $response.Headers.Location)
                    continue
                }
                $response.EnsureSuccessStatusCode() | Out-Null
                if ($response.Content.Headers.ContentLength -gt $Limit) { throw 'Release download is too large.' }
                $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $memory = [IO.MemoryStream]::new()
                try {
                    $buffer = [byte[]]::new(16384)
                    while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        if ($memory.Length + $count -gt $Limit) { throw 'Release download is too large.' }
                        $memory.Write($buffer, 0, $count)
                    }
                    return ,$memory.ToArray()
                } finally { $inputStream.Dispose(); $memory.Dispose() }
            } finally { $response.Dispose() }
        }
        throw 'Too many download redirects.'
    } finally { $client.Dispose(); $handler.Dispose() }
}

function Assert-PrivatePath([string]$Path, [bool]$Directory) {
    $item = Get-Item -LiteralPath $Path -Force
    if ([bool]$item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'A symbolic or unexpected installation path was preserved.' }
    $acl = Get-Acl -LiteralPath $Path
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trusted = @($userSid, 'S-1-5-18', 'S-1-5-32-544')
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw 'An installation path has a different owner.' }
    $writeRights = [int]([Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership)
    foreach ($rule in $acl.Access) {
        if ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if ($rule.AccessControlType -eq 'Allow' -and ([int]$rule.FileSystemRights -band $writeRights) -and $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw 'An installation path is writable by another account.' }
    }
}

function Install-SettingsBinary([string]$ProfileRoot, [string]$DataHome, [string]$Release, [byte[]]$Binary, [string]$Checksums) {
    if ($Release -notmatch '^v[0-9][A-Za-z0-9._-]*$' -or $Release.Contains('..')) { throw 'Invalid release version.' }
    $entries = @($Checksums -split '\r?\n' | Where-Object { $_ -match '^([a-f0-9]{64})\s+claude-tweaks_windows_amd64\.exe$' })
    if ($entries.Count -ne 1) { throw 'The Windows checksum is missing or ambiguous.' }
    $expected = ($entries[0] -split '\s+')[0]
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($sha.ComputeHash($Binary)).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($actual -ne $expected) { throw 'Checksum verification failed. No files were installed.' }
    $root = [IO.Path]::GetFullPath($ProfileRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $destination = [IO.Path]::GetFullPath((Join-Path $DataHome "Claude Desktop Tweaks\releases\$Release\x64"))
    if (-not $destination.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'The installation directory must be inside your user profile.' }
    Assert-PrivatePath $root $true
    $current = $root
    foreach ($part in $destination.Substring($root.Length + 1).Split([IO.Path]::DirectorySeparatorChar)) {
        $current = Join-Path $current $part
        if (-not (Test-Path -LiteralPath $current)) { [IO.Directory]::CreateDirectory($current) | Out-Null }
        Assert-PrivatePath $current $true
    }
    $target = Join-Path $destination 'claude-tweaks.exe'
    if (Test-Path -LiteralPath $target) {
        Assert-PrivatePath $target $false
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'An existing executable differs and was preserved.' }
    } else {
        $stage = Join-Path $destination ('.download-' + [guid]::NewGuid().ToString('N'))
        try {
            $stream = [IO.File]::Open($stage, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $stream.Write($Binary,0,$Binary.Length); $stream.Flush($true) } finally { $stream.Dispose() }
            [IO.File]::Move($stage,$target)
        } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force } }
    }
    return $target
}

function Invoke-ClaudeTweaksInstall([string]$Release, [bool]$SkipLaunch) {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber -lt 22000 -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') { throw 'This installer supports Windows 11 x64.' }
    $repository = 'https://github.com/Ssisakhti/Claude-Desktop-Tweaks'
    if ($Release -eq 'latest') {
        $metadata = [Text.Encoding]::UTF8.GetString((Get-ReleaseBytes 'https://api.github.com/repos/Ssisakhti/Claude-Desktop-Tweaks/releases/latest' 2097152)) | ConvertFrom-Json
        $Release = $metadata.tag_name
    }
    if ($Release -notmatch '^v[0-9][A-Za-z0-9._-]*$' -or $Release.Contains('..')) { throw 'Invalid release version.' }
    Write-Host "Downloading Claude Desktop Tweaks $Release for Windows x64..."
    $base = "$repository/releases/download/$Release"
    $binary = Get-ReleaseBytes "$base/claude-tweaks_windows_amd64.exe"
    $checksums = [Text.Encoding]::UTF8.GetString((Get-ReleaseBytes "$base/checksums.txt" 65536))
    $target = Install-SettingsBinary ([Environment]::GetFolderPath('UserProfile')) ([Environment]::GetFolderPath('LocalApplicationData')) $Release $binary $checksums
    Write-Host 'Download verified. No Node.js or Go installation is needed.'
    Write-Host "Settings command: & '$($target.Replace("'","''"))'"
    if (-not $SkipLaunch) { & $target; if ($LASTEXITCODE -ne 0) { throw 'Setup did not finish. Review the message above.' } }
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-ClaudeTweaksInstall $Version ([bool]$NoLaunch) }
