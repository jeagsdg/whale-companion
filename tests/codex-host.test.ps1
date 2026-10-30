param([Parameter(Mandatory=$true)][string]$TestHome)
$ErrorActionPreference = 'Stop'
$package = Join-Path $PSScriptRoot '..\packages\desktop-pet'
. (Join-Path $package 'whale-pet-common.ps1')
. (Join-Path $package 'whale-host.ps1')
$TestHome = [IO.Path]::GetFullPath($TestHome)
[void][IO.Directory]::CreateDirectory($TestHome)
$script:passed = 0
$script:failures = @()
function Assert($Condition, [string]$Name) {
  if (-not $Condition) { $script:failures += $Name }
  else { $script:passed++ }
}
function Assert-OnlyMetadata($Event, [string]$Name) {
  $keys = @($Event.Keys | Sort-Object)
  Assert (($keys -join ',') -eq 'activity,at,kind,project,sid') ($Name + ': exact metadata keys')
  Assert (($Event | ConvertTo-Json -Depth 20) -notmatch 'TOP_SECRET') ($Name + ': no sensitive fields')
}
# This guard would fail the test if any adapter path tried to launch an application.
function Start-Process { throw 'Host conversion tests must never start any application.' }
$session = '01a13567-1329-7381-bb41-6ce4f4d18c47'
foreach ($id in @($session, $session.ToUpperInvariant(), 'thr_abc-XYZ_123')) { Assert (Test-PetSessionId $id) ('valid session ' + $id) }
foreach ($id in @('', '../elsewhere', 'thr_', ('thr_' + ('a' * 101)), 'codex://threads/anything', 'x;Start-Process bad', ($session + '\..'))) {
  Assert (-not (Test-PetSessionId $id)) ('invalid session ' + $id)
}
$hooks = @{ SessionStart='idle'; UserPromptSubmit='running'; PermissionRequest='approval'; Stop='completion'; Interrupt='interrupted'; SessionEnd='idle' }
foreach ($name in $hooks.Keys) {
  $event = Convert-PetHookEvent ([PSCustomObject]@{ hook_event_name=$name;session_id=$session;cwd='E:\Projects\鲸鱼项目\';
    prompt='TOP_SECRET_PROMPT';tool_input=@{ arguments='TOP_SECRET_TOOL_ARGS' };response='TOP_SECRET_RESPONSE' })
  Assert ($event.kind -eq $hooks[$name] -and $event.sid -eq $session -and $event.project -eq '鲸鱼项目') ('hook mapping ' + $name)
  Assert-OnlyMetadata $event ('hook privacy ' + $name)
}
Assert ($null -eq (Convert-PetHookEvent @{hook_event_name='Unsupported';prompt='TOP_SECRET'})) 'unknown hook ignored'
foreach($case in @(@{name='functions.exec';args='npm test TOP_SECRET';expected='test'},@{name='apply_patch';args='TOP_SECRET';expected='edit'},@{name='image_gen';args='TOP_SECRET';expected='art'},@{name='exec_command';args='git diff TOP_SECRET';expected='review'},@{name='exec_command';args='Get-Content file TOP_SECRET';expected='read'})){
  Assert ((Get-PetWorkActivity $case.name $case.args) -eq $case.expected) ('work category '+$case.expected)
}
$records = @(
  @{type='event_msg';payload=@{type='task_started'};expected='running'},
  @{type='event_msg';payload=@{type='task_complete'};expected='completion'},
  @{type='event_msg';payload=@{type='turn_aborted'};expected='interrupted'},
  @{type='event_msg';payload=@{type='task_failed'};expected='failure'},
  @{type='response_item';payload=@{type='function_call';name='exec_command';arguments='TOP_SECRET'};expected='tool'},
  @{type='response_item';payload=@{type='custom_tool_call';name='apply_patch';input='TOP_SECRET'};expected='tool'},
  @{type='response_item';payload=@{type='function_call';name='tools.request_user_input';arguments='TOP_SECRET'};expected='question'}
)
foreach ($record in $records) {
  $record.timestamp = [DateTimeOffset]::UtcNow.ToString('o')
  $record.prompt = 'TOP_SECRET_PROMPT'
  $record.output = 'TOP_SECRET_OUTPUT'
  $event = Convert-PetRolloutEvent $record $session '鲸鱼项目'
  Assert ($event.kind -eq $record.expected -and $event.sid -eq $session -and $event.project -eq '鲸鱼项目') ('rollout mapping ' + $record.expected)
  Assert-OnlyMetadata $event ('rollout privacy ' + $record.expected)
}
foreach ($record in @(
  @{type='event_msg';payload=@{type='user_message';message='TOP_SECRET'}},
  @{type='event_msg';payload=@{type='agent_message';message='TOP_SECRET'}},
  @{type='response_item';payload=@{type='message';content='TOP_SECRET'}},
  @{type='response_item';payload=@{type='reasoning';summary='TOP_SECRET'}},
  @{type='response_item';payload=@{type='function_call_output';output='TOP_SECRET'}}
)) { Assert ($null -eq (Convert-PetRolloutEvent $record $session '鲸鱼项目')) 'conversation contents ignored' }
Assert ($null -eq (Convert-PetRolloutEvent @{timestamp='invalid';type='event_msg';payload=@{type='task_complete'}} $session 'x')) 'malformed timestamp ignored'

