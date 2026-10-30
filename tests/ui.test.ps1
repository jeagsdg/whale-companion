$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
$source = Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-pet.ps1'
. (Join-Path (Split-Path $source -Parent) 'whale-companion.ps1')
. (Join-Path (Split-Path $source -Parent) 'whale-companion-ui.ps1')
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$script:passed = 0
function Assert($condition, [string]$name) { if (-not $condition) { throw ('FAIL: ' + $name) }; $script:passed++; 'PASS: ' + $name }
foreach ($name in @('Read-Record','Load-Pose','Show-Pose','Restore-Pose','Say','Test-Calm','Get-RpsOutcome','Invoke-PetRps','Update-SignIn','Update-Companion','Start-Focus','Cancel-Focus','Show-GentleReminder','Get-ApprovalKey','Test-ApprovalLive','Clear-Pending','Update-PetState','Submit-PetDecision','Read-Json','Write-Json','Remember','Set-Quiet','Set-BreakReminders','Add-PetCatalogMenu','Show-CatalogSticker','Show-PetMood')) {
  $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
  . ([scriptblock]::Create($fn.Extent.Text))
}
function petLog($m) {}
function Update-Tray {}
function Save-Preferences {}
function Read-PetJson($path) { if ($script:fixtures.ContainsKey($path)) { return $script:fixtures[$path] }; return $null }
function Write-PetJson($path, $value) { if ($script:failWrite) { throw 'test write failure' }; $script:writes += @{ path = $path; value = $value } }
function Get-PetDecisionPath($root, $client, $id) { return (Join-Path $root ('decisions\' + $client + '\' + $id + '.json')) }
function Save-Stats {}
function Add-Xp($n, $why) { $script:xpAwarded += $n }
function Pick-Line($key) { return $key }
$script:fixtures = @{}
$script:writes = @()
$script:failWrite = $false
$PetHome = Join-Path $PSScriptRoot '..\packages\desktop-pet'
$script:preferences = Get-PetPreferenceDefaults
$script:preferences.host = 'dsh'
$script:companion = @{ tasks = @(); reminders = @(); focus = $null }
$companionFile = 'companion-data.json'
$script:focusMinutes = 25
$script:cache = @{}
$script:lastPose = ''
$script:decidedIds = @{}
$script:stats = @{ approvals = 0; focusSessions = 0; streak = 4; lastDay = '2026-10-13' }
$script:mem = @{ project = ''; lastProject = ''; lastSeen = '' }
$memFile = 'memory.json'
$script:xpAwarded = 0
$script:nightMode = $false
$script:away = $false
$script:pending = $null
$script:focusUntil = $null
$script:gentleReminder = ''
$script:breakNextAt = [DateTime]::Now.AddMinutes(50)
$script:lastLine = ''
$window = [pscustomobject]@{ IsVisible = $true }
$image = New-Object System.Windows.Controls.Image
$card = New-Object System.Windows.Controls.Border
$bubbleBox = New-Object System.Windows.Controls.StackPanel
$bubbleText = New-Object System.Windows.Controls.TextBlock
$bubbleNameText = New-Object System.Windows.Controls.TextBlock
$headText = New-Object System.Windows.Controls.TextBlock
$cardTool = New-Object System.Windows.Controls.TextBlock
$cardReason = New-Object System.Windows.Controls.TextBlock
$btnGo = New-Object System.Windows.Controls.Button
$btnYes = New-Object System.Windows.Controls.Button
$btnNo = New-Object System.Windows.Controls.Button
$miQuiet = New-Object System.Windows.Forms.ToolStripMenuItem
$miBreak = New-Object System.Windows.Forms.ToolStripMenuItem
$miWalk = New-Object System.Windows.Forms.ToolStripMenuItem
$miShow = New-Object System.Windows.Forms.ToolStripMenuItem

foreach ($target in @('btnYes', 'btnNo')) {
  $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq ('$' + $target) -and $n.Member.Value -eq 'Add_Click' }, $true)
  (Get-Variable $target -ValueOnly).Add_Click($node.Arguments[0].ScriptBlock.GetScriptBlock())
}
function New-Approval([string]$id, [string]$client = 'client-A') { return @{ id = $id; clientId = $client; sessionId = 'session-A'; requestId = 'request-A'; tool = 'Test'; reason = '隔离审批'; expiresAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 60000 } }
$script:pending = New-Approval 'yes-A'
$btnYes.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert ($script:writes.Count -eq 1 -and $script:writes[0].value.outcome -eq 'allowed-once') '允许按钮独立提交一次'
Assert ($script:writes[0].value.clientId -eq 'client-A' -and $script:writes[0].value.sessionId -eq 'session-A' -and $script:writes[0].value.requestId -eq 'request-A') '裁决保留完整请求身份'
$script:writes = @(); $script:pending = New-Approval 'no-A'
$btnNo.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert ($script:writes.Count -eq 1 -and $script:writes[0].value.outcome -eq 'rejected') '拒绝按钮独立提交一次'
$script:writes = @(); $script:pending = New-Approval 'write-fail'; $script:failWrite = $true
Submit-PetDecision 'allowed-once'
Assert ($script:pending.id -eq 'write-fail' -and $script:writes.Count -eq 0) '裁决落盘失败仍保留原牌'
$script:failWrite = $false
$script:pending = @{ id = 'legacy-no-identity' }
Submit-PetDecision 'allowed-once'
Assert ($script:writes.Count -eq 0) '缺客户端身份的旧牌禁止裁决'

$now = [DateTime]::Now
$live = New-Approval 'state-A'
Update-PetState @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); approval = $live; approvalCount = 2; line = 'ordinary' } $now
Assert ($script:pending.id -eq 'state-A' -and $headText.Text -match '2' -and $bubbleBox.Visibility -eq 'Collapsed') '审批优先于气泡并显示队列数量'
$live.reason = 'renewed'
Update-PetState @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 80000; approval = $live } $now
Assert ($script:pending.id -eq 'state-A' -and $cardReason.Text -eq 'renewed') '审批有效期优先于普通状态75秒过期'
$live.expiresAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 1
Update-PetState $null $now
Assert ($null -eq $script:pending) '审批到期后收牌'
Update-PetState @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 80000; approval = @{ id = 'legacy-A'; clientId = 'client-A' } } $now
Assert ($script:pending.id -eq 'legacy-A') '旧协议75秒后仍享有150秒宽限'
Update-PetState @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 226000; approval = @{ id = 'legacy-B'; clientId = 'client-A' } } $now
Assert ($null -eq $script:pending) '旧协议宽限到期后收牌'
Update-PetState @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); approval = (New-Approval 'cancel-A') } $now
Update-PetState @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); approval = $null } $now
Assert ($null -eq $script:pending) '服务端明确取消后立即收牌'
$script:pending = $null
$script:preferences.host = 'codex'
$codexApproval = New-Approval 'cannot-act'
Update-PetState @{ host = 'codex'; kind = 'approval'; sid = 'thread-12345678'; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); approval = $codexApproval } $now
Assert ($script:pending.notificationOnly -and $btnYes.Visibility -eq 'Collapsed' -and $btnNo.Visibility -eq 'Collapsed' -and $btnGo.Visibility -eq 'Visible') 'Codex权限提示只提供原会话入口'
$script:writes = @(); Submit-PetDecision 'allowed-once'
Assert ($script:writes.Count -eq 0) 'Codex信息牌绝不写入裁决'
Update-PetState @{ host = 'codex'; kind = 'question'; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 80000 } $now
Assert ($script:pending.notificationOnly) 'Codex等待选择的牌超过75秒仍显示'
Update-PetState @{ host = 'codex'; kind = 'completion'; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() } $now
Assert ($null -eq $script:pending) 'Codex完成后撤掉通知牌'
Update-PetState @{ host = 'dsh'; approval = (New-Approval 'wrong-host'); at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() } $now
Assert ($null -eq $script:pending) 'Codex模式忽略DSH审批'

