$ErrorActionPreference='Stop'
. "$PSScriptRoot/../scripts/install.ps1"
$known=@(Get-DownloadProgressLines 'Downloading installer' 1048576 2097152 2)
if ($known[1] -notmatch '50%' -or $known[2] -notmatch '1.0 / 2.0 MB' -or $known[2] -notmatch '512 KB/s') {throw 'Known-length progress is wrong.'}
$unknown=@(Get-DownloadProgressLines 'Downloading installer' 1048576 0 2)
if (($unknown -join '') -match '%' -or $unknown[2] -notmatch '1.0 MB') {throw 'Unknown-length progress fabricates a percent.'}
$bytes=[byte[]]@(1,2,3,4)
foreach($total in @(0,4)) {
 $stream=[IO.MemoryStream]::new($bytes)
 try {$actual=Read-ReleaseStream $stream $total 16 'Test transfer';if ([BitConverter]::ToString($actual) -ne '01-02-03-04'){throw 'Stream was changed.'}} finally {$stream.Dispose()}
}
$rejected=$false;$stream=[IO.MemoryStream]::new($bytes)
try {Read-ReleaseStream $stream 8 16 'Test transfer'|Out-Null} catch {$rejected=$true} finally {$stream.Dispose()}
if (-not $rejected) {throw 'Truncated response accepted.'}
$rejected=$false;$stream=[IO.MemoryStream]::new($bytes)
try {Read-ReleaseStream $stream 0 2 'Test transfer'|Out-Null} catch {$rejected=$true} finally {$stream.Dispose()}
if (-not $rejected) {throw 'Oversized response accepted.'}
Close-DownloadProgress
Write-Host 'Download progress checks passed.'
Add-Type -TypeDefinition @'
using System;using System.IO;using System.Threading;using System.Threading.Tasks;
public class CdtDownloadFixtureStream:MemoryStream {
 public bool Stalled;
 public override Task<int> ReadAsync(byte[] b,int offset,int count,CancellationToken token) {
  if(Stalled)return new TaskCompletionSource<int>().Task;
  Thread.Sleep(10);b[offset]=1;return Task.FromResult(1);
 }
}
'@
foreach($stalled in @($true,$false)) {
 $stream=[CdtDownloadFixtureStream]::new();$stream.Stalled=$stalled;$rejected=$false
 $clock=[Diagnostics.Stopwatch]::StartNew()
 try {Read-ReleaseStream $stream 0 65536 'Test timeout' 0.05 0.05|Out-Null} catch {$rejected=$true} finally {$stream.Dispose()}
 if (-not $rejected -or $clock.Elapsed.TotalSeconds -gt 3) {throw 'Download deadline was not enforced.'}
}
$writer=(Get-Command Write-DownloadProgress).ScriptBlock
$script:LastFrame=$null
function Write-DownloadProgress {
 param($Phase,$Received,$Total,$Seconds,[switch]$Force)
 $script:LastFrame=@{Received=$Received;Total=$Total;Force=[bool]$Force}
}
$stream=[IO.MemoryStream]::new([byte[]]@(1,2,3,4))
try {Read-ReleaseStream $stream 4 16 'Downloading installer'|Out-Null} finally {$stream.Dispose()}
if (-not $script:LastFrame.Force -or $script:LastFrame.Received -ne 4) {throw 'The completed download frame was not shown.'}
Set-Item Function:Write-DownloadProgress $writer
