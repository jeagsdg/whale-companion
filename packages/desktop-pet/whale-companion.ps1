# Companion preferences and local task/reminder model. PowerShell 5.1; no UI or startup side effects.
function ConvertTo-PetSingleLine([string]$Value, [int]$MaxLength = 80) {
  $value = ([regex]::Replace([string]$Value, '[\x00-\x1F\x7F]', ' ')).Trim()
  $value = [regex]::Replace($value, '\s+', ' ')
  if ($value.Length -gt $MaxLength) { throw ('最多填写 ' + $MaxLength + ' 个字。') }
  return $value
}
function Get-PetPreferenceDefaults {
  return @{ petName = '鲸鱼娘'; userName = '你'; host = 'codex'; displayMode = 'desktop'; autoWakeOnHostStart = $true; quiet = $true; walk = $true; breakReminders = $false; focusMinutes = 25; newsEnabled = $true; newsTopics = @('tech', 'ai'); newsMinMinutes = 60; newsMaxMinutes = 180; newsDailyLimit = 3 }
}
function Get-PetBoundedNumber($Value, [int]$Default, [int]$Min, [int]$Max) {
  $number = 0
  if (-not [int]::TryParse([string]$Value, [ref]$number) -or $number -lt $Min -or $number -gt $Max) { return $Default }
  return $number
}
function Repair-PetPreferences([hashtable]$Preferences) {
  $defaults = Get-PetPreferenceDefaults
  foreach ($key in $defaults.Keys) { if (-not $Preferences.ContainsKey($key)) { $Preferences[$key] = $defaults[$key] } }
  foreach($key in @('autoWakeOnHostStart','quiet','walk','breakReminders','newsEnabled')) {
    if($Preferences[$key] -isnot [bool]) {
      $value=$false
      $Preferences[$key]=if([bool]::TryParse([string]$Preferences[$key],[ref]$value)){$value}else{$defaults[$key]}
    }
  }
  foreach ($key in @('petName', 'userName')) {
    try { $name = ConvertTo-PetSingleLine ([string]$Preferences[$key]) 24 } catch { $name = '' }
    $Preferences[$key] = if ($name) { $name } else { $defaults[$key] }
  }
  if ($Preferences.host -notin @('codex', 'dsh')) { $Preferences.host = 'codex' }
  if ($Preferences.displayMode -notin @('desktop','native')) { $Preferences.displayMode = 'desktop' }
  $Preferences.focusMinutes = Get-PetBoundedNumber $Preferences.focusMinutes 25 5 180
  $Preferences.newsMinMinutes = Get-PetBoundedNumber $Preferences.newsMinMinutes 60 60 720
  $Preferences.newsMaxMinutes = Get-PetBoundedNumber $Preferences.newsMaxMinutes 180 60 720
  if ($Preferences.newsMaxMinutes -lt $Preferences.newsMinMinutes) { $Preferences.newsMaxMinutes = $Preferences.newsMinMinutes }
  $Preferences.newsDailyLimit = Get-PetBoundedNumber $Preferences.newsDailyLimit 3 1 6
  $Preferences.newsTopics = @($Preferences.newsTopics | Where-Object { $_ -in @('tech', 'ai', 'china', 'world', 'games') } | Select-Object -Unique)
  if (-not $Preferences.newsTopics.Count) { $Preferences.newsTopics = @('tech', 'ai') }
  return $Preferences
}
function Get-PetCompanionText([string]$Text, [hashtable]$Preferences) {
  $pet = if ($Preferences.petName) { [string]$Preferences.petName } else { '鲸鱼娘' }
  $user = if ($Preferences.userName) { [string]$Preferences.userName } else { '你' }
  $replace = { param($match) if ($match.Value -in @('{pet}', '鲸鱼娘')) { return $pet }; return $user }.GetNewClosure()
  return [regex]::Replace($Text, '\{pet\}|\{user\}|鲸鱼娘|主人|你', [System.Text.RegularExpressions.MatchEvaluator]$replace)
}
function Get-PetCompanionData([string]$Path) {
  $saved = Read-PetJson $Path
  $data = @{ version = 1; tasks = @(); reminders = @(); focus = $null; focusNotice=$null; focusCompletedCount=0 }
  if ($saved) {
    $data.focusCompletedCount=Get-PetBoundedNumber $saved.focusCompletedCount 0 0 1000000
    if($saved.focusNotice -and (Get-PetBoundedNumber $saved.focusNotice.minutes 0 5 180)) {
      $data.focusNotice=@{minutes=[int]$saved.focusNotice.minutes;at=[string]$saved.focusNotice.at}
    }
    foreach ($task in @($saved.tasks | Where-Object { $_ -and $_.id -and $_.text } | Select-Object -Last 200)) {
      try {
        $text = ConvertTo-PetSingleLine ([string]$task.text) 120
        $data.tasks += @{ id = [string]$task.id; text = $text; done = ($task.done -eq $true); createdAt = [string]$task.createdAt; commandId = [string]$task.commandId }
      } catch { }
    }
    foreach ($reminder in @($saved.reminders | Where-Object { $_ -and $_.id -and $_.text -and $_.dueAt } | Select-Object -Last 100)) {
      try {
        $text = ConvertTo-PetSingleLine ([string]$reminder.text) 120
        $deadline = [DateTime]::MinValue
        if ([DateTime]::TryParse([string]$reminder.dueAt, [ref]$deadline)) {
          $data.reminders += @{ id = [string]$reminder.id; text = $text; dueAt = [string]$reminder.dueAt; notified = ($reminder.notified -eq $true); commandId = [string]$reminder.commandId }
        }
      } catch { }
    }
    if ($saved.focus -and (Get-PetBoundedNumber $saved.focus.minutes 0 5 180)) {
      $remaining=Get-PetBoundedNumber $saved.focus.remainingSeconds 0 1 ([int]$saved.focus.minutes*60)
      $deadline = [DateTime]::MinValue
      if($saved.focus.paused -eq $true -and $remaining -gt 0){
        $data.focus=@{until='';minutes=[int]$saved.focus.minutes;paused=$true;remainingSeconds=$remaining}
      } elseif ([DateTime]::TryParse([string]$saved.focus.until, [ref]$deadline) -and $deadline -lt [DateTime]::Now.AddMinutes(181)) {
        $data.focus = @{ until = [string]$saved.focus.until; minutes = [int]$saved.focus.minutes }
      }
    }
  }
  return $data
}
function Copy-PetCompanionData([hashtable]$Data) {
  $copy = ($Data | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
  return @{ version = 1; tasks = @($copy.tasks); reminders = @($copy.reminders); focus = $copy.focus; focusNotice=$copy.focusNotice; focusCompletedCount=[int]$copy.focusCompletedCount }
}
function Add-PetTask([hashtable]$Data, [string]$Text) {
  $text = ConvertTo-PetSingleLine $Text 120
  if (-not $text) { throw '先写一件想做的小事吧。' }
  if (@($Data.tasks | Where-Object { -not $_.done }).Count -ge 50) { throw '待办已满 50 条，先完成或删除几条吧。' }
  $task = @{ id = [Guid]::NewGuid().ToString('N'); text = $text; done = $false; createdAt = [DateTimeOffset]::UtcNow.ToString('o') }
  $Data.tasks = @($Data.tasks) + $task
  if ($Data.tasks.Count -gt 200) {
    $active = @($Data.tasks | Where-Object { -not $_.done })
    $completed = @($Data.tasks | Where-Object { $_.done } | Select-Object -Last (200 - $active.Count))
    $Data.tasks = $active + $completed
  }
  return $task
}
function Set-PetTaskDone([hashtable]$Data, [string]$Id, [bool]$Done = $true) {
  foreach ($task in $Data.tasks) { if ($task.id -eq $Id) { if ([bool]$task.done -eq $Done) { return $false };if(-not $Done -and @($Data.tasks|Where-Object{-not $_.done}).Count -ge 50){throw '待做已有 50 条，先完成或移除几条再重新打开。'}; $task.done = $Done; return $true } }
  return $false
}
function Remove-PetTask([hashtable]$Data, [string]$Id) { $Data.tasks = @($Data.tasks | Where-Object { $_.id -ne $Id }) }
function Set-PetTaskText([hashtable]$Data,[string]$Id,[string]$Text){
  $text=ConvertTo-PetSingleLine $Text 120
  if(-not $text){throw '待办内容不能为空。'}
  foreach($task in $Data.tasks){if($task.id -eq $Id){$task.text=$text;return}}
  throw '这条待办已被移除，刷新后再试。'
}
function Add-PetReminder([hashtable]$Data, [string]$Text, [int]$Minutes, [DateTime]$Now = [DateTime]::Now) {
  $text = ConvertTo-PetSingleLine $Text 120
  if (-not $text) { throw '写一句想让我提醒的事吧。' }
  if ($Minutes -lt 1 -or $Minutes -gt 1440) { throw '提醒时间支持 1 到 1440 分钟。' }
  if (@($Data.reminders | Where-Object { -not $_.notified }).Count -ge 20) { throw '已有 20 条提醒，先完成或删除几条吧。' }
  $reminder = @{ id = [Guid]::NewGuid().ToString('N'); text = $text; dueAt = $Now.ToUniversalTime().AddMinutes($Minutes).ToString('o'); notified = $false }
  $pending=@($Data.reminders | Where-Object {-not $_.notified})
  $history=@($Data.reminders | Where-Object {$_.notified} | Select-Object -Last (99-$pending.Count))
  $Data.reminders = $pending + $history + $reminder
  return $reminder
}
function Remove-PetReminder([hashtable]$Data, [string]$Id) { $Data.reminders = @($Data.reminders | Where-Object { $_.id -ne $Id }) }
function Snooze-PetReminder([hashtable]$Data,[string]$Id,[int]$Minutes=10,[DateTime]$Now=[DateTime]::Now){
  if($Minutes -lt 1 -or $Minutes -gt 1440){throw '稍后提醒支持 1 到 1440 分钟。'}
  foreach($reminder in $Data.reminders){if($reminder.id -eq $Id){
    if($reminder.notified -and @($Data.reminders|Where-Object{-not $_.notified}).Count -ge 20){throw '待提醒已有 20 条，先取消几条吧。'}
    $reminder.dueAt=$Now.ToUniversalTime().AddMinutes($Minutes).ToString('o');$reminder.notified=$false;return
  }}
  throw '这条提醒已取消。'
}
function Get-PetFocusRemainingSeconds([hashtable]$Data,[DateTime]$Now=[DateTime]::Now){
  if(-not $Data.focus){return 0}
  if($Data.focus.paused -eq $true){return [int]$Data.focus.remainingSeconds}
  $deadline=Get-PetFocusDeadline $Data
  if(-not $deadline){return 0}
  return [int][Math]::Max(0,[Math]::Ceiling(($deadline-$Now).TotalSeconds))
}
function Get-PetDueReminders([hashtable]$Data, [DateTime]$Now) {
  return @($Data.reminders | Where-Object {
    $deadline = [DateTime]::MinValue
    -not $_.notified -and [DateTime]::TryParse([string]$_.dueAt, [ref]$deadline) -and $deadline.ToUniversalTime() -le $Now.ToUniversalTime()
  })
}
function Get-PetFocusDeadline([hashtable]$Data) {
  $deadline = [DateTime]::MinValue
  if ($Data.focus -and $Data.focus.paused -ne $true -and [DateTime]::TryParse([string]$Data.focus.until, [ref]$deadline)) { return $deadline.ToLocalTime() }
  return $null
}
function Test-PetThreadId([string]$ThreadId) { return ($ThreadId -match '^[a-zA-Z0-9][a-zA-Z0-9_-]{7,127}$') }
function Test-PetNewsUrl([string]$Url) {
  $uri = $null
  return ([Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https') -and -not $uri.UserInfo)
}
function Get-PetNewsLibrary([string]$Path){
  $saved=Read-PetJson $Path
  $library=@{readIds=@();savedItems=@()}
  if($saved){
    $library.readIds=@($saved.readIds|Where-Object{$_ -is [string] -and $_.Length -gt 0 -and $_.Length -le 128}|Select-Object -Unique -Last 2000)
    $library.savedItems=@($saved.savedItems|Where-Object{$_ -and $_.id -and $_.title -and (Test-PetNewsUrl ([string]$_.url))}|Select-Object -First 100)
  }
  return $library
}
function Set-PetNewsLibraryItem([hashtable]$Library,$Item,[string]$Action){
  if(-not $Item.id -or -not (Test-PetNewsUrl ([string]$Item.url))){throw '这条新闻缺少有效原文链接。'}
  $id=[string]$Item.id
  switch($Action){
    'read'{$Library.readIds=@(@($Library.readIds)+$id|Select-Object -Unique -Last 2000)}
    'save'{
      if(@($Library.savedItems|Where-Object{$_.id -eq $id}).Count){$Library.savedItems=@($Library.savedItems|Where-Object{$_.id -ne $id})}
      else{if($Library.savedItems.Count -ge 100){throw '已经收藏 100 条，先取消几条收藏吧。'};$Library.savedItems=@($Library.savedItems)+$Item}
    }
    default{throw '不支持的新闻操作。'}
  }
}