$beats = @{ '石头' = '剪刀'; '剪刀' = '布'; '布' = '石头' }
foreach ($pick in @('石头', '剪刀', '布')) {
  foreach ($her in @('石头', '剪刀', '布')) {
    $expected = if ($pick -eq $her) { 'draw' } elseif ($beats[$pick] -eq $her) { 'win' } else { 'lose' }
    Assert ((Get-RpsOutcome $pick $her) -eq $expected) ('猜拳 ' + $pick + '/' + $her)
  }
}
$script:lastPose = 'idle'
$image.Source = Load-Pose 'idle'
Show-Pose 'react-head' -1
Restore-Pose @{ pose = 'idle' } ([DateTime]::Now)
Assert ([object]::ReferenceEquals($image.Source, (Load-Pose 'idle'))) '临时姿态到期后恢复同名基础姿态'
Show-Pose 'react-head' -1
Restore-Pose $null ([DateTime]::Now)
Assert ($script:lastPose -eq 'idle') '没有state文件也恢复基础姿态'
foreach ($pair in @(@('success','ok'),@('failure','err'),@('meme-heart','valentine'),@('meme-shock','meme-omg'),@('idle-cute','idle'),@('waiting','wait'),@('meme-music','daily-gaming'),@('celebrate','game-happy'),@('meme-broke','daily-melt'),@('meme-no','no'),@('meme-yes','ok'))) {
  Assert ([object]::ReferenceEquals((Load-Pose $pair[0]), (Load-Pose $pair[1]))) ('贴纸别名 ' + $pair[0])
}
$script:fixtures['old-memory'] = ('{"project":"旧项目","visits":7,"lastSeen":"''; lastProject = ''"}' | ConvertFrom-Json)
$script:mem = Read-Record 'old-memory' @{ project = ''; visits = 0; lastSeen = ''; lastProject = '' }
Remember '新项目'
Assert ($script:mem.lastProject -eq '旧项目' -and $script:mem.project -eq '新项目' -and $script:mem.visits -eq 7) '旧记忆补齐字段并保留数据'
$script:fixtures['old-stats'] = ('{"pats":44,"level":3}' | ConvertFrom-Json)
$record = Read-Record 'old-stats' @{ pats = 0; level = 1; bubbles = 0; focusSessions = 0 }
Assert ($record.pats -eq 44 -and $record.level -eq 3 -and $record.ContainsKey('focusSessions')) '旧养成数据保留并补齐新字段'
Update-SignIn ([DateTime]'2026-10-14T00:00:01')
Update-SignIn ([DateTime]'2026-10-14T23:59:59')
Update-SignIn ([DateTime]'2026-10-15T00:00:01')
Assert ($script:stats.streak -eq 6 -and $script:xpAwarded -eq 10) '跨午夜签到连续累计且每天只奖励一次'

$bubbleBox.Visibility = 'Collapsed'
Say 'ambient suppressed' 1000 -Ambient
Assert ($bubbleBox.Visibility -eq 'Collapsed') '安静模式抑制主动气泡'
Say 'manual response' 1000
Assert ($bubbleText.Text -eq 'manual response' -and $bubbleBox.Visibility -eq 'Visible') '安静模式仍响应手动交互'
Start-Focus
Assert ($script:focusUntil -and (Test-Calm)) '25分钟专注开始且进入安静状态'
$oldDeadline = $script:focusUntil
Start-Focus
Assert ($oldDeadline -eq $script:focusUntil) '重复开始不会重置正在进行的专注'
Cancel-Focus
Assert ($null -eq $script:focusUntil -and $script:stats.focusSessions -eq 0) '取消专注不记完成'
Start-Focus; $script:focusUntil = [DateTime]::Now.AddSeconds(-1)
$script:pending = New-Approval 'during-focus'; Update-Companion ([DateTime]::Now)
Assert ($script:gentleReminder -and $script:stats.focusSessions -eq 1) '专注完成提醒延后到审批后且只记录一次'
$script:pending = $null; $window.IsVisible = $false
Update-Companion ([DateTime]::Now)
Assert ([bool]$script:gentleReminder) '隐藏时不弹出专注提醒'
$window.IsVisible = $true; Update-Companion ([DateTime]::Now)
Assert (-not $script:gentleReminder -and $bubbleText.Text -match '25 分钟') '显示后温和提醒且不抢焦点'
$script:breakNextAt = [DateTime]::Now.AddSeconds(-1)
Update-Companion ([DateTime]::Now)
Assert (-not $script:gentleReminder) '休息提醒默认关闭'
Set-BreakReminders $true; $script:breakNextAt = [DateTime]::Now.AddSeconds(-1)
Update-Companion ([DateTime]::Now)
Assert ($bubbleText.Text -match '伸个懒腰') '休息提醒开启后按时提示'

$script:preferences.petName = '小泡'; $script:preferences.userName = '阿宁'
Say '鲸鱼娘和主人都在，给你加油。' 1000
Assert ($bubbleText.Text -eq '小泡和阿宁都在，给阿宁加油。') '旧台词和固定称呼一致替换'
Say '新闻：鲸鱼娘，你不知道的故事' 1000 -Raw
Assert ($bubbleText.Text -eq '新闻：鲸鱼娘，你不知道的故事') '外部标题原样显示不会误改称呼'
Assert ((ConvertTo-PetSingleLine "阿宁`r`n同学" 24) -eq '阿宁 同学') '称呼去掉换行'
$badPreferences = Repair-PetPreferences @{ petName = ''; userName = ('啊' * 25); focusMinutes = -8; newsTopics = @('invalid'); newsMinMinutes = 100; newsMaxMinutes = 60 }
Assert ($badPreferences.petName -eq '鲸鱼娘' -and $badPreferences.userName -eq '你' -and $badPreferences.focusMinutes -eq 25 -and $badPreferences.newsMaxMinutes -eq 100 -and $badPreferences.host -eq 'codex') '坏配置修复边界并默认Codex'
$script:preferences.focusMinutes = 7; Start-Focus
Assert (($script:focusUntil - [DateTime]::Now).TotalMinutes -gt 6.9 -and $script:companion.focus.minutes -eq 7) '可配置7分钟专注保存恢复信息'
Cancel-Focus
$task = Add-PetTask $script:companion "写计划`n拆小步"
Assert ($task.text -eq '写计划 拆小步' -and (Set-PetTaskDone $script:companion $task.id) -and $script:companion.tasks[0].done) '持久待办model增删完成'
Remove-PetTask $script:companion $task.id
Assert ($script:companion.tasks.Count -eq 0) '删除待办'
$reminderA = Add-PetReminder $script:companion '喝水' 5 $now.AddMinutes(-8)
$reminderB = Add-PetReminder $script:companion '新闻里写鲸鱼娘和你' 5 $now.AddMinutes(-7)
$script:away = $true; Update-Companion $now
Assert (-not $reminderA.notified -and -not $reminderB.notified) '离开时到期提醒不弹也不丢失'
$script:away = $false; Update-Companion $now
Assert (@($script:companion.reminders|Where-Object{$_.notified}).Count -eq 2 -and $bubbleText.Text -eq '阿宁，之前记下的提醒到啦：喝水；新闻里写鲸鱼娘和你') '回归后多个提醒合并一次且保留用户原文'

