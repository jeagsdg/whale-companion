# Codex adapter helpers. Only manual UI actions open the host; events never launch it.
function Test-PetSessionId([string]$Id) {
  return ($Id -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -or $Id -match '^thr_[a-zA-Z0-9_-]{1,100}$')
}
function Open-PetHost([string]$PetHome, [string]$SessionId = '') {
  $prefs = Read-PetJson (Join-Path $PetHome 'pet-preferences.json')
  if ($prefs.host -eq 'dsh') {
    if ($SessionId) { [IO.File]::AppendAllText((Join-Path (Split-Path -Parent $PetHome) 'dsh-desktop-notify.activate'), $SessionId + "`n", (New-Object Text.UTF8Encoding($false))) }
    try { [void](New-Object -ComObject WScript.Shell).AppActivate('DeepSeek Harness') } catch { }
    return
  }
  if ($SessionId -and (Test-PetSessionId $SessionId)) {
    try { Start-Process -FilePath ('codex://threads/' + [Uri]::EscapeDataString($SessionId)); return } catch { }
  }
  try { [void](New-Object -ComObject WScript.Shell).AppActivate('Codex') } catch { }
}
function Get-PetWorkActivity([string]$Name,[string]$Arguments=''){
  # Only a closed category leaves the reader. Never retain command arguments.
  $sample=$Arguments.Substring(0,[Math]::Min(16000,$Arguments.Length))
  $text=$Name+' '+$sample
  if($text -match '(?i)imagegen|image_gen|generate.image'){return 'art'}
  if($text -match '(?i)apply_patch|write_file|edit_file|replace_in_file'){return 'edit'}
  if($text -match '(?i)npm (?:run )?test|node --test|pytest|tests[/\\]|vitest|cargo test|go test'){return 'test'}
  if($text -match '(?i)git diff|code_review|review_pull_request'){return 'review'}
  if($text -match '(?i)search_query|web__run|web\.run|search_service'){return 'research'}
  if($text -match '(?i)npm run build|build-host|compile_latex|dotnet build|cargo build'){return 'build'}
  if($text -match '(?i)Get-Content|read_file|rg |view_image|list_directory'){return 'read'}
  return 'work'
}
function Send-PetHostEvent([string]$PetHome, $Event) {
  $control = Read-PetJson (Join-Path $PetHome 'control.json')
  if ($control.stopped) { return }
  $kind = [string]$Event.kind
  if ($kind -notin @('running','tool','completion','failure','approval','question','idle','interrupted')) { return }
  $sid = [string]$Event.sid
  if ($sid -and -not (Test-PetSessionId $sid)) { return }
  $stamp = [double](Get-PetUtcMs)
  if ($null -ne $Event.at) { if (-not [double]::TryParse([string]$Event.at,[ref]$stamp)) { return } }
  if ([double]::IsNaN($stamp) -or [double]::IsInfinity($stamp)) { return }
  $now = Get-PetUtcMs
  if ($stamp -gt $now + 30000 -or $stamp -lt $now - 120000) { return }
  $poses = @{running='think';tool='tool';completion='ok';failure='err';approval='wait';question='wait';idle='idle';interrupted='no'}
  $lines = @{running='我在认真处理这件事，陪你一起。';tool='正在动手做事，稍等我一下。';completion='{user}，这一轮完成啦，来看看成果吧。';failure='这一步遇到了问题，一起回 Codex 看看吧。';approval='{user}，Codex 需要你确认，点“带我去看”处理。';question='{user}，我需要你补充一点信息，来 Codex 看看吧。';idle='在这里，随时陪你。';interrupted='这一轮已暂停，按你的节奏来。'}
  $project = [string]$Event.project
  $activity=[string]$Event.activity
  if($activity -notin @('read','edit','test','review','research','build','art','work')){$activity=''}
  $lines.running='{user}，{pet}正在梳理「{project}」这一轮的工作。'
  $lines.completion='{user}，「{project}」这一轮处理完成了，成果在 Codex 里等你查看。'
  $lines.failure='{user}，「{project}」这一步遇到问题了，{pet}陪你回 Codex 看具体原因。'
  if($kind -eq 'tool'){
    $activityLines=@{read='检查代码和现有资料';edit='修改实现';test='运行测试和验证';review='核对这次改动';research='查找所需资料';build='构建运行版本';art='制作和检查表情素材';work='处理这一轮工作'}
    $description=if($activity){$activityLines[$activity]}else{$activityLines.work}
    $lines.tool='{user}，{pet}正在为「{project}」'+$description+'。'
    $poses.tool=if($activity -in @('test','review')){'v3-debug'}elseif($activity -eq 'art'){'v3-happy'}elseif($activity -eq 'read'){'v3-debug'}else{'v3-working'}
  }
  if ($project.Length -gt 160) { $project = $project.Substring(0,160) }
  $record = @{ host='codex';kind=$kind;sid=$sid;pose=$poses[$kind];line=$lines[$kind];note=$project;activity=$activity;at=$stamp;noticeId=[Guid]::NewGuid().ToString('N') }
  $path = Join-Path (Join-Path $PetHome 'host-events') (([long]$stamp).ToString() + '-' + $record.noticeId + '.json')
  Write-PetJson $path $record
}
function Convert-PetHookEvent($InputEvent) {
  $kind = switch ([string]$InputEvent.hook_event_name) {
    'SessionStart' { 'idle' }; 'UserPromptSubmit' { 'running' }; 'PermissionRequest' { 'approval' }
    'Stop' { 'completion' }; 'Interrupt' { 'interrupted' }; 'SessionEnd' { 'idle' }; default { $null }
  }
  if (-not $kind) { return $null }
  $cwd = [string]$InputEvent.cwd
  $project = if ($cwd) { [IO.Path]::GetFileName($cwd.TrimEnd('\','/')) } else { '' }
  return @{kind=$kind;sid=[string]$InputEvent.session_id;project=$project;activity='';at=Get-PetUtcMs}
}
function Convert-PetRolloutEvent($Record, [string]$SessionId, [string]$Project) {
  $kind = $null
  if ($Record.type -eq 'event_msg') {
    $kind = switch ([string]$Record.payload.type) {
      'task_started' { 'running' }; 'task_complete' { 'completion' }; 'turn_aborted' { 'interrupted' }
      'task_failed' { 'failure' }; default { $null }
    }
  } elseif ($Record.type -eq 'response_item' -and $Record.payload.type -in @('function_call','custom_tool_call')) {
    $kind = if ([string]$Record.payload.name -match 'request_user_input') { 'question' } else { 'tool' }
  }
  if (-not $kind) { return $null }
  $stamp = Get-PetUtcMs
  if ($Record.timestamp) { try { $stamp = [DateTimeOffset]::Parse([string]$Record.timestamp).ToUnixTimeMilliseconds() } catch { return $null } }
  # Do not forward prompt, tool arguments, output, reasoning, or assistant message text.
  $activity=if($kind -eq 'tool'){Get-PetWorkActivity ([string]$Record.payload.name) ([string]$Record.payload.arguments+' '+[string]$Record.payload.input)}else{''}
  return @{kind=$kind;sid=$SessionId;project=$Project;activity=$activity;at=$stamp}
}
