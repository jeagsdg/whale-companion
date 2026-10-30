param([string]$TestHome)
$ErrorActionPreference='Stop'
$package=Join-Path $PSScriptRoot '..\packages\desktop-pet'
. (Join-Path $package 'whale-pet-common.ps1')
. (Join-Path $package 'whale-host.ps1')
. (Join-Path $package 'whale-codex-core.ps1')
$sessions=Join-Path $TestHome 'sessions'
$oldFolder=Join-Path $sessions '2020\01\01';[void][IO.Directory]::CreateDirectory($oldFolder)
$rootPath=Join-Path $oldFolder 'long-lived.jsonl'
$sid='01a13567-1329-7381-bb41-6ce4f4d18c47'
$meta=@{type='session_meta';payload=@{id=$sid;cwd='E:\old\中文项目'}}|ConvertTo-Json -Depth 5 -Compress
$event=@{type='event_msg';timestamp=[DateTimeOffset]::UtcNow.ToString('o');payload=@{type='task_started'}}|ConvertTo-Json -Depth 5 -Compress
[IO.File]::WriteAllText($rootPath,($meta+"`n"+$event+"`n"),(New-Object Text.UTF8Encoding($false)))
[IO.File]::SetLastWriteTimeUtc($rootPath,[DateTime]::UtcNow.AddMinutes(-10))
for($i=0;$i -lt 45;$i++){
  $sub=@{type='session_meta';payload=@{id=[Guid]::NewGuid().ToString();cwd='E:\worker';source=@{subagent=@{thread_spawn=@{}}}}}|ConvertTo-Json -Depth 8 -Compress
  [IO.File]::WriteAllText((Join-Path $sessions ('sub-'+$i+'.jsonl')),($sub+"`n"),(New-Object Text.UTF8Encoding($false)))
}
try{
  if(-not (Initialize-PetCodexWatch $TestHome $sessions $true)){throw 'Cannot acquire isolated reader.'}
  Discover-Sessions
  if($script:tracks.Count -ne 1 -or -not $script:tracks.ContainsKey($rootPath)){throw 'Recent subagents starved the long-lived root session.'}
  Read-SessionChanges
  $events=@(Get-ChildItem -LiteralPath (Join-Path $TestHome 'host-events') -File)
  if($events.Count -ne 1 -or (Read-PetJson $events[0].FullName).note -cne '中文项目'){throw 'Resumed old-date session was not reported accurately.'}
}finally{Close-PetCodexWatch}
$cache=@{};$cachePath=Join-Path $TestHome 'cached.json'
Write-PetJson $cachePath @{value=1}
$first=Read-PetJsonCached $cachePath $cache;$same=Read-PetJsonCached $cachePath $cache
if(-not [object]::ReferenceEquals($first,$same)){throw 'Unchanged JSON was parsed again.'}
Write-PetJson $cachePath @{value=2};[IO.File]::SetLastWriteTimeUtc($cachePath,[DateTime]::UtcNow.AddSeconds(1))
if((Read-PetJsonCached $cachePath $cache).value -ne 2){throw 'Changed JSON was not invalidated.'}
[IO.File]::WriteAllText($cachePath,('x'*1048577))
if($null -ne (Read-PetJson $cachePath)){throw 'Oversized JSON was accepted.'}
[IO.File]::Delete($cachePath)
if($null -ne (Read-PetJsonCached $cachePath $cache) -or $cache.ContainsKey($cachePath)){throw 'Deleted file remained cached.'}
Write-PetJson $cachePath @{value=3}
$script:readAttempts=0
function Read-PetJson([string]$Path){$script:readAttempts++;if($script:readAttempts -eq 1){return $null};return [pscustomobject]@{value=3}}
if($null -ne (Read-PetJsonCached $cachePath $cache)){throw 'Failed read was unexpectedly accepted.'}
if((Read-PetJsonCached $cachePath $cache).value -ne 3 -or $script:readAttempts -ne 2){throw 'Transient failed read poisoned the unchanged-file cache.'}
'Session discovery and bounded JSON cache passed.'