$upNode = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq '$image' -and $n.Member.Value -eq 'Add_MouseLeftButtonUp' }, $true)
$upHandler = $upNode.Arguments[0].ScriptBlock.GetScriptBlock()
$script:stats.clicks = 0; $script:dragged = $false; $script:skipClick = $false; $script:rapid = 0
for ($i = 0; $i -lt 9; $i++) { $script:rapidSince = [DateTime]::Now.AddSeconds(-3); . $upHandler }
Assert ($script:rapid -eq 1 -and $script:stats.clicks -eq 9) '实际点击回调按2.5秒窗口重置连点'
for ($i = 0; $i -lt 5; $i++) { . $upHandler }
Assert ($script:rapid -eq 6) '实际点击回调仍累计窗口内连点'

function Unlock($id, $pose, $line) {}
$script:stats.pats = 0; $script:stats.rpsWin = 0; $script:stats.rpsLose = 0; $script:stats.rpsStreak = 0; $script:stats.level = 1
$menuNode = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq '$image' -and $n.Member.Value -eq 'Add_MouseRightButtonUp' }, $true)
$menuBody = $menuNode.Arguments[0].ScriptBlock.Extent.Text
$menuBody = $menuBody.Substring(1, $menuBody.Length - 2).Replace('$cm.IsOpen = $true', '')
. ([scriptblock]::Create($menuBody))
$gameMenu = @($cm.Items | Where-Object { $_.Header -eq '猜拳 ✊✌✋' })[0]
Assert (@($cm.Items | Where-Object { $_.Header -eq '戳泡泡 🫧' }).Count -eq 1) '真实WPF右键菜单只添加一次泡泡项'
function Get-Random { return '剪刀' }
$gameMenu.Items[0].RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.MenuItem]::ClickEvent)))
Assert ($script:stats.rpsWin -eq 1 -and $script:stats.rpsLose -eq 0 -and $script:stats.rpsStreak -eq 1) '实际猜拳菜单事件正确记录用户胜利'
Remove-Item Function:\Get-Random
$quietItem.IsChecked = $false
$quietItem.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.MenuItem]::ClickEvent)))
Assert (-not $script:preferences.quiet) '右键安静模式开关事件确实更新设置'
$breakItem.IsChecked = $false
$breakItem.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.MenuItem]::ClickEvent)))
Assert (-not $script:preferences.breakReminders) '右键休息提醒开关事件确实更新设置'

$raw = [System.IO.File]::ReadAllText($source)
Assert ($raw -notmatch '\$image\.Add_MouseDoubleClick' -and $raw -match '\$eventArgs\.ClickCount -ge 2') 'Image双击使用支持的ClickCount事件'
Assert ($raw -notmatch '\$window\.Activate\(' -and $raw -match '\$window.ShowActivated = \$false') '后台显示不会激活或抢焦点'
Assert ($raw -notmatch '\$window\.ShowDialog\(' -and $raw -match '\$app.Run\(\$window\)') '隐藏窗口不结束UI消息循环'
$bytes = [System.IO.File]::ReadAllBytes($source)
Assert ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) '源脚本保留UTF8 BOM'

. (Join-Path (Split-Path $source -Parent) 'whale-pet-common.ps1')
$probeHome = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) '.diag') ('ui-home-' + [Guid]::NewGuid().ToString('N'))
$created = $false
$probeMutex = New-Object System.Threading.Mutex($true, (Get-PetMutexName 'UI' $probeHome), [ref]$created)
$duplicateCreated = $false
$duplicateMutex = New-Object System.Threading.Mutex($true, (Get-PetMutexName 'UI' $probeHome), [ref]$duplicateCreated)
Assert ($created -and -not $duplicateCreated) '命名mutex准确拒绝同目录第二个UI'
$duplicateMutex.Dispose(); $probeMutex.ReleaseMutex(); $probeMutex.Dispose()
$path = Get-PetDecisionPath $probeHome 'client/中文' 'id/中文'
Write-PetJson $path @{ clientId = 'client/中文'; id = 'id/中文'; outcome = 'rejected' }
$diskValue = Read-PetJson $path
Assert ($diskValue.clientId -eq 'client/中文' -and $diskValue.id -eq 'id/中文' -and $path -match '[0-9a-f]{64}\\[0-9a-f]{64}\.json$') '真实原子写路径使用身份哈希且中文裁决可读回'
Write-PetJson $path @{ clientId = 'client/中文'; id = 'id/中文'; outcome = 'allowed-once' }
$diskValue = Read-PetJson $path
Assert ($diskValue.outcome -eq 'allowed-once') '同一JSON第二次原子替换真实落盘'

