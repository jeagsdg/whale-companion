param([string]$TestHome)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationFramework
$moduleRoot=Join-Path $PSScriptRoot '..\packages\desktop-pet'
. (Join-Path $moduleRoot 'whale-pet-common.ps1')
. (Join-Path $moduleRoot 'whale-companion.ps1')
. (Join-Path $moduleRoot 'whale-companion-ui.ps1')
. (Join-Path $moduleRoot 'whale-news.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $moduleRoot 'whale-pet.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw ($errors|Out-String)}
foreach($name in @('Show-PetNativeNotice','Show-PetNewsNotice','Show-GentleReminder','Update-Companion','Start-Focus','Cancel-Focus')){
  $fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
  . ([scriptblock]::Create($fn.Extent.Text))
}
function Read-Json($path){Read-PetJson $path}
function Write-Json($path,$value){Write-PetJson $path $value}
function Update-Tray{}
function Save-Stats{}
function petLog($message){}
function Say($text,$ms,[switch]$Raw){$script:bubbleCount++}
function Show-Pose($pose,$ms){}
$script:passed=0
function Assert($condition,[string]$name){if(-not $condition){throw ('FAIL: '+$name)};$script:passed++}
$PetHome=$TestHome;$companionFile=Join-Path $TestHome 'companion-data.json'
$window=[pscustomobject]@{IsVisible=$false}
$bubbleBox=[pscustomobject]@{Visibility='Collapsed'}
$tray=[pscustomobject]@{Visible=$true;Fail=$false;Notices=(New-Object Collections.Generic.List[object])}
$tray|Add-Member ScriptMethod ShowBalloonTip {
  param($timeout,$title,$body,$icon)
  if($this.Fail){throw 'test notification failure'}
  [void]$this.Notices.Add(@{title=$title;body=$body})
}
function Reset-Model{
  $script:preferences=Get-PetPreferenceDefaults
  $script:preferences.displayMode='native';$script:preferences.petName='小鲸';$script:preferences.userName='搭子'
  $script:preferences.quiet=$true;$script:preferences.breakReminders=$false
  $script:companion=@{version=1;tasks=@();reminders=@();focus=$null;focusNotice=$null;focusCompletedCount=0}
  $script:stats=@{focusSessions=0};$script:focusUntil=$null;$script:focusMinutes=5
  $script:pending=$null;$script:away=$false;$script:gentleReminder='';$script:gentleReminderRaw=$false
  $script:breakNextAt=[DateTime]::Now.AddMinutes(50);$script:bubbleCount=0
  $tray.Notices.Clear();$tray.Visible=$true;$tray.Fail=$false;$window.IsVisible=$false
  Save-CompanionData
}
function Queue-Command([string]$action,$extra=@{}){
  $id=[Guid]::NewGuid().ToString('D')
  $command=@{id=$id;at=Get-PetUtcMs;action=$action}
  foreach($key in $extra.Keys){$command[$key]=$extra[$key]}
  Write-PetJson (Join-Path (Join-Path $TestHome 'commands') ($id+'.json')) $command
  return $id
}
function Get-Receipt([string]$id){Read-PetJson (Join-Path (Join-Path $TestHome 'command-results') ($id+'.json'))}

Reset-Model
$sayId=Queue-Command 'say' @{text='一起慢慢来'}
Process-PetCommands $TestHome
Assert ((Get-Receipt $sayId).status -eq 'completed' -and $tray.Notices.Count -eq 1 -and -not $window.IsVisible -and -not $script:bubbleCount) 'native requested speech uses the notification channel without showing the old pet'
Assert ($tray.Notices[0].title -match '小鲸' -and $tray.Notices[0].body -eq '一起慢慢来') 'notification preserves the saved pet name and exact requested message'
$script:away=$true;$awayId=Queue-Command 'say' @{text='等回来再说'}
Process-PetCommands $TestHome
Assert (-not (Get-Receipt $awayId) -and $tray.Notices.Count -eq 1) 'native speech stays queued while away'
$script:away=$false;Process-PetCommands $TestHome
Assert ((Get-Receipt $awayId).status -eq 'completed' -and $tray.Notices.Count -eq 2) 'native speech resumes after the user returns'
$script:preferences.displayMode='desktop';$hiddenId=Queue-Command 'say' @{text='普通隐藏不要打扰'}
Process-PetCommands $TestHome
Assert (-not (Get-Receipt $hiddenId) -and $tray.Notices.Count -eq 2) 'ordinary hidden support mode keeps the prior delayed-speech rule'
$script:preferences.displayMode='native';Process-PetCommands $TestHome