$eventHome = Join-Path $TestHome 'events'
Send-PetHostEvent $eventHome @{kind='completion';sid=$session;project='鲸鱼项目';at=Get-PetUtcMs;prompt='TOP_SECRET';arguments='TOP_SECRET'}
$files = @(Get-ChildItem -LiteralPath (Join-Path $eventHome 'host-events') -File)
Assert ($files.Count -eq 1) 'valid event persisted once'
$persisted = Read-PetJson $files[0].FullName
Assert ($persisted.host -eq 'codex' -and $persisted.kind -eq 'completion' -and $persisted.sid -eq $session -and $persisted.note -eq '鲸鱼项目') 'persisted metadata identity'
Assert (($persisted.PSObject.Properties.Name | Sort-Object) -join ',' -eq 'activity,at,host,kind,line,note,noticeId,pose,sid') 'persisted metadata whitelist'
Assert (([IO.File]::ReadAllText($files[0].FullName)) -notmatch 'TOP_SECRET') 'persistence omits raw prompt and arguments'
foreach ($event in @(
  @{kind='completion';sid='../escape';at=Get-PetUtcMs},
  @{kind='unknown';sid=$session;at=Get-PetUtcMs},
  @{kind='completion';sid=$session;at=((Get-PetUtcMs) - 180000)},
  @{kind='completion';sid=$session;at=((Get-PetUtcMs) + 60000)},
  @{kind='completion';sid=$session;at=0}
)) { Send-PetHostEvent $eventHome $event }
Assert (@(Get-ChildItem -LiteralPath (Join-Path $eventHome 'host-events') -File).Count -eq 1) 'invalid identity, unknown kind, stale epoch and future events rejected'