# Initialize the actual UI source with a disposable data directory and no visible tray.
$PetHome = $probeHome
$initStart = $raw.IndexOf('$ErrorActionPreference = ''Continue''')
$initEnd = $raw.IndexOf('# ---------- animation loop ----------')
$initSource = $raw.Substring($initStart, $initEnd - $initStart).Replace('$tray.Visible = $true', '$tray.Visible = $false').Replace('$companionModuleRoot = $PSScriptRoot', '$companionModuleRoot = [IO.Path]::GetDirectoryName($source)')
. ([scriptblock]::Create($initSource))
Assert ($window -is [System.Windows.Window] -and $buttons -is [System.Windows.Controls.WrapPanel] -and -not $window.IsVisible -and -not $tray.Visible) '完整UI控件和数据初始化成功且全程无可见窗口托盘'
Assert ((Read-PetJson (Join-Path $probeHome 'pet-preferences.json')).quiet -and -not (Read-PetJson (Join-Path $probeHome 'pet-preferences.json')).breakReminders) '初始preferences真实落盘：安静开启、休息提醒关闭'
$settingsProbe = New-PetSettingsWindow
Assert (-not $settingsProbe.IsVisible -and $settingsProbe.Tag.controls.petName.Text -eq '鲸鱼娘') '设置表单真实构造且不会自动显示'
$settingsProbe.Tag.controls.petName.Text = '泡泡'; $settingsProbe.Tag.controls.userName.Text = '搭子'
$settingsProbe.Tag.controls.focus.Text = '11'
$settingsProbe.Tag.save.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
$savedPrefs = Read-PetJson $preferencesFile
Assert ($savedPrefs.petName -eq '泡泡' -and $savedPrefs.userName -eq '搭子' -and $savedPrefs.focusMinutes -eq 11 -and $window.Title -match '泡泡') '真实设置保存事件持久化称呼与时间并更新窗口名'
$settingsProbe.Tag.controls.focus.Text = '181'; $settingsProbe.Tag.controls.petName.Text = '不能保存'
$settingsProbe.Tag.save.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert ((Read-PetJson $preferencesFile).petName -eq '泡泡' -and $settingsProbe.Tag.controls.status.Text -match '5 到 180') '无效配置校验后不会部分保存'
$settingsProbe.Tag.controls.focus.Text='11';$settingsProbe.Tag.controls.petName.Text='泡泡'
$displayModeCalls=New-Object Collections.Generic.List[string]
$savedDisplayModeCommand=Get-Command Set-PetDisplayMode -ErrorAction SilentlyContinue
function Set-PetDisplayMode([string]$Mode){$displayModeCalls.Add($Mode)}
$settingsProbe.Tag.controls.displayMode.SelectedIndex=1
$settingsProbe.Tag.save.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
$settingsProbe.Tag.save.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ((Read-PetJson $preferencesFile).displayMode -eq 'native' -and $displayModeCalls.Count -eq 1 -and $displayModeCalls[0] -eq 'native') '原生模式持久保存且重复保存设置不重复显示宠物'
$settingsProbe.Tag.controls.displayMode.SelectedIndex=0
$settingsProbe.Tag.save.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
if($savedDisplayModeCommand){Set-Item Function:\Set-PetDisplayMode -Value $savedDisplayModeCommand.ScriptBlock}else{Remove-Item Function:\Set-PetDisplayMode}
$taskProbe = New-PetTasksWindow
$taskProbe.Tag.controls.newTask.Text = '用户主动写的一件事'
$taskProbe.Tag.add.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert ((Read-PetJson $companionFile).tasks[0].text -eq '用户主动写的一件事' -and -not $taskProbe.IsVisible) '真实待办添加事件落盘且无需显示窗口'
$taskProbe.Tag.controls.tasks.SelectedIndex = 0
$taskProbe.Tag.done.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert ((Read-PetJson $companionFile).tasks[0].done) '真实待办完成事件落盘'
$taskProbe.Tag.controls.newReminder.Text = '按时喝水'
$taskProbe.Tag.controls.minutes.Text = '5'
$taskProbe.Tag.remind.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert ((Read-PetJson $companionFile).reminders[0].text -eq '按时喝水') '真实一次性提醒事件落盘'
$commandDirectory = Join-Path $probeHome 'commands'
function New-TestCommand([string]$Action, [string]$Text = '', [int]$Minutes = 0) {
  $id = [Guid]::NewGuid().ToString()
  $value = @{ id = $id; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); action = $Action; text = $Text; minutes = $Minutes }
  Write-PetJson (Join-Path $commandDirectory ($id + '.json')) $value
  return $value
}
$command = New-TestCommand 'add_todo' 'Codex帮我记的事'
Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\' + $command.id + '.json'))).status -eq 'completed' -and @((Read-PetJson $companionFile).tasks).Count -eq 2) 'Codex待办命令真实处理并回执落盘'
Write-PetJson (Join-Path $commandDirectory ($command.id + '.json')) $command
Process-PetCommands $probeHome
Assert (@((Read-PetJson $companionFile).tasks).Count -eq 2) '重复同一Codex命令不会重复添加'
$script:realWritePetJson = (Get-Command Write-PetJson).ScriptBlock
$script:failResultWrites = 1
$script:failDataWrites = 0
Set-Item -LiteralPath 'Function:\Write-PetJson' -Value { param([string]$Path, $Value)
  if ($script:failResultWrites -gt 0 -and $Path -match '[\\/]command-results[\\/]') {
    $script:failResultWrites--; throw '模拟回执写入暂时失败'
  }
  if ($script:failDataWrites -gt 0 -and $Path -eq $companionFile) {
    $script:failDataWrites--; throw '模拟陪伴数据写入失败'
  }
  & $script:realWritePetJson $Path $Value
}
$retryCommand = New-TestCommand 'add_todo' '回执失败但不能重复的待办'
Process-PetCommands $probeHome
$retryInbox = Join-Path $commandDirectory ($retryCommand.id + '.json')
$retryResult = Join-Path $probeHome ('command-results\' + $retryCommand.id + '.json')
Assert ((Test-Path -LiteralPath $retryInbox) -and -not (Test-Path -LiteralPath $retryResult) -and $script:handledCommands[$retryCommand.id].status -eq 'completed') '回执写失败保留命令与完整结果供下次重试'
Process-PetCommands $probeHome
Assert (-not (Test-Path -LiteralPath $retryInbox) -and (Read-PetJson $retryResult).status -eq 'completed' -and @((Read-PetJson $companionFile).tasks).Count -eq 3 -and -not $script:handledCommands.ContainsKey($retryCommand.id)) '下一tick只重试回执不重做动作且完成后清理内存'
$script:failDataWrites = 1
$failedTaskCommand = New-TestCommand 'add_todo' '保存失败不能留在内存的事'
Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\' + $failedTaskCommand.id + '.json'))).status -eq 'failed' -and $script:companion.tasks.Count -eq 3 -and @((Read-PetJson $companionFile).tasks).Count -eq 3) '命令待办写失败时内存与磁盘都不提交条目'
$script:failDataWrites = 1
$failedReminderCommand = New-TestCommand 'remind' '不能冒出来的提醒' 5
Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\' + $failedReminderCommand.id + '.json'))).status -eq 'failed' -and $script:companion.reminders.Count -eq 1 -and @((Read-PetJson $companionFile).reminders).Count -eq 1) '命令提醒写失败时不会留下稍后意外触发的幽灵提醒'
Set-Item -LiteralPath 'Function:\Write-PetJson' -Value $script:realWritePetJson
$oldReceipt = Join-Path $probeHome 'command-results\old-completed.json'
$pendingReceipt = Join-Path $probeHome 'command-results\old-pending.json'
Write-PetJson $oldReceipt @{ status = 'completed' }
Write-PetJson $pendingReceipt @{ status = 'completed' }
Write-PetJson (Join-Path $commandDirectory 'old-pending.json') @{ action = 'say' }
[IO.File]::SetLastWriteTimeUtc($oldReceipt, [DateTime]::UtcNow.AddDays(-8))
[IO.File]::SetLastWriteTimeUtc($pendingReceipt, [DateTime]::UtcNow.AddDays(-8))
$script:commandCleanupDay = ''
Clear-OldPetCommandResults $probeHome ([DateTime]::Now)
Assert (-not (Test-Path -LiteralPath $oldReceipt) -and (Test-Path -LiteralPath $pendingReceipt)) '清理七天前完成回执但保留仍有待处理命令的回执'
Remove-Item -LiteralPath (Join-Path $commandDirectory 'old-pending.json') -Force
$invalidCommand = New-TestCommand 'execute_code' 'never run'
Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\' + $invalidCommand.id + '.json'))).status -eq 'failed') '命令白名单拒绝任意执行'
$sayCommand = New-TestCommand 'say' '这条消息应该等回来'
Process-PetCommands $probeHome
Assert ((Test-Path -LiteralPath (Join-Path $commandDirectory ($sayCommand.id + '.json'))) -and -not (Test-Path -LiteralPath (Join-Path $probeHome ('command-results\' + $sayCommand.id + '.json')))) '隐藏时Codex传话延后不唤醒'
Process-PetCommands $probeHome ([DateTime]::Now.AddMinutes(6))
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\' + $sayCommand.id + '.json'))).status -eq 'failed') '过期的传话清理回执防止返程消息轰炸'
$nameCommand = New-TestCommand 'set_names'
$nameCommand.petName = '小鲸'; $nameCommand.userName = '搭档'
Write-PetJson (Join-Path $commandDirectory ($nameCommand.id + '.json')) $nameCommand
Process-PetCommands $probeHome
Assert ((Read-PetJson $preferencesFile).petName -eq '小鲸' -and (Read-PetJson $preferencesFile).userName -eq '搭档') 'Codex称呼命令验证后保存两方昵称'
[void](New-TestCommand 'focus' '' 9); Process-PetCommands $probeHome
Assert ((Read-PetJson $companionFile).focus.minutes -eq 9 -and (Get-PetFocusDeadline (Get-PetCompanionData $companionFile))) 'Codex专注命令保存9分钟且重读可恢复'
[void](New-TestCommand 'cancel_focus'); Process-PetCommands $probeHome
Assert ($null -eq (Read-PetJson $companionFile).focus -and $null -eq $script:focusUntil) 'Codex取消专注命令同时清理运行与存储状态'
[void](New-TestCommand 'remind' '五分钟提醒' 5); Process-PetCommands $probeHome
Assert (@((Read-PetJson $companionFile).reminders).Count -eq 2) 'Codex提醒命令真实持久化'
$invalidFocus=New-TestCommand 'focus' '' -1;Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\'+$invalidFocus.id+'.json'))).status -eq 'failed' -and -not $script:focusUntil) '非法专注时长被拒绝而非悄悄改成默认值'
$settingsProbe.Tag.controls.autoWake.IsChecked=$false
$settingsProbe.Tag.controls.focus.Text='11';$settingsProbe.Tag.controls.petName.Text='小鲸'
$settingsProbe.Tag.save.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert (-not (Read-PetJson $preferencesFile).autoWakeOnHostStart) '自动唤醒开关真实持久化'
$settingsProbe.Tag.controls.autoWake.IsChecked=$true
$settingsProbe.Tag.save.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Start-Focus 5
$deadlineBeforeFailure=$script:focusUntil;$focusBeforeFailure=$script:companion.focus.until;$countBeforeFailure=[int]$script:stats.focusSessions
$savedJsonWriter=(Get-Item Function:\Write-PetJson).ScriptBlock
function Write-PetJson{throw 'injected disk failure'}
$failed=$false;try{Cancel-Focus}catch{$failed=$true}
Assert ($failed -and $script:focusUntil -eq $deadlineBeforeFailure -and $script:companion.focus.until -eq $focusBeforeFailure) '取消专注保存失败时保持内存和磁盘计时一致'
$script:focusUntil=[DateTime]::Now.AddSeconds(-1);$failed=$false
try{Update-Companion ([DateTime]::Now)}catch{$failed=$true}
Assert ($failed -and $script:companion.focus -and $script:stats.focusSessions -eq $countBeforeFailure) '专注完成保存失败时可重试且不重复计数'
Set-Item Function:\Write-PetJson -Value $savedJsonWriter
$script:pending=$null;$script:away=$false
Update-Companion ([DateTime]::Now)
$noticeReload=Get-PetCompanionData $companionFile
Assert ($noticeReload.focusNotice.minutes -eq 5 -and $noticeReload.focusCompletedCount -eq $countBeforeFailure+1 -and -not $noticeReload.focus) '隐藏期间完成的专注提醒和计数持久保存'
$script:companion=$noticeReload;$script:gentleReminder=''
Update-Companion ([DateTime]::Now)
Assert ($script:gentleReminder -and $script:companion.focusNotice) '重启模拟能恢复待显示专注提醒'
$realWindow=$window;$window=[PSCustomObject]@{IsVisible=$true};Show-GentleReminder;$window=$realWindow
Assert (-not (Read-PetJson $companionFile).focusNotice -and -not $script:gentleReminder) '专注提醒展示后确认并不再重播'
$catalogHome = $PetHome; $PetHome = Split-Path $source -Parent
$script:catalog = Read-PetJson (Join-Path $PetHome 'sticker-catalog.json')
$catalogProbe = New-Object System.Windows.Controls.ContextMenu
Add-PetCatalogMenu $catalogProbe
$catalogEntries = @($catalogProbe.Items|ForEach-Object{$_.Items}|ForEach-Object{$_.Items})
Assert ($catalogEntries.Count -eq 104 -and @($catalogEntries | Where-Object { $_.Header -match '^[a-z0-9-]+$' }).Count -eq 0) '新版12张和旧版92张均以中文标题接入且分开浏览'
Assert (@($catalogProbe.Items[0].Items|ForEach-Object{$_.Items}).Count -eq 12) '常用入口只展示新版精选表情'
$firstCurated=@($catalogProbe.Items[0].Items|ForEach-Object{$_.Items})[0]
$firstCurated.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.MenuItem]::ClickEvent)))
Assert ($script:forcedPose -eq $firstCurated.Tag.pose -and $bubbleText.Text -eq $firstCurated.Tag.caption) '真实菜单点击通过Tag选中表情而不创建额外闭包模块'
$selectedSticker = $script:catalog.stickers | Select-Object -First 1
Show-CatalogSticker $selectedSticker 5000
Assert ($bubbleText.Text -eq ([string]$selectedSticker.caption + ' · ' + [string]$selectedSticker.en)) '手动表情在安静模式下仍显示原字幕'
$script:preferences.petName='梁文峰';$script:preferences.userName='KK'
Show-PetMood 'low'
Assert ($script:forcedPose -eq 'v3-comfort' -and $bubbleText.Text -match '梁文峰' -and $bubbleText.Text -match 'KK') '低落反馈使用专用安慰表情并体现双方称呼'
Assert ($bubbleNameText.Text -eq '梁文峰 · 陪着 KK') '自定义称呼在气泡署名实际可见'
Show-PetMood 'happy';Assert ($script:forcedPose -eq 'v3-happy') '开心反馈不再使用旧游戏或得意姿态'
Show-PetMood 'anxious';Assert ($script:forcedPose -eq 'v3-calm') '焦虑反馈使用平静呼吸表情'
Show-PetMood 'tired';Assert ($script:forcedPose -eq 'v3-tired') '疲惫反馈使用抱枕休息表情'
$script:cache=@{};$script:poseCacheOrder=$null
foreach($pose in @($script:catalog.stickers|Select-Object -First 22)){$bitmap=Load-Pose $pose.pose}
Assert ($script:cache.Count -le 8 -and $bitmap.IsFrozen -and $bitmap.PixelWidth -le 320) '图片按显示尺寸解码冻结且缓存不超过八张'
$pngPath=Join-Path $PetHome 'assets\v3-comfort.png'
$clipboardData=New-PetStickerClipboardData $pngPath
$pngStream=$clipboardData.GetData('PNG',$false)
Assert ([Convert]::ToBase64String($pngStream.ToArray()) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($pngPath))) '复制使用原始透明PNG字节不混入窗口背景或字幕'
Assert ($clipboardData.GetDataPresent('image/png',$false) -and $clipboardData.GetDataPresent([Windows.DataFormats]::FileDrop,$false)) '剪贴板提供透明PNG和原图文件兼容格式'
$fallback=$clipboardData.GetImage();$corner=New-Object byte[] 4;$fallback.CopyPixels((New-Object Windows.Int32Rect(0,0,1,1)),$corner,4,0)
Assert ($fallback.PixelWidth -le 512) '旧粘贴格式控制分辨率避免复制占用大块内存'
Assert ($corner[0] -eq 255 -and $corner[1] -eq 255 -and $corner[2] -eq 255 -and $corner[3] -eq 255) '旧式粘贴目标使用纯白兼容底不会显示黑块'
$script:preferences.quiet=$false;$script:lastLine='';$script:lastLineContext=''
Update-PetState @{host='codex';kind='tool';note='鲸鱼娘和你';line='{user}，{pet}正在为「{project}」运行测试和验证。';at=Get-PetUtcMs} ([DateTime]::Now)
Assert ($bubbleText.Text -eq 'KK，梁文峰正在为「鲸鱼娘和你」运行测试和验证。') '工作反馈结合项目与阶段并保留项目原名'
$PetHome = $catalogHome
$newsProbe = New-PetNewsWindow
Assert (-not $newsProbe.IsVisible) '新闻收件箱手动构造不会拉起窗口或请求网络'
Assert ((Format-PetNewsTime '') -eq '来源未提供发布时间' -and (Format-PetNewsTime '2026-10-14T10:22:00+08:00') -match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}') '新闻缺失日期明确说明并将有效时间按本地格式展示'