Reset-Model
$reminder=Add-PetReminder $script:companion '去喝水' 1 ([DateTime]::Now.AddMinutes(-2));Save-CompanionData
Update-Companion ([DateTime]::Now)
Assert ($tray.Notices.Count -eq 1 -and $tray.Notices[0].body -match '搭子.*去喝水' -and (Read-PetJson $companionFile).reminders[0].notified -and -not $window.IsVisible) 'native saved reminder delivers with the fixed user name and is acknowledged'
Update-Companion ([DateTime]::Now)
Assert ($tray.Notices.Count -eq 1) 'delivered reminders do not repeat on each maintenance tick'
$retry=Add-PetReminder $script:companion '失败后重试' 1 ([DateTime]::Now.AddMinutes(-2));Save-CompanionData
$tray.Fail=$true;Update-Companion ([DateTime]::Now)
Assert (-not @((Read-PetJson $companionFile).reminders|Where-Object{$_.id -eq $retry.id})[0].notified) 'notification failure does not falsely acknowledge the saved reminder'
$tray.Fail=$false;Update-Companion ([DateTime]::Now)
Assert ($tray.Notices.Count -eq 2 -and @((Read-PetJson $companionFile).reminders|Where-Object{$_.id -eq $retry.id})[0].notified) 'failed native reminder can deliver on a subsequent tick'

Reset-Model
$script:companion.focus=@{minutes=5;until=[DateTime]::Now.AddSeconds(-1).ToUniversalTime().ToString('o')}
$script:focusUntil=[DateTime]::Now.AddSeconds(-1);Save-CompanionData
Update-Companion ([DateTime]::Now)
Assert ($tray.Notices.Count -eq 1 -and -not $script:companion.focusNotice -and $script:companion.focusCompletedCount -eq 1 -and -not $window.IsVisible) 'native focus completion notifies once and acknowledges the persisted notice'
Update-Companion ([DateTime]::Now)
Assert ($tray.Notices.Count -eq 1) 'native focus completion is not repeatedly announced'
$script:preferences.breakReminders=$true;$script:breakNextAt=[DateTime]::Now.AddSeconds(-1)
Update-Companion ([DateTime]::Now)
Assert ($tray.Notices.Count -eq 1 -and -not $script:gentleReminder) 'background native mode does not turn ambient break activity into notifications'
$script:gentleReminder='之前排队的休息提醒';Show-GentleReminder
Assert (-not $script:gentleReminder -and $tray.Notices.Count -eq 1) 'switching to native mode drops ambient break text instead of blocking saved reminders'

Reset-Model
Start-Focus 5
$deadline=[string]$script:companion.focus.until
$duplicate=Queue-Command 'focus' @{minutes=25};Process-PetCommands $TestHome
Assert ((Get-Receipt $duplicate).status -eq 'failed' -and $script:companion.focus.minutes -eq 5 -and $script:companion.focus.until -eq $deadline) 'starting another focus fails honestly and preserves the running timer'
$pause=Queue-Command 'pause_focus';Process-PetCommands $TestHome
Assert ((Get-Receipt $pause).status -eq 'completed' -and $script:companion.focus.paused -and -not $script:focusUntil) 'native focus can pause through the same command queue'
$pausedSeconds=$script:companion.focus.remainingSeconds
$pausedDuplicate=Queue-Command 'focus' @{minutes=25};Process-PetCommands $TestHome
Assert ((Get-Receipt $pausedDuplicate).status -eq 'failed' -and $script:companion.focus.paused -and $script:companion.focus.remainingSeconds -eq $pausedSeconds) 'starting another focus also fails honestly while paused'
$resume=Queue-Command 'resume_focus';Process-PetCommands $TestHome
Assert ((Get-Receipt $resume).status -eq 'completed' -and $script:focusUntil -and -not $script:companion.focus.paused) 'native focus resumes the retained time through the same queue'