# Exercise the actual incremental reader with a UTF-8 code point crossing its 256 KiB boundary.
$watcher = Join-Path $package 'whale-codex-core.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($watcher, [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'watcher syntax parses'
foreach ($name in @('Get-PetRecentSessionFiles', 'Discover-Sessions', 'Read-SessionChanges')) {
  $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
  Assert ($null -ne $function) ('watcher function exists ' + $name)
  . ([scriptblock]::Create($function.Extent.Text))
}
$PetHome = Join-Path $TestHome 'utf8-pet'
$SessionRoot = Join-Path $TestHome 'utf8-sessions'
[void][IO.Directory]::CreateDirectory($SessionRoot)
$Replay = $true
$tracks = @{}
$file = Join-Path $SessionRoot 'rollout-utf8.jsonl'
$meta = (@{type='session_meta';payload=@{id=$session;cwd='E:\Projects\鲸鱼项目';source='cli'}} | ConvertTo-Json -Depth 10 -Compress) + "`n"
$prefix = '{"timestamp":"' + [DateTimeOffset]::UtcNow.ToString('o') + '","type":"event_msg","payload":{"type":"task_complete"},"padding":"'
$middle = '","proof":"'
$padding = 262143 - [Text.Encoding]::UTF8.GetByteCount($meta + $prefix + $middle)
$row = $prefix + ('x' * $padding) + $middle + '🌊中文' + '"}'
[IO.File]::WriteAllText($file, $meta + $row, (New-Object Text.UTF8Encoding($false)))
$originalConvert = (Get-Command Convert-PetRolloutEvent).ScriptBlock
$script:observedProof = $null
function Convert-PetRolloutEvent($Record, [string]$SessionId, [string]$Project) {
  if ($Record.proof) { $script:observedProof = [string]$Record.proof }
  return (& $originalConvert $Record $SessionId $Project)
}
Discover-Sessions
Assert ($tracks.Count -eq 1) 'UTF8 session discovered'
Read-SessionChanges
Assert ($tracks[$file].offset -eq 262144) 'first incremental read stops on byte boundary'
Assert ($tracks[$file].buffer.IndexOf([char]0xfffd) -lt 0) 'split UTF8 byte is buffered without replacement'
Assert (-not (Test-Path -LiteralPath (Join-Path $PetHome 'host-events'))) 'incomplete JSON emits no event'
Read-SessionChanges
Assert ($null -eq $script:observedProof) 'complete JSON without newline remains buffered'
[IO.File]::AppendAllText($file, "`n", (New-Object Text.UTF8Encoding($false)))
Read-SessionChanges
Assert ($script:observedProof -eq '🌊中文') 'split UTF8 survives until newline commits the record'
$utf8Files = @(Get-ChildItem -LiteralPath (Join-Path $PetHome 'host-events') -File)
Assert ($utf8Files.Count -eq 1 -and (Read-PetJson $utf8Files[0].FullName).kind -eq 'completion') 'UTF8 completion emitted exactly once'
Read-SessionChanges
Assert (@(Get-ChildItem -LiteralPath (Join-Path $PetHome 'host-events') -File).Count -eq 1) 'repeated read does not duplicate completion'

# A new short turn can finish before the 20-second discovery pass. It must be read
# on discovery, while files that predate watcher startup retain the EOF behavior.
$PetHome = Join-Path $TestHome 'fast-turn-pet'
$SessionRoot = Join-Path $TestHome 'fast-turn-sessions'
[void][IO.Directory]::CreateDirectory($SessionRoot)
$Replay = $false; $tracks = @{}
$script:watcherStartedAt = [DateTime]::UtcNow.AddSeconds(-10)
$fastId = [Guid]::NewGuid().ToString()
$oldId = [Guid]::NewGuid().ToString()
$fastFile = Join-Path $SessionRoot 'fast-completed.jsonl'
$oldFile = Join-Path $SessionRoot 'existing-completed.jsonl'
foreach ($fixture in @(@{ path = $fastFile; id = $fastId; new = $true }, @{ path = $oldFile; id = $oldId; new = $false })) {
  $metaLine = @{ type = 'session_meta'; payload = @{ id = $fixture.id; cwd = 'E:\Projects\短会话'; source = 'cli' } } | ConvertTo-Json -Depth 10 -Compress
  $completedLine = @{ timestamp = [DateTimeOffset]::UtcNow.ToString('o'); type = 'event_msg'; payload = @{ type = 'task_complete' } } | ConvertTo-Json -Depth 10 -Compress
  [IO.File]::WriteAllText($fixture.path, $metaLine + "`n" + $completedLine + "`n", (New-Object Text.UTF8Encoding($false)))
  $createdAt = if ($fixture.new) { [DateTime]::UtcNow } else { $script:watcherStartedAt.AddMinutes(-1) }
  [IO.File]::SetCreationTimeUtc($fixture.path, $createdAt)
}
Discover-Sessions
Assert ($tracks.Count -eq 2 -and $tracks[$fastFile].offset -eq 0) 'newly created short session starts reading at the first record'
Assert ($tracks[$oldFile].offset -eq (Get-Item -LiteralPath $oldFile).Length) 'existing session begins at EOF without replaying historical turns'
Read-SessionChanges
$fastEvents = @(Get-ChildItem -LiteralPath (Join-Path $PetHome 'host-events') -File)
Assert ($fastEvents.Count -eq 1 -and (Read-PetJson $fastEvents[0].FullName).sid -eq $fastId -and (Read-PetJson $fastEvents[0].FullName).kind -eq 'completion') 'short new turn completion reaches the event inbox on first discovery'
Read-SessionChanges
Assert (@(Get-ChildItem -LiteralPath (Join-Path $PetHome 'host-events') -File).Count -eq 1) 'first-discovery short completion is emitted only once'