# End-to-end workflow actions use the actual controls and real isolated files.
$script:companion=@{version=1;tasks=@();reminders=@();focus=$null;focusNotice=$null;focusCompletedCount=0}
$c=$taskProbe.Tag.controls
$c.newTask.Text='整理项目';Invoke-CompanionListAction 'add' $c
$c.newTask.Text='读一本书';Invoke-CompanionListAction 'add' $c
$c.tasks.SelectedIndex=0;Invoke-CompanionListAction 'done' $c
Assert ($script:companion.tasks[0].done -and $c.summary.Text -match '待做 1 件') '待办完成即时更新进度'
$c.tasks.SelectedIndex=1;Invoke-CompanionListAction 'done' $c
Assert (-not $script:companion.tasks[0].done) '已完成待办可以重新打开'
$editedId=[string]$script:companion.tasks[0].id;foreach($entry in $c.tasks.Items){if($entry.Tag -eq $editedId){$c.tasks.SelectedItem=$entry;break}};Invoke-CompanionListAction 'edit' $c;$c.newTask.Text='整理并提交项目';Invoke-CompanionListAction 'add' $c
Assert (@($script:companion.tasks|Where-Object{$_.id -eq $editedId})[0].text -eq '整理并提交项目' -and $script:companion.tasks.Count -eq 2) '修改待办保持身份且不重复添加'
$c.newTask.Text='键盘回车记录的待办'
$keyParams=New-Object Windows.Interop.HwndSourceParameters('WhaleWorkflowKeyTest');$keyParams.WindowStyle=0;$keyParams.Width=0;$keyParams.Height=0
$keySource=New-Object Windows.Interop.HwndSource($keyParams)
$enterEvent=New-Object Windows.Input.KeyEventArgs([Windows.Input.Keyboard]::PrimaryDevice,$keySource,0,[Windows.Input.Key]::Enter);$enterEvent.RoutedEvent=[Windows.Input.Keyboard]::KeyDownEvent
$c.newTask.RaiseEvent($enterEvent)
$keySource.Dispose()
Assert ($enterEvent.Handled -and @($script:companion.tasks|Where-Object{$_.text -eq '键盘回车记录的待办'}).Count -eq 1) '真实Enter键事件直接添加并阻止重复传播'
$keyboardId=@($script:companion.tasks|Where-Object{$_.text -eq '键盘回车记录的待办'})[0].id
Remove-PetTask $script:companion $keyboardId;$c.signature='';Refresh-CompanionLists $c
$c.search.Text='一本书'
Assert ($c.tasks.Items.Count -eq 1 -and $c.tasks.Items[0].Content -match '一本书') '输入搜索即时筛选待办'
$c.search.Text='';$c.tasks.SelectedIndex=0;Invoke-CompanionListAction 'delete' $c
$c.newTask.Text='删除之后的新待办';Invoke-CompanionListAction 'add' $c
Invoke-CompanionListAction 'undo' $c
Assert ($script:companion.tasks.Count -eq 3 -and @($script:companion.tasks|Where-Object{$_.text -eq '删除之后的新待办'}).Count -eq 1) '撤销删除只恢复目标不会覆盖后来添加的待办'
$r=Add-PetReminder $script:companion '已提醒仍可回看' 1 ([DateTime]::Now.AddMinutes(-5));$r.notified=$true
[void](Add-PetReminder $script:companion '稍后的提醒' 60)
$soon=Add-PetReminder $script:companion '最近的提醒' 2
$c.signature='';Refresh-CompanionLists $c
Assert ($c.reminders.Items[0].Tag -eq $soon.id -and $script:companion.reminders.Count -eq 3) '近期提醒排在最前且新增提醒不清空历史'
$offsetEarly=@{id='offset-early';text='不同时区更早的提醒';notified=$false;dueAt='2030-01-01T10:00:00+08:00'}
$offsetLate=@{id='offset-late';text='不同时区更晚的提醒';notified=$false;dueAt='2030-01-01T05:00:00Z'}
$script:companion.reminders+=@($offsetLate,$offsetEarly);$c.signature='';Refresh-CompanionLists $c
$offsetOrder=@($c.reminders.Items|Where-Object{$_.Tag -like 'offset-*'}|ForEach-Object{$_.Tag})
Assert ($offsetOrder[0] -eq 'offset-early' -and $offsetOrder[1] -eq 'offset-late') '跨时区提醒按真实时刻排序而非日期字符串'
$script:companion.reminders=@($script:companion.reminders|Where-Object{$_.id -notlike 'offset-*'});$c.signature='';Refresh-CompanionLists $c
$c.reminders.SelectedIndex=0;Invoke-CompanionListAction 'snooze' $c
$snoozed=@($script:companion.reminders|Where-Object{$_.id -eq $soon.id})[0]
Assert (-not $snoozed.notified -and ([DateTime]$snoozed.dueAt).ToLocalTime() -gt [DateTime]::Now.AddMinutes(9)) '稍后提醒延到十分钟且重新待提醒'

