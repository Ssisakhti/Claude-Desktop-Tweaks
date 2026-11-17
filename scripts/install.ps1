param([string]$Version = 'latest', [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'

# Download feedback uses one fixed console region. Redirected output stays plain.
function Get-DownloadProgressLines([string]$Phase, [long]$Received, [long]$Total, [double]$Seconds, [int]$Frame = 0) {
    $secondsSafe = [Math]::Max(1, $Seconds)
    $speed = '{0:0} KB/s' -f ($Received / 1024 / $secondsSafe)
    if ($Total -gt 0) {
        $percent = [Math]::Min(100, [Math]::Floor(100.0 * $Received / $Total))
        $filled = [int][Math]::Floor($percent * 24 / 100)
        $bar = '[' + ('#' * $filled) + ('-' * (24 - $filled)) + '] ' + $percent + '%'
        $amount = '{0:0.0} / {1:0.0} MB' -f ($Received / 1048576), ($Total / 1048576)
    } else {
        $spinner = @('|','/','-','\')[$Frame % 4]
        $bar = "$spinner Receiving data..."
        $amount = '{0:0.0} MB' -f ($Received / 1048576)
    }
    if ($Phase -notlike 'Downloading installer*') {
        $bar=@('|','/','-','\')[$Frame % 4]+' Working...';$amount='Please wait...';$speed=''
        if ($Phase -like 'Verifying*') {$bar='Checking SHA-256 integrity.'}
        return @($Phase,$bar,$amount)
    }
    return @($Phase, $bar, "$amount | $speed")
}
function Write-DownloadProgress([string]$Phase, [long]$Received = 0, [long]$Total = 0, [double]$Seconds = 0, [switch]$Force) {
    if ($null -eq $script:DownloadDisplay) {
        $interactive = $false
        try { $interactive = -not [Console]::IsOutputRedirected -and [Console]::WindowWidth -ge 60 } catch {}
        $script:DownloadDisplay = @{Interactive=$interactive; Top=0; Frame=0; LastPhase=''; LastPaint=[datetime]::MinValue}
        if ($interactive) {
            [Console]::WriteLine('  CLAUDE DESKTOP TWEAKS')
            [Console]::WriteLine('  Ctrl+C Cancel')
            [Console]::WriteLine('')
            for ($n=0; $n -lt 3; $n++) { [Console]::WriteLine('') }
            $script:DownloadDisplay.Top = [Math]::Max(0, [Console]::CursorTop - 3)
        }
    }
    $display = $script:DownloadDisplay
    if (-not $display.Interactive) {
        if ($display.LastPhase -ne $Phase) { Write-Host $Phase; $display.LastPhase=$Phase }
        return
    }
    if (-not $Force -and $display.LastPhase -eq $Phase -and ((Get-Date) - $display.LastPaint).TotalMilliseconds -lt 150) { return }
    $display.LastPhase=$Phase; $display.LastPaint=Get-Date
    $lines = @(Get-DownloadProgressLines $Phase $Received $Total $Seconds $display.Frame)
    $display.Frame++
    $oldColor=[Console]::ForegroundColor
    try {
        $width=[Math]::Max(1,[Math]::Min(72,[Console]::WindowWidth-2))
        for ($n=0;$n -lt 3;$n++) {
            [Console]::SetCursorPosition(0,$display.Top+$n)
            $line='  '+$lines[$n]
            if ($line.Length -gt $width) { $line=$line.Substring(0,$width) }
            if (-not $env:NO_COLOR -and $n -eq 0) {
                if ($env:WT_SESSION -or $env:COLORTERM -eq 'truecolor') {
                    [Console]::Write(([char]27)+'[38;2;136;192;208m'+$line.PadRight($width)+([char]27)+'[0m')
                } else { [Console]::ForegroundColor=[ConsoleColor]::Cyan; [Console]::Write($line.PadRight($width)) }
            } else { [Console]::ForegroundColor=$oldColor; [Console]::Write($line.PadRight($width)) }
        }
        [Console]::SetCursorPosition(0,$display.Top+3)
    } catch {
        # Resize or hosts without cursor support fall back to plain phase messages.
        $display.Interactive=$false
        Write-Host $Phase
    } finally { [Console]::ForegroundColor=$oldColor }
}
function Close-DownloadProgress {
    if ($script:DownloadDisplay -and $script:DownloadDisplay.Interactive) {
        try { [Console]::SetCursorPosition(0,$script:DownloadDisplay.Top+3) } catch {}
    }
    $script:DownloadDisplay=$null
}
function Read-ReleaseStream([IO.Stream]$Stream, [long]$Total, [int]$Limit, [string]$Phase, [double]$IdleTimeout=30, [double]$TotalTimeout=180) {
    $memory=[IO.MemoryStream]::new()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $buffer=[byte[]]::new(16384)
        while ($true) {
            if ($watch.Elapsed.TotalSeconds -gt $TotalTimeout) { throw 'Download timed out. Check your connection and run the install command again.' }
            $readStarted=$watch.Elapsed.TotalSeconds
            $cancel=[Threading.CancellationTokenSource]::new()
            try {
                $cancel.CancelAfter([int]($IdleTimeout*1000))
                $task=$Stream.ReadAsync($buffer,0,$buffer.Length,$cancel.Token)
                while (-not $task.Wait(150)) {
                    Write-DownloadProgress $Phase $memory.Length $Total $watch.Elapsed.TotalSeconds
                    if ($watch.Elapsed.TotalSeconds -gt $TotalTimeout -or $watch.Elapsed.TotalSeconds-$readStarted -gt $IdleTimeout) { $cancel.Cancel(); throw 'Download timed out. Check your connection and run the install command again.' }
                }
                $count=$task.GetAwaiter().GetResult()
            } catch {
                if ($cancel.IsCancellationRequested) { throw 'Download stalled or timed out. Check your connection and run the install command again.' }
                throw
            } finally { $cancel.Dispose() }
            if ($count -eq 0) { break }
            if ($memory.Length + $count -gt $Limit) { throw 'Release download is too large.' }
            $memory.Write($buffer,0,$count)
            Write-DownloadProgress $Phase $memory.Length $Total $watch.Elapsed.TotalSeconds
        }
        if ($Total -gt 0 -and $memory.Length -ne $Total) { throw 'Download was incomplete. Run the install command again.' }
        Write-DownloadProgress $Phase $memory.Length $Total $watch.Elapsed.TotalSeconds -Force
        return ,$memory.ToArray()
    } finally { $memory.Dispose(); $watch.Stop() }
}

function Get-ReleaseBytes([string]$Url, [int]$Limit = 67108864, [string]$Phase = 'Downloading installer...') {
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Claude-Desktop-Tweaks/1.0')
    try {
        $uri = [Uri]$Url
        for ($redirect = 0; $redirect -le 8; $redirect++) {
            if ($uri.Scheme -ne 'https' -or $uri.UserInfo) { throw 'Only HTTPS downloads are allowed.' }
            $headerTask=$client.GetAsync($uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            while (-not $headerTask.Wait(150)) { Write-DownloadProgress $Phase }
            $response=$headerTask.GetAwaiter().GetResult()
            try {
                if ([int]$response.StatusCode -in @(301,302,303,307,308)) {
                    $uri = [Uri]::new($uri, $response.Headers.Location)
                    continue
                }
                $response.EnsureSuccessStatusCode() | Out-Null
                if ($response.Content.Headers.ContentLength -gt $Limit) { throw 'Release download is too large.' }
                $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                try {
                    return ,(Read-ReleaseStream $inputStream ([long]$response.Content.Headers.ContentLength) $Limit $Phase)
                } finally { $inputStream.Dispose() }
            } finally { $response.Dispose() }
        }
        throw 'Too many download redirects.'
    } catch {
        throw "Download stopped or failed. Check your connection and run the install command again. $($_.Exception.Message)"
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
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This installer supports Windows 11 x64.' }
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    $architecture = [string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').PROCESSOR_ARCHITECTURE
    if ($build -lt 22000 -or $architecture -ne 'AMD64') { throw 'This installer supports Windows 11 x64.' }
    $repository = 'https://github.com/Ssisakhti/Claude-Desktop-Tweaks'
    if ($Release -eq 'latest') {
        $metadata = [Text.Encoding]::UTF8.GetString((Get-ReleaseBytes 'https://api.github.com/repos/Ssisakhti/Claude-Desktop-Tweaks/releases/latest' 2097152 'Finding the latest release...')) | ConvertFrom-Json
        $Release = $metadata.tag_name
    }
    if ($Release -notmatch '^v[0-9][A-Za-z0-9._-]*$' -or $Release.Contains('..')) { throw 'Invalid release version.' }
    Write-DownloadProgress "Downloading installer | $Release"
    $base = "$repository/releases/download/$Release"
    $binary = Get-ReleaseBytes "$base/claude-tweaks_windows_amd64.exe" 67108864 "Downloading installer | $Release"
    $checksums = [Text.Encoding]::UTF8.GetString((Get-ReleaseBytes "$base/checksums.txt" 65536 'Downloading checksums...'))
    Write-DownloadProgress 'Verifying download...'
    $target = Install-SettingsBinary ([Environment]::GetFolderPath('UserProfile')) ([Environment]::GetFolderPath('LocalApplicationData')) $Release $binary $checksums
    Close-DownloadProgress
    Write-Host 'Download verified.'
    Write-Host "Settings command: & '$($target.Replace("'","''"))'"
    if (-not $SkipLaunch) { & $target; if ($LASTEXITCODE -ne 0) { throw 'Setup did not finish. Review the message above.' } }
}

if ($MyInvocation.InvocationName -ne '.') {
 try { Invoke-ClaudeTweaksInstall $Version ([bool]$NoLaunch) } finally { Close-DownloadProgress }
}
