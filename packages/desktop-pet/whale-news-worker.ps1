param([Parameter(Mandatory=$true)][string]$PetHome)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'whale-pet-common.ps1')
. (Join-Path $PSScriptRoot 'whale-news.ps1')
$created = $false
$mutex = New-Object Threading.Mutex($true, (Get-PetMutexName 'News' $PetHome), [ref]$created)
if (-not $created) { $mutex.Dispose(); exit 0 }
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
  $process = [Diagnostics.Process]::GetCurrentProcess()
  try { Write-PetJson (Join-Path $PetHome 'news-refresh.lock') @{ pid = $PID; startedAtTicks = $process.StartTime.ToUniversalTime().Ticks } }
  finally { $process.Dispose() }
  Set-WhaleNewsRefreshStatus -PetHome $PetHome -State 'running'
  $preferences = Read-PetJson (Join-Path $PetHome 'pet-preferences.json')
  $cache = Update-WhaleNewsCache -PetHome $PetHome -Preferences $preferences
  Set-WhaleNewsRefreshStatus -PetHome $PetHome -State 'completed' -CacheStatus $cache.status -DurationMs $watch.ElapsedMilliseconds
} catch {
  # Never store exception text (which may contain a remote HTML body or a local path).
  # The last valid cache survives a persistence/process failure and stays readable.
  try { Set-WhaleNewsRefreshStatus -PetHome $PetHome -State 'failed' -Code 'worker-update-failed' -Message '新闻更新未完成，原来的新闻仍然保留。请稍后重试。' -DurationMs $watch.ElapsedMilliseconds } catch {}
} finally {
  try { [IO.File]::Delete((Join-Path $PetHome 'news-refresh.lock')) } catch {}
  $mutex.ReleaseMutex(); $mutex.Dispose()
}