$script:focusUntil=$null;Start-Focus 5
$script:focusUntil=[DateTime]::Now.AddSeconds(180);$script:companion.focus.until=$script:focusUntil.ToUniversalTime().ToString('o')
Pause-PetFocus
$paused=Get-PetCompanionData $companionFile
Assert ($paused.focus.paused -and $paused.focus.remainingSeconds -ge 179 -and $paused.focus.remainingSeconds -le 180 -and -not (Get-PetFocusDeadline $paused)) '暂停持久保存剩余秒数且重读后不继续计时'
$originalSeconds=$paused.focus.remainingSeconds;Start-Focus 25
Assert ($script:companion.focus.paused -and $script:companion.focus.minutes -eq 5) '再次开始不会覆盖暂停中的专注'
$writerBeforePause=(Get-Item Function:\Write-PetJson).ScriptBlock
function Write-PetJson{throw '模拟无法保存'}
$failed=$false;try{Resume-PetFocus}catch{$failed=$true}
Assert ($failed -and $script:companion.focus.paused -and -not $script:focusUntil) '继续专注保存失败时保持暂停状态'
Set-Item Function:\Write-PetJson -Value $writerBeforePause
Resume-PetFocus
Assert ($script:focusUntil -gt [DateTime]::Now.AddSeconds(178) -and -not $script:companion.focus.paused) '继续专注按剩余时间而非原时长恢复'
$focusProbe=New-PetFocusWindow
Assert ($focusProbe.Tag.controls.clock.Text -match '^0[23]:\d\d$' -and $focusProbe.Tag.controls.progress.Value -gt 35 -and -not $focusProbe.Tag.controls.start.IsEnabled) '专注面板显示秒级倒计时进度并禁用重复开始'
Assert ($focusProbe.Tag.controls.start.Background.ToString() -eq '#FF127C91') '专注面板完整构造并应用已定义的主按钮样式'
$focusProbe.Tag.controls.pause.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ($focusProbe.Tag.controls.pause.Content -eq '继续专注') '真实暂停操作更新主按钮'
$focusProbe.Tag.controls.pause.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ($script:focusUntil -and -not $script:companion.focus.paused) '真实继续按钮恢复计时并写入同一份数据'
$focusProbe.Tag.controls.cancel.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert (-not $script:companion.focus -and $script:companion.focusCompletedCount -eq 0) '暂停后结束不会误记完成'
$focusProbe.Tag.controls.minutes.Text='7'
$focusProbe.Tag.controls.start.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ($script:companion.focus.minutes -eq 7 -and -not $focusProbe.Tag.controls.start.IsEnabled) '真实开始按钮创建专注并禁用重复开始'
$focusProbe.Tag.controls.cancel.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))

