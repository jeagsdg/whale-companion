param([Parameter(Mandatory=$true)][string]$TestHome)
$ErrorActionPreference = 'Stop'
$package = Join-Path $PSScriptRoot '..\packages\desktop-pet'
. (Join-Path $package 'whale-pet-common.ps1')
. (Join-Path $package 'whale-diagnostics.ps1')
$script:passed = 0
function Assert($Value, [string]$Message) { if (-not $Value) { throw ('FAIL: ' + $Message) }; $script:passed++ }
function Save-Fixture([string]$File, $Data) { Write-PetJson (Join-Path $TestHome $File) $Data }
[void][IO.Directory]::CreateDirectory($TestHome)
$now = [DateTime]::Now; $nowMs = [DateTimeOffset]::new($now.ToUniversalTime()).ToUnixTimeMilliseconds()
foreach ($file in @('whale-pet.ps1','whale-pet-start.ps1','whale-pet-common.ps1','whale-companion.ps1','whale-companion-ui.ps1','whale-focus.ps1','whale-media.ps1','whale-news.ps1','whale-news-worker.ps1','whale-pet-http.ps1','whale-codex-core.ps1','whale-host-watch.exe','whale-host-native.dll','whale-mcp.mjs','sticker-catalog.json')) { [IO.File]::WriteAllText((Join-Path $TestHome $file), '# fixture') }
foreach ($file in @('alive.json','bridge-alive.json','host-watch-alive.json')) { Save-Fixture $file @{ at = $nowMs; pid = $PID } }
Save-Fixture 'runtime-version.json' @{ version = '2.4.0' }
Save-Fixture 'pet-preferences.json' @{ displayMode = 'desktop'; petName = 'secret-pet-name'; userName = 'secret-user-name'; token = 'DO-NOT-DISCLOSE' }
Save-Fixture 'companion-data.json' @{ tasks = @(@{ text = 'DO-NOT-READ-TASK' }) }
Save-Fixture 'news.json' @{ status = 'ok'; fetchedAt = $nowMs; items = @(@{ title = 'DO-NOT-READ-NEWS'; url = 'https://example.invalid' }) }
Save-Fixture 'news-refresh-status.json' @{ state = 'completed'; at = $nowMs }
$before = @{}; foreach ($file in [IO.Directory]::EnumerateFiles($TestHome)) { $before[$file] = [IO.File]::ReadAllText($file) }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.status -eq 'healthy' -and @($report.components | Where-Object state -eq 'healthy').Count -eq 3) 'all three live processes reported healthy'
Assert ($report.version.value -eq '2.4.0' -and $report.news.cachedItems -eq 1) 'version and news count available'
$json = $report | ConvertTo-Json -Depth 10
Assert ($json -notmatch 'DO-NOT|secret-pet|secret-user|token|example.invalid') 'whitelisted report excludes personal content and secrets'
Assert ((ConvertTo-PetHealthText $report) -match '功能服务') 'plain text available without WPF'
foreach ($file in $before.Keys) { Assert ([IO.File]::ReadAllText($file) -ceq $before[$file]) 'health check never changes original files' }
Save-Fixture 'news.json' @{ status = 'ok'; lastFetchedAt = $now.ToUniversalTime().ToString('o'); items = @() }
Assert ((Get-PetHealthReport $TestHome $now).news.fetchedAt -match '^\d{4}-') 'ISO news update time supported alongside numeric heartbeat timestamps'
Save-Fixture 'hidden.json' @{ at = $nowMs }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.mode.hidden -and $report.status -eq 'healthy' -and $report.mode.description -match '隐藏') 'hidden is intentional state, not service failure'
Save-Fixture 'pet-preferences.json' @{ displayMode = 'native' }
Save-Fixture 'hidden.json' @{ at = $nowMs; supportOnly = $true }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.mode.displayMode -eq 'native' -and $report.mode.supportOnly -and $report.mode.description -match '面板') 'native mode explains preserved panels'
Save-Fixture 'control.json' @{ stopped = $true }
[IO.File]::Delete((Join-Path $TestHome 'alive.json')); [IO.File]::Delete((Join-Path $TestHome 'bridge-alive.json'))
$report = Get-PetHealthReport $TestHome $now
Assert ($report.status -eq 'stopped' -and $report.components[0].state -eq 'stopped' -and $report.components[1].state -eq 'stopped') 'explicit exit respected and not reported as crash'
Save-Fixture 'control.json' @{ stopped = $false }
Save-Fixture 'alive.json' @{ at = $nowMs - 50000; pid = $PID }
Save-Fixture 'bridge-alive.json' @{ at = $nowMs; pid = 2147483646 }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.components[0].state -eq 'stale' -and $report.components[1].state -eq 'offline') 'stale heartbeat and ended process distinguished'
Save-Fixture 'alive.json' @{ at = 'NaN'; pid = $PID }; Save-Fixture 'bridge-alive.json' @{ at = $nowMs + 60000; pid = $PID }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.components[0].state -eq 'invalid' -and $report.components[1].state -eq 'invalid') 'invalid and future heartbeat safely rejected'
[IO.File]::WriteAllText((Join-Path $TestHome 'pet-preferences.json'), '{corrupt')
Assert ([IO.File]::Exists((Join-Path $TestHome 'pet-preferences.json'))) ('corrupt file exists at ' + $TestHome)
[IO.File]::WriteAllText((Join-Path $TestHome 'news.json'), ('x' * 1048577))
Save-Fixture 'hidden.json' @('not','an','object')
$report = Get-PetHealthReport $TestHome $now
Assert ($report.status -eq 'attention' -and $report.dataIssues.Count -eq 3) 'corrupt, oversized and wrong-shape files do not crash report'
Assert (@($report.dataIssues | Where-Object state -eq 'too-large').Count -eq 1) 'one megabyte input limit enforced'
[IO.File]::Delete((Join-Path $TestHome 'whale-focus.ps1'))
Save-Fixture 'news-refresh-status.json' @{ state = 'running'; at = $nowMs - 200000 }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.missingFiles -contains 'whale-focus.ps1' -and $report.news.refreshState -eq 'stalled') 'missing component and stalled refresh have recovery guidance'
Save-Fixture 'commands\queued.json' @{ id = 'queued'; at = $nowMs; action = 'say'; text = 'NEVER-ECHO-COMMAND' }
Save-Fixture 'commands\expired.json' @{ id = 'expired'; at = $nowMs - 400000; action = 'say'; text = 'NEVER-ECHO-COMMAND' }
Save-Fixture 'command-results\failed.json' @{ id = 'failed'; status = 'failed'; at = $nowMs; error = 'NEVER-ECHO-ERROR' }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.commands.pendingCount -eq 2 -and $report.commands.expiredInSample -eq 1 -and $report.commands.failedInSample -eq 1) 'queue count and failure summary useful without private text'
Assert (($report | ConvertTo-Json -Depth 10) -notmatch 'NEVER-ECHO') 'commands and error bodies are not copied into diagnostic exports'
[IO.File]::WriteAllText((Join-Path $TestHome 'host-watch.log'), ('prefix secret ' * 4000) + "`nfailed NEVER-ECHO-LOG`n")
$report = Get-PetHealthReport $TestHome $now
Assert ($report.logs[0].inspectedBytes -le 32768 -and $report.logs[0].failureLines -eq 1) 'log scan limited to the last 32KB'
Assert (($report | ConvertTo-Json -Depth 10) -notmatch 'NEVER-ECHO-LOG|prefix secret') 'raw log lines never leave checker'
for ($i = 0; $i -lt 280; $i++) { Save-Fixture ('commands\bulk-' + $i + '.json') @{ at = $nowMs; action = 'say' } }
$report = Get-PetHealthReport $TestHome $now
Assert ($report.commands.pendingCount -eq 256 -and $report.commands.pendingCountIsLowerBound -and $report.commands.inspectedPending -eq 64) 'large queue has bounded enumeration and reads'
$empty = Get-PetHealthReport (Join-Path $TestHome 'does-not-exist') $now
Assert ($empty.status -eq 'attention' -and $empty.missingFiles.Count -gt 0) 'missing directory produces an actionable report'
$root = Get-PetHealthReport ([IO.Path]::GetPathRoot($TestHome)) $now
Assert ($root.status -eq 'attention') 'filesystem root input cannot crash parent log check'
$nullPath = Get-PetHealthReport ([string][char]0) $now
Assert ($nullPath.status -eq 'attention' -and $nullPath.summary -match '目录无效') 'illegal directory returns structured result'

# UI creation checks use a local isolated fixture. No window or clipboard is shown.
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
. (Join-Path $package 'whale-companion-ui.ps1')
$dialog = New-PetDiagnosticsWindow $TestHome
Assert ($dialog.Tag.controls.text.IsReadOnly -and $dialog.Tag.controls.text.Text -match '健康检查') 'diagnostic window renders read-only report'
Assert (-not $dialog.Tag.timer) 'diagnostic window creates no recurring timer'
$dialog.Tag.controls.refresh.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ($dialog.Tag.controls.status.Text -match '已完成') 'manual refresh callback works'
$dialog.Close()
'DIAGNOSTICS_PASSED=' + $script:passed