Reset-Model
$script:bubbleUntil=$null
$newsCall=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Extent.Text -match '^\$newsItem\s*=\s*Invoke-WhaleNewsTick\b'},$true)
if(-not $newsCall){throw 'News scheduler invocation was not found.'}
$newsInvocation=[scriptblock]::Create($newsCall.Extent.Text)
$now=[DateTime]::Today.AddHours(12)
$nowMs=[DateTimeOffset]::new($now).ToUnixTimeMilliseconds()
$newsItems=@(
  @{id='native-news-1';title='新的人工智能研究';sourceId='mit-ai';url='https://news.mit.edu/2026/native-test-1';topics=@('ai');publishedAt=$now.ToUniversalTime().ToString('o')},
  @{id='native-news-2';title='另一条研究消息';sourceId='mit-ai';url='https://news.mit.edu/2026/native-test-2';topics=@('ai');publishedAt=$now.ToUniversalTime().ToString('o')}
)
Write-PetJson (Join-Path $TestHome 'news.json') @{lastFetchedAt=$now.ToUniversalTime().ToString('o');items=$newsItems}
function Reset-NewsSchedule{
  Write-PetJson (Join-Path $TestHome 'news-schedule.json') @{version=1;day=$now.ToString('yyyy-MM-dd');sharedToday=0;seen=@();nextShareAt=$nowMs-1;nextRefreshAt=$nowMs+60000;lastRefreshResultAt=0}
}
Reset-NewsSchedule
$script:preferences.displayMode='desktop';. $newsInvocation
Assert (-not $newsItem) 'ordinary hidden mode still blocks automatic news'
$script:preferences.displayMode='native';. $newsInvocation
Assert ($newsItem -and (Read-PetJson (Join-Path $TestHome 'news-schedule.json')).sharedToday -eq 1) 'actual main-loop scheduler allows fresh selected news in native mode'
Show-PetNewsNotice $newsItem
Assert ($tray.Notices.Count -eq 1 -and $tray.Notices[0].body -match '搭子.*研究.*新闻面板' -and -not $window.IsVisible -and -not $script:bubbleCount) 'native news is delivered by notification with a usable source-panel instruction'
$script:preferences.newsDailyLimit=1
$schedule=Read-PetJson (Join-Path $TestHome 'news-schedule.json');$schedule.nextShareAt=$nowMs-1
Write-PetJson (Join-Path $TestHome 'news-schedule.json') $schedule
. $newsInvocation
Assert (-not $newsItem) 'native news keeps the existing daily share limit'
Reset-NewsSchedule;$now=[DateTime]::Today.AddHours(23);. $newsInvocation
Assert (-not $newsItem) 'native news keeps the nighttime quiet period'
$now=[DateTime]::Today.AddHours(12);Reset-NewsSchedule;$script:away=$true;. $newsInvocation
Assert (-not $newsItem) 'native news stays quiet while away'
$script:away=$false;Reset-NewsSchedule;$script:focusUntil=$now.AddMinutes(10);. $newsInvocation
Assert (-not $newsItem) 'native news stays quiet during a focus session'
$script:focusUntil=$null;Reset-NewsSchedule;$script:pending=@{id='pending'};. $newsInvocation
Assert (-not $newsItem) 'native news stays quiet while input is pending'
$script:pending=$null;Reset-NewsSchedule;$script:preferences.newsEnabled=$false;. $newsInvocation
Assert (-not $newsItem) 'native news respects the disabled sharing preference'
function Start-WhaleNewsRefresh{param([string]$PetHome);return $false}
function Test-WhaleNewsRefreshing{param([string]$PetHome);return $script:testRefreshRunning}
$script:testRefreshRunning=$false
$failedRefresh=Queue-Command 'refresh_news';Process-PetCommands $TestHome
Assert ((Get-Receipt $failedRefresh).status -eq 'failed' -and (Get-Receipt $failedRefresh).error -match '没有启动') 'refresh receipt fails when no worker started or is running'
$script:testRefreshRunning=$true
$runningRefresh=Queue-Command 'refresh_news';Process-PetCommands $TestHome
Assert ((Get-Receipt $runningRefresh).status -eq 'completed' -and (Get-Receipt $runningRefresh).message -match '进行中' -and (Get-Receipt $runningRefresh).message -notmatch '完成') 'already-running refresh acknowledges the request without claiming fetched news'
'NATIVE_NOTIFICATIONS_PASSED='+$script:passed