# Exercise asynchronous commands against the same data used by live windows.
$commandTask=Add-PetTask $script:companion '让Codex帮忙完成的待办';Save-CompanionData
$toggleCommand=New-TestCommand 'set_todo_done';$toggleCommand.taskId=$commandTask.id;$toggleCommand.done=$true
Write-PetJson (Join-Path $commandDirectory ($toggleCommand.id+'.json')) $toggleCommand;Process-PetCommands $probeHome
Assert (@((Read-PetJson $companionFile).tasks|Where-Object{$_.id -eq $commandTask.id})[0].done -and (Read-PetJson (Join-Path $probeHome ('command-results\'+$toggleCommand.id+'.json'))).status -eq 'completed') 'Codex完成待办命令实际落盘并回执成功'
$badToggle=New-TestCommand 'set_todo_done';$badToggle.taskId=$commandTask.id;$badToggle.done='false'
Write-PetJson (Join-Path $commandDirectory ($badToggle.id+'.json')) $badToggle;Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\'+$badToggle.id+'.json'))).status -eq 'failed' -and @($script:companion.tasks|Where-Object{$_.id -eq $commandTask.id})[0].done) '命令拒绝字符串布尔避免错误切换完成状态'
$badStamp=New-TestCommand 'add_todo' '无效时间不能加进待办';$badStamp.at='NaN'
Write-PetJson (Join-Path $commandDirectory ($badStamp.id+'.json')) $badStamp;Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\'+$badStamp.id+'.json'))).status -eq 'failed' -and -not @($script:companion.tasks|Where-Object{$_.text -eq $badStamp.text}).Count) '非有限命令时间不能绕过过期校验'
Start-Focus 5
$pauseCommand=New-TestCommand 'pause_focus';Process-PetCommands $probeHome
Assert ((Read-PetJson $companionFile).focus.paused -and -not $script:focusUntil) 'Codex暂停专注命令保存剩余秒数'
$resumeCommand=New-TestCommand 'resume_focus';Process-PetCommands $probeHome
Assert ($script:focusUntil -and -not (Read-PetJson $companionFile).focus.paused) 'Codex继续专注命令恢复剩余计时'
Cancel-Focus
$missingFocusCommand=New-TestCommand 'resume_focus';Process-PetCommands $probeHome
Assert ((Read-PetJson (Join-Path $probeHome ('command-results\'+$missingFocusCommand.id+'.json'))).status -eq 'failed') '没有专注时继续命令明确失败而不假报成功'

$c.signature='';Refresh-CompanionLists $c;$c.tasks.SelectedIndex=0
$staleTaskId=[string]$c.tasks.SelectedItem.Tag;Remove-PetTask $script:companion $staleTaskId;Save-CompanionData
$taskCountBefore=$script:companion.tasks.Count
$taskProbe.Tag.done.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert ($c.status.Text -match '已被移除' -and $script:companion.tasks.Count -eq $taskCountBefore -and -not @($c.tasks.Items|Where-Object{$_.Tag -eq $staleTaskId}).Count) '外部移除选中待办后真实按钮提示过期并刷新而不假报完成'
$companionBeforeUndoLimit=Copy-PetCompanionData $script:companion
$script:companion.tasks=@();for($i=0;$i -lt 50;$i++){[void](Add-PetTask $script:companion ('待做上限测试 '+$i))}
$c.deleted=@{kind='tasks';item=@{id='completed-undo-limit';text='已完成的历史任务';done=$true;createdAt=[DateTimeOffset]::UtcNow.ToString('o')}}
$c.undo.IsEnabled=$true
$c.undo.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
Assert (@($script:companion.tasks|Where-Object{-not $_.done}).Count -eq 50 -and @($script:companion.tasks|Where-Object{$_.id -eq 'completed-undo-limit'}).Count -eq 1) '待做已满仍能撤销删除已完成记录'
$script:companion=$companionBeforeUndoLimit;Save-CompanionData;$c.signature='';Refresh-CompanionLists $c
$c.newReminder.Text='键盘回车提醒';$c.minutes.Text='3'
$reminderKeyParams=New-Object Windows.Interop.HwndSourceParameters('WhaleReminderEnterTest');$reminderKeyParams.WindowStyle=0;$reminderKeyParams.Width=0;$reminderKeyParams.Height=0
$reminderKeySource=New-Object Windows.Interop.HwndSource($reminderKeyParams)
$reminderEnterEvent=New-Object Windows.Input.KeyEventArgs([Windows.Input.Keyboard]::PrimaryDevice,$reminderKeySource,0,[Windows.Input.Key]::Enter);$reminderEnterEvent.RoutedEvent=[Windows.Input.Keyboard]::KeyDownEvent
$c.minutes.RaiseEvent($reminderEnterEvent);$reminderKeySource.Dispose()
Assert ($reminderEnterEvent.Handled -and @((Read-PetJson $companionFile).reminders|Where-Object{$_.text -eq '键盘回车提醒'}).Count -eq 1) '提醒分钟输入框真实Enter事件直接创建一条提醒'
$savedShowTasks=(Get-Command Show-PetTasks).ScriptBlock;$script:panelOpened=''
function Show-PetTasks{$script:panelOpened='tasks'}
$panelCommand=New-TestCommand 'open_panel';$panelCommand.panel='tasks';Write-PetJson (Join-Path $commandDirectory ($panelCommand.id+'.json')) $panelCommand
Process-PetCommands $probeHome
Set-Item Function:\Show-PetTasks -Value $savedShowTasks
Assert ($script:panelOpened -eq 'tasks' -and -not $window.IsVisible -and (Read-PetJson (Join-Path $probeHome ('command-results\'+$panelCommand.id+'.json'))).status -eq 'completed') '打开面板命令只调用指定面板且不唤醒隐藏主宠'

$r=Add-PetReminder $script:companion '写失败也要再提醒' 1 ([DateTime]::Now.AddMinutes(-2))
$script:gentleReminder='';$windowBefore=$window;$window=[pscustomobject]@{IsVisible=$true};$script:away=$false;$script:pending=$null
function Write-PetJson{throw '模拟提醒写入失败'}
$failed=$false;try{Update-Companion ([DateTime]::Now)}catch{$failed=$true}
Assert ($failed -and -not @($script:companion.reminders|Where-Object{$_.id -eq $r.id})[0].notified -and -not $script:gentleReminder) '提醒状态保存失败不会丢失待提醒或生成虚假成功'
Set-Item Function:\Write-PetJson -Value $writerBeforePause;$window=$windowBefore

$libraryPath=Join-Path $PetHome 'news-library.json'
$article=[pscustomobject]@{id='workflow-test';title='测试用科技新闻';summary='用于验证筛选和收藏';url='https://openai.com/news/';source='测试来源';topics=@('ai');publishedAt=[DateTimeOffset]::Now.ToString('o')}
function Get-WhaleNewsItems{param([string]$PetHome);return @($script:testNewsArticle)}
$script:testNewsArticle=$article
$nc=$newsProbe.Tag.controls
Invoke-PetNewsItemAction 'save' $article $nc $nc.items
Assert ((Get-PetNewsLibrary $libraryPath).savedItems.Count -eq 1) '新闻收藏持久保存文章内容而非只保存过期缓存编号'
Invoke-PetNewsItemAction 'read' $article $nc $nc.items
Assert ((Get-PetNewsLibrary $libraryPath).readIds -contains 'workflow-test') '新闻已读状态持久保存'
$nc.filter.SelectedIndex=1
Assert ($nc.count.Text -match '找到 0 条') '未读筛选立即隐藏已读新闻'
$nc.filter.SelectedIndex=2
Assert ($nc.count.Text -match '找到 1 条') '收藏筛选展示已保存文章'
$nc.search.Text='不存在的关键词'
Assert ($nc.count.Text -match '找到 0 条') '新闻搜索与收藏筛选叠加生效'
$nc.search.Text='';$nc.filter.SelectedIndex=0
$script:testNewsArticle=[pscustomobject]@{id='new-workflow-test';title='缓存刚更新的测试新闻';url='https://openai.com/news/';source='测试来源';topics=@('ai')}
Write-PetJson (Join-Path $PetHome 'news.json') @{status='ok';lastAttemptAt=[DateTimeOffset]::Now.ToString('o');items=@($script:testNewsArticle)}
Update-PetNewsWindow $newsProbe
Assert ($nc.items.Children[1].Children[0].Text -eq '缓存刚更新的测试新闻') '缓存更新后自动显示新文章不需再次点显示缓存'
$healthText=$nc.sourceHealthText;$nc.sourceHealth.IsExpanded=$true
Write-PetJson (Join-Path $PetHome 'news.json') @{status='partial';lastAttemptAt=[DateTimeOffset]::Now.ToString('o');items=@($script:testNewsArticle);sources=@(@{id='openai';name='OpenAI 官方';ok=$false;state='failed';message='来源返回 HTTP 403，已保留缓存';lastCheckedAt=[DateTimeOffset]::Now.ToString('o');lastSuccessAt=[DateTimeOffset]::Now.AddHours(-1).ToString('o')})}
Update-PetNewsWindow $newsProbe
Assert ($nc.sourceHealth.IsExpanded -and [object]::ReferenceEquals($healthText,$nc.sourceHealthText)) '来源健康刷新复用原控件，保留用户展开状态'
Assert ($nc.sourceHealthText.Text -match 'HTTP 403' -and $nc.sourceHealthText.Text -match '最近成功：' -and $nc.sourceHealth.Content.MaxHeight -eq 280) '来源健康展示具体失败和最近成功时间，长列表在限定高度内滚动'
$nc.filter.SelectedIndex=2
Assert ($nc.count.Text -match '找到 1 条') '原新闻离开缓存后收藏仍能回看'
$savedWriter=(Get-Item Function:\Write-PetJson).ScriptBlock
function Write-PetJson{throw '模拟收藏保存失败'}
Invoke-PetNewsItemAction 'save' $article $nc $nc.items
Set-Item Function:\Write-PetJson -Value $savedWriter
Assert ((Get-PetNewsLibrary $libraryPath).savedItems.Count -eq 1 -and $nc.status.Text -match '模拟收藏保存失败') '收藏保存失败不改变磁盘状态并提示可重试'
$nc.wasBusy=$true
Write-PetJson (Join-Path $PetHome 'news-refresh-status.json') @{state='failed';at=1;message='获取进程中断，请重试。';cacheStatus='ok'}
Update-PetNewsWindow $newsProbe
Assert ($nc.refresh.IsEnabled -and $nc.status.Text -eq '获取进程中断，请重试。') '新闻后台失败后面板显示实际失败而不假报更新成功'
Write-PetJson (Join-Path $PetHome 'news-refresh-status.json') @{state='completed';at=2;cacheStatus='partial'}
Update-PetNewsWindow $newsProbe
Assert ($nc.status.Text -match '部分来源暂时不可用') '新闻部分成功明确展示来源故障'
Write-PetJson (Join-Path $PetHome 'news-refresh-status.json') @{state='running';at=3;cacheStatus='ok'}
Update-PetNewsWindow $newsProbe
Assert ($nc.status.Text -match '上次获取没有完成') '过期工作状态不会伪装成刷新完成'

if($env:WHALE_RENDER_WORKFLOWS -eq '1'){
  function Export-WorkflowView($Dialog,[string]$Name){
    $content=$Dialog.Content;$content.Background=$Dialog.Background;$size=New-Object Windows.Size(($Dialog.Width-20),($Dialog.Height-40))
    $content.Measure($size);$content.Arrange((New-Object Windows.Rect(0,0,$size.Width,$size.Height)));$content.UpdateLayout()
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$size.Width,[int]$size.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($content)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file=[IO.File]::Create((Join-Path $PSScriptRoot ('..\.diag\'+$Name+'.png')));try{$encoder.Save($file)}finally{$file.Dispose()}
  }
  Export-WorkflowView $taskProbe 'workflow-tasks';Export-WorkflowView $newsProbe 'workflow-news';Export-WorkflowView $focusProbe 'workflow-focus'
}
$focusProbe.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.FrameworkElement]::LoadedEvent)))
Assert ($focusProbe.Tag.timer.IsEnabled) '窗口加载才启动界面刷新计时器'
$focusProbe.Tag.controls.clock.Text='等待刷新'
$refreshFrame=New-Object Windows.Threading.DispatcherFrame
$finishRefresh=New-Object Windows.Threading.DispatcherTimer;$finishRefresh.Interval=[TimeSpan]::FromMilliseconds(1250)
$finishRefresh.Add_Tick({$finishRefresh.Stop();$refreshFrame.Continue=$false});$finishRefresh.Start()
[Windows.Threading.Dispatcher]::PushFrame($refreshFrame)
Assert ($focusProbe.Tag.controls.clock.Text -eq '准备好了') '真实Dispatcher计时器回调刷新专注显示'
$settingsProbe.Close(); $taskProbe.Close(); $newsProbe.Close();$focusProbe.Close()
Assert (-not $focusProbe.Tag.timer.IsEnabled) '窗口关闭后停止刷新避免后台计时器泄漏'
$tray.Dispose(); $window.Close()

# Run the dispatcher without showing any window or tray icon.
$probeWindow = New-Object System.Windows.Window
$probeApp = New-Object System.Windows.Application
$probeApp.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$probeApp.MainWindow = $probeWindow
$script:dispatcherTicks = 0
$probeTimer = New-Object System.Windows.Threading.DispatcherTimer
$probeTimer.Interval = [TimeSpan]::FromMilliseconds(20)
$probeTimer.Add_Tick({
  $script:dispatcherTicks++
  if ($script:dispatcherTicks -eq 1) { $probeWindow.Hide() }
  if ($script:dispatcherTicks -eq 3) { $probeWindow.Close() }
})
$probeTimer.Start()
[void]$probeApp.Run()
$probeTimer.Stop()
Assert ($script:dispatcherTicks -eq 3) '真实WPF消息循环在隐藏后继续运行，关闭才退出'
'TOTAL_PASSED=' + $script:passed