# New child-agent files sort ahead of root chats; they must not consume the six
# root-chat tracking slots, and old tracked roots must be bounded on rediscovery.
$PetHome = Join-Path $TestHome 'root-selection-pet'
$SessionRoot = Join-Path $TestHome 'root-selection-sessions'
[void][IO.Directory]::CreateDirectory($SessionRoot)
$tracks = @{}; $script:watcherStartedAt = [DateTime]::UtcNow.AddMinutes(-1)
$rootIds = @(); $rootPaths = @(); $childIds = @(); $childPaths = @()
for ($i = 0; $i -lt 7; $i++) {
  $id = [Guid]::NewGuid().ToString(); $rootIds += $id
  $path = Join-Path $SessionRoot ('root-' + $i + '.jsonl'); $rootPaths += $path
  $metaLine = @{ type = 'session_meta'; payload = @{ id = $id; cwd = 'E:\Projects\根会话'; source = 'cli' } } | ConvertTo-Json -Depth 10 -Compress
  $completedLine = @{ timestamp = [DateTimeOffset]::UtcNow.ToString('o'); type = 'event_msg'; payload = @{ type = 'task_complete' } } | ConvertTo-Json -Depth 10 -Compress
  [IO.File]::WriteAllText($path, $metaLine + "`n" + $completedLine + "`n", (New-Object Text.UTF8Encoding($false)))
  [IO.File]::SetCreationTimeUtc($path, [DateTime]::UtcNow)
  [IO.File]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddSeconds(-20 - $i))
}
for ($i = 0; $i -lt 12; $i++) {
  $id = [Guid]::NewGuid().ToString(); $childIds += $id
  $path = Join-Path $SessionRoot ('child-' + $i + '.jsonl'); $childPaths += $path
  $metaLine = @{ type = 'session_meta'; payload = @{ id = $id; cwd = 'E:\Projects\子会话'; source = @{ subagent = @{ thread_spawn = @{ parent_thread_id = $rootIds[0]; depth = 1 } } } } } | ConvertTo-Json -Depth 10 -Compress
  $completedLine = @{ timestamp = [DateTimeOffset]::UtcNow.ToString('o'); type = 'event_msg'; payload = @{ type = 'task_complete' } } | ConvertTo-Json -Depth 10 -Compress
  [IO.File]::WriteAllText($path, $metaLine + "`n" + $completedLine + "`n", (New-Object Text.UTF8Encoding($false)))
  [IO.File]::SetCreationTimeUtc($path, [DateTime]::UtcNow)
  [IO.File]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddMilliseconds($i))
}
Discover-Sessions
Assert ($tracks.Count -eq 6 -and @($tracks.Keys | Where-Object { $_ -in $childPaths }).Count -eq 0) 'new child-agent files do not occupy any root tracking slot'
Assert (@($rootPaths | Select-Object -First 6 | Where-Object { $tracks.ContainsKey($_) }).Count -eq 6 -and -not $tracks.ContainsKey($rootPaths[6])) 'six most recent root chats are tracked despite newer child agents'
Read-SessionChanges
$rootEvents = @(Get-ChildItem -LiteralPath (Join-Path $PetHome 'host-events') -File)
Assert ($rootEvents.Count -eq 6 -and @($rootEvents | Where-Object { (Read-PetJson $_.FullName).sid -in $childIds }).Count -eq 0) 'only root-chat completions reach the pet inbox'
[IO.File]::SetLastWriteTimeUtc($rootPaths[6], [DateTime]::UtcNow.AddSeconds(1))
Discover-Sessions
Assert ($tracks.Count -eq 6 -and $tracks.ContainsKey($rootPaths[6]) -and -not $tracks.ContainsKey($rootPaths[5])) 'rediscovery replaces the oldest root without growing the tracked set'
Write-Output ('PASS: ' + $script:passed + ' Codex host assertions')
if ($script:failures.Count) { throw ('FAIL: ' + ($script:failures -join '; ')) }
