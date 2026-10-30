# User-opened companion windows. Dot sourcing this file never displays a window.
. (Join-Path $PSScriptRoot 'whale-focus.ps1')
. (Join-Path $PSScriptRoot 'whale-media.ps1')
function New-CompanionWindow([string]$Title, [int]$Width = 560, [int]$Height = 690) {
  $dialog = New-Object System.Windows.Window
  $dialog.Title = $Title; $dialog.Width = $Width; $dialog.Height = $Height
  $dialog.MinWidth = 430; $dialog.MinHeight = 420
  $dialog.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
  $dialog.FontFamily = 'Microsoft YaHei UI'; $dialog.FontSize = 13
  $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F2F8FA')
  $dialog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#183B48')
  $scroll = New-Object System.Windows.Controls.ScrollViewer
  $scroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
  $panel = New-Object System.Windows.Controls.StackPanel
  $panel.Margin = New-Object System.Windows.Thickness(22)
  $scroll.Content = $panel; $dialog.Content = $scroll
  $dialog.Tag = @{ panel = $panel }
  return $dialog
}
function Add-CompanionLabel($Panel, [string]$Text, [int]$Size = 13) {
  $label = New-Object System.Windows.Controls.TextBlock
  $label.Text = $Text; $label.TextWrapping = [System.Windows.TextWrapping]::Wrap
  $label.FontSize = $Size; $label.Margin = New-Object System.Windows.Thickness(0, 9, 0, 5)
  [void]$Panel.Children.Add($label)
  return $label
}
function Add-CompanionInput($Panel, [string]$Label, [string]$Value, [int]$MaxLength = 120) {
  [void](Add-CompanionLabel $Panel $Label)
  $input = New-Object System.Windows.Controls.TextBox
  $input.Text = $Value; $input.MaxLength = $MaxLength; $input.Padding = New-Object System.Windows.Thickness(7)
  [void]$Panel.Children.Add($input)
  return $input
}
function Add-CompanionButton($Panel, [string]$Label) {
  $button = New-Object System.Windows.Controls.Button
  $button.Content = $Label; $button.Padding = New-Object System.Windows.Thickness(12, 7, 12, 7)
  $button.Margin = New-Object System.Windows.Thickness(0, 8, 7, 3)
  $button.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
  $button.MinHeight=34
  [void]$Panel.Children.Add($button)
  return $button
}
function Set-CompanionPrimaryButton($Button) {
  # Shared by the focus panel. Keep this helper in the UI module so opening the
  # panel does not depend on a theme function being defined by the host script.
  $Button.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#127C91')
  $Button.Foreground = [Windows.Media.Brushes]::White
  $Button.BorderBrush = $Button.Background
}
function Add-CompanionCheck($Panel, [string]$Label, [bool]$Checked) {
  $check = New-Object System.Windows.Controls.CheckBox
  $check.Content = $Label; $check.IsChecked = $Checked; $check.Margin = New-Object System.Windows.Thickness(0, 8, 14, 3)
  [void]$Panel.Children.Add($check)
  return $check
}
function Update-PetIdentity {
  $window.Title=$script:preferences.petName+' · 桌面陪伴'
  $miShow.Text='叫'+$script:preferences.petName+'出来'
  if($bubbleNameText){$bubbleNameText.Text=$script:preferences.petName+' · 陪着 '+$script:preferences.userName}
}
function Save-PetSettingsValues($Controls, $Dialog) {
  try {
    $petName = ConvertTo-PetSingleLine $Controls.petName.Text 24
    $userName = ConvertTo-PetSingleLine $Controls.userName.Text 24
    if (-not $petName -or -not $userName) { throw '两个称呼都要填写哦。' }
    $focus = 0; $newsMin = 0; $newsMax = 0; $newsLimit = 0
    if (-not [int]::TryParse($Controls.focus.Text, [ref]$focus) -or $focus -lt 5 -or $focus -gt 180) { throw '专注时间请填 5 到 180 分钟。' }
    if (-not [int]::TryParse($Controls.newsMin.Text, [ref]$newsMin) -or $newsMin -lt 60 -or $newsMin -gt 720) { throw '新闻最短间隔请填 60 到 720 分钟。' }
    if (-not [int]::TryParse($Controls.newsMax.Text, [ref]$newsMax) -or $newsMax -lt $newsMin -or $newsMax -gt 720) { throw '新闻最长间隔应不小于最短间隔，并在 720 分钟以内。' }
    if (-not [int]::TryParse($Controls.newsLimit.Text, [ref]$newsLimit) -or $newsLimit -lt 1 -or $newsLimit -gt 6) { throw '每天新闻最多分享 1 到 6 次。' }
    $topics = @($Controls.topics.Keys | Where-Object { [bool]$Controls.topics[$_].IsChecked })
    if (-not $topics.Count) { throw '至少选一个感兴趣的新闻话题吧。' }
    # Validate everything before writing; failed persistence keeps previous live preferences.
    $next = @{}; foreach ($key in $script:preferences.Keys) { $next[$key] = $script:preferences[$key] }
    $next.petName = $petName; $next.userName = $userName; $next.focusMinutes = $focus
    $next.autoWakeOnHostStart = [bool]$Controls.autoWake.IsChecked
    $next.quiet = [bool]$Controls.quiet.IsChecked; $next.walk = [bool]$Controls.walk.IsChecked
    $next.breakReminders = [bool]$Controls.breaks.IsChecked; $next.newsEnabled = [bool]$Controls.news.IsChecked
    if($Controls.displayMode){$next.displayMode=if($Controls.displayMode.SelectedIndex -eq 1){'native'}else{'desktop'}}
    $next.newsTopics = $topics; $next.newsMinMinutes = $newsMin; $next.newsMaxMinutes = $newsMax; $next.newsDailyLimit = $newsLimit
    $previousMode=[string]$script:preferences.displayMode
    Write-Json $preferencesFile $next
    $script:preferences = $next; $script:walk = $next.walk
    $miQuiet.Checked = $next.quiet; $miWalk.Checked = $next.walk; $miBreak.Checked = $next.breakReminders
    Update-PetIdentity
    if($previousMode -cne [string]$next.displayMode -and (Get-Command Set-PetDisplayMode -ErrorAction SilentlyContinue)){Set-PetDisplayMode ([string]$next.displayMode)}
    Update-Tray
    $Controls.status.Text = '保存好了，下次打开也会记得。'
    Say '{user}，称呼和陪伴习惯记好啦。' 3600
  } catch { $Controls.status.Text = $_.Exception.Message }
}
function New-PetSettingsWindow {
  $dialog = New-CompanionWindow ($script:preferences.petName + ' · 设置与称呼') 560 735
  $panel = $dialog.Tag.panel
  [void](Add-CompanionLabel $panel '把陪伴调成你喜欢的样子' 21)
  [void](Add-CompanionLabel $panel '默认跟随 Codex 工作。隐藏后会继续安静等着；设置窗口只会由你主动打开。')
  $controls = @{}
  $controls.petName = Add-CompanionInput $panel '给它起个名字（最多 24 字）' $script:preferences.petName 24
  $controls.userName = Add-CompanionInput $panel '它怎么称呼你（例如：阿宁、老板、搭子）' $script:preferences.userName 24
  [void](Add-CompanionLabel $panel '陪伴显示方式')
  $controls.displayMode=Add-CompanionChoice $panel @('独立桌宠（完整气泡和互动）','使用应用内置宠物（保留原功能面板）')
  $controls.displayMode.SelectedIndex=if($script:preferences.displayMode -eq 'native'){1}else{0}
  [void](Add-CompanionLabel $panel '内置模式下不会再出现第二个桌宠；待办、提醒、专注和新闻仍由本机服务保留。' 11)
  $controls.focus = Add-CompanionInput $panel '一次专注的分钟数（5～180）' $script:preferences.focusMinutes 3
  $controls.autoWake = Add-CompanionCheck $panel '打开 Codex 时自动唤醒（同一轮退出或隐藏后不反复叫醒）' $script:preferences.autoWakeOnHostStart
  $controls.quiet = Add-CompanionCheck $panel '安静陪伴：减少随机气泡和走动' $script:preferences.quiet
  $controls.walk = Add-CompanionCheck $panel '允许自动溜达' $script:preferences.walk
  $controls.breaks = Add-CompanionCheck $panel '每 50 分钟提醒起身、喝水' $script:preferences.breakReminders
  [void](Add-CompanionLabel $panel '偶尔分享新闻' 18)
  $controls.news = Add-CompanionCheck $panel '允许偶尔分享一条新闻' $script:preferences.newsEnabled
  [void](Add-CompanionLabel $panel '睡觉、隐藏、专注和等待你处理 Codex 提示时不打扰。新闻会保留来源链接。')
  $topicsRow = New-Object System.Windows.Controls.WrapPanel; [void]$panel.Children.Add($topicsRow)
  $controls.topics = @{}
  foreach ($topic in @(@{ id = 'ai'; label = 'AI' }, @{ id = 'tech'; label = '科技' }, @{ id = 'china'; label = '国内' }, @{ id = 'world'; label = '国际' }, @{ id = 'games'; label = '游戏' })) {
    $controls.topics[$topic.id] = Add-CompanionCheck $topicsRow $topic.label ($script:preferences.newsTopics -contains $topic.id)
  }
  $controls.newsMin = Add-CompanionInput $panel '随机分享的最短间隔（分钟，60～720）' $script:preferences.newsMinMinutes 3
  $controls.newsMax = Add-CompanionInput $panel '随机分享的最长间隔（分钟，至少等于最短间隔）' $script:preferences.newsMaxMinutes 3
  $controls.newsLimit = Add-CompanionInput $panel '每天最多分享几条（1～6）' $script:preferences.newsDailyLimit 1
  $controls.status = Add-CompanionLabel $panel ''
  $save = Add-CompanionButton $panel '保存设置'
  $save.Add_Click({ Save-PetSettingsValues $controls $dialog }.GetNewClosure())
  $dialog.Tag.controls = $controls; $dialog.Tag.save = $save
  return $dialog
}
function Show-PetSettings {
  if ($script:settingsWindow -and $script:settingsWindow.IsVisible) { [void]$script:settingsWindow.Activate(); return }
  $script:settingsWindow = New-PetSettingsWindow
  $script:settingsWindow.Show()
}
function Process-PetShowRequest {
  $request=Read-Json $showFile
  Remove-Item -LiteralPath $showFile -Force -ErrorAction SilentlyContinue
  $stamp=0.0
  if(-not $request -or $request.explicit -ne $true -or -not [double]::TryParse([string]$request.at,[ref]$stamp) -or [double]::IsNaN($stamp) -or [double]::IsInfinity($stamp)){return}
  $age=(Get-PetUtcMs)-$stamp
  if($age -lt -30000 -or $age -gt 45000){return}
  $hidden=Read-Json $hiddenFile
  if($hidden.at -and [double]$hidden.at -ge $stamp){return}
  Show-Pet;petLog 'shown by a fresh host/manual request'
}
function Save-CompanionData { Write-Json $companionFile $script:companion }
function Start-CompanionWindowTimer($Dialog,[scriptblock]$Tick,[int]$IntervalSeconds=1){
  $timer=New-Object Windows.Threading.DispatcherTimer
  $timer.Interval=[TimeSpan]::FromSeconds([Math]::Max(1,$IntervalSeconds))
  $timer.Add_Tick({try{& $Tick}catch{petLog ('companion view refresh: '+$_.Exception.Message)}}.GetNewClosure())
  $Dialog.Add_Loaded({$timer.Start()}.GetNewClosure())
  $Dialog.Add_Closed({$timer.Stop()}.GetNewClosure())
  $Dialog.Tag.timer=$timer
  return $timer
}
function Add-CompanionChoice($Panel,[string[]]$Options){
  $choice=New-Object Windows.Controls.ComboBox
  foreach($option in $Options){[void]$choice.Items.Add($option)}
  $choice.SelectedIndex=0;$choice.MinWidth=110;$choice.Margin=New-Object Windows.Thickness(0,5,8,5)
  [void]$Panel.Children.Add($choice);return $choice
}
function Refresh-CompanionLists($Controls) {
  $filter=if($Controls.filter){[int]$Controls.filter.SelectedIndex}else{0}
  $query=if($Controls.search){$Controls.search.Text.Trim()}else{''}
  $signature=($script:companion | ConvertTo-Json -Depth 10 -Compress)+"|$filter|$query|"+[DateTime]::Now.ToString('yyyyMMddHHmm')
  if($Controls.signature -ceq $signature){return}
  $Controls.signature=$signature
  $selectedTask=if($Controls.tasks.SelectedItem){[string]$Controls.tasks.SelectedItem.Tag}else{''}
  $selectedReminder=if($Controls.reminders.SelectedItem){[string]$Controls.reminders.SelectedItem.Tag}else{''}
  $Controls.tasks.Items.Clear(); $Controls.reminders.Items.Clear()
  foreach ($task in @($script:companion.tasks | Sort-Object done)) {
    if(($filter -eq 1 -and $task.done) -or ($filter -eq 2 -and -not $task.done)){continue}
    if($query -and ([string]$task.text).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Content = $(if ($task.done) { '✓ ' } else { '○ ' }) + [string]$task.text; $item.Tag = [string]$task.id
    [void]$Controls.tasks.Items.Add($item)
    if($item.Tag -eq $selectedTask){$Controls.tasks.SelectedItem=$item}
  }
  # Imported reminders can carry different UTC offsets. Sort by the instant,
  # rather than ISO text ("10:00+08:00" is earlier than "05:00Z").
  foreach ($reminder in @($script:companion.reminders | Sort-Object @{Expression={ [int][bool]$_.notified }},@{Expression={ $date=[DateTimeOffset]::MinValue;if([DateTimeOffset]::TryParse([string]$_.dueAt,[ref]$date)){$date.UtcTicks}else{[long]::MaxValue} }})) {
    $deadline = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$reminder.dueAt, [ref]$deadline)) { continue }
    $item = New-Object System.Windows.Controls.ListBoxItem
    $left=[int][Math]::Ceiling(($deadline.ToLocalTime()-[DateTime]::Now).TotalMinutes)
    $when=if($reminder.notified){'已提醒'}elseif($left -le 0){'已到时间'}elseif($left -lt 60){[string]$left+' 分钟后'}else{$deadline.ToLocalTime().ToString('MM-dd HH:mm')}
    $item.Content = $when + '  ' + [string]$reminder.text; $item.Tag = [string]$reminder.id
    [void]$Controls.reminders.Items.Add($item)
    if($item.Tag -eq $selectedReminder){$Controls.reminders.SelectedItem=$item}
  }
  if($Controls.summary){$active=@($script:companion.tasks|Where-Object{-not $_.done}).Count;$completed=@($script:companion.tasks|Where-Object{$_.done}).Count;$Controls.summary.Text='待做 '+$active+' 件    已完成 '+$completed+' 件';$Controls.empty.Text=if($Controls.tasks.Items.Count){''}elseif($query){'没有找到，换个关键词试试。'}elseif($filter -eq 2){'还没有完成记录，从一件小事开始。'}else{'这里已经清空了，歇一会儿也很好。'}}
  if($Controls.done){$selected=@($script:companion.tasks|Where-Object{$_.id -eq $selectedTask}|Select-Object -First 1);$Controls.done.Content=if($selected.Count -and $selected[0].done){'重新打开'}else{'完成选中待办'}}
}
function Update-PetTaskSelection($Controls){
  $selected=@($script:companion.tasks|Where-Object{$_.id -eq [string]$Controls.tasks.SelectedItem.Tag})
  $Controls.done.Content=if($selected.Count -and $selected[0].done){'重新打开'}else{'完成选中待办'}
}
function Get-PetSelectedListEntry($Items,$SelectedItem,[string]$Name){
  if(-not $SelectedItem){throw ('先选一条'+$Name+'吧。')}
  $matches=@($Items|Where-Object{[string]$_.id -ceq [string]$SelectedItem.Tag})
  if($matches.Count -ne 1){throw ('这条'+$Name+'已被移除，列表已刷新。')}
  return $matches[0]
}
function Invoke-CompanionListAction([string]$Action, $Controls) {
  try {
    # Work on a copy, so a write failure cannot claim that a task was saved.
    $next = Copy-PetCompanionData $script:companion
    $done = $false
    $deleted=$null
    switch ($Action) {
      'add' { if($Controls.editId){Set-PetTaskText $next $Controls.editId $Controls.newTask.Text}else{[void](Add-PetTask $next $Controls.newTask.Text)} }
      'edit'{$selected=Get-PetSelectedListEntry $next.tasks $Controls.tasks.SelectedItem '待办';$Controls.editId=[string]$selected.id;$Controls.newTask.Text=[string]$selected.text;$Controls.add.Content='保存修改';[void]$Controls.newTask.Focus();$Controls.status.Text='在输入框里修改，按 Enter 保存。';return}
      'done' { $selected=Get-PetSelectedListEntry $next.tasks $Controls.tasks.SelectedItem '待办';$target=-not [bool]$selected.done;[void](Set-PetTaskDone $next ([string]$selected.id) $target);$done=$target }
      'delete' { $selected=Get-PetSelectedListEntry $next.tasks $Controls.tasks.SelectedItem '待办';$id=[string]$selected.id;$deleted=@{kind='tasks';item=$selected};Remove-PetTask $next $id }
      'remind' {
        $minutes = 0
        if (-not [int]::TryParse($Controls.minutes.Text, [ref]$minutes)) { throw '请输入提醒的分钟数。' }
        [void](Add-PetReminder $next $Controls.newReminder.Text $minutes)
      }
      'cancelReminder' { $selected=Get-PetSelectedListEntry $next.reminders $Controls.reminders.SelectedItem '提醒';$id=[string]$selected.id;$deleted=@{kind='reminders';item=$selected};Remove-PetReminder $next $id }
      'snooze'{if(-not $Controls.reminders.SelectedItem){throw '先选一条提醒吧。'};Snooze-PetReminder $next ([string]$Controls.reminders.SelectedItem.Tag) 10}
      'undo'{if(-not $Controls.deleted){throw '没有可撤销的删除。'};$entry=$Controls.deleted;$limit=if($entry.kind -eq 'tasks'){50}else{20};$active=@($next[$entry.kind]|Where-Object{if($entry.kind -eq 'tasks'){-not $_.done}else{-not $_.notified}}).Count;$restoresActive=if($entry.kind -eq 'tasks'){-not $entry.item.done}else{-not $entry.item.notified};if($restoresActive -and $active -ge $limit){throw '列表已满，腾出位置后再恢复。'};if(-not @($next[$entry.kind]|Where-Object{$_.id -eq $entry.item.id}).Count){$next[$entry.kind]=@($next[$entry.kind])+$entry.item}}
      default{throw '这项操作暂时不可用。'}
    }
    Write-Json $companionFile $next; $script:companion = $next
    if ($Action -eq 'add') { $Controls.newTask.Clear();$Controls.editId='';if($Controls.add){$Controls.add.Content='加入待办'} }
    if ($Action -eq 'remind') { $Controls.newReminder.Clear() }
    if($deleted){$Controls.deleted=$deleted;$Controls.undo.IsEnabled=$true}
    if($Action -eq 'undo'){$Controls.deleted=$null;$Controls.undo.IsEnabled=$false}
    $Controls.signature=''
    Refresh-CompanionLists $Controls
    $Controls.status.Text = $(if($deleted){'已删除。误点了可以点“撤销删除”。'}elseif($Action -eq 'snooze'){'10 分钟后再提醒，先处理眼前的事。'}elseif($Action -eq 'undo'){'已经恢复了。'}elseif ($done) { '做成一件就很棒了。下一步慢慢来。' } else { '记好啦，会保存在这台电脑上。' })
    if ($done) { Show-Pose 'daily-done' 4200; Say '{user}，又完成一件事，给自己一点掌声吧。' 4200 }
  } catch { $Controls.status.Text = $_.Exception.Message;$Controls.signature='';Refresh-CompanionLists $Controls }
}
function New-PetTasksWindow {
  $dialog = New-CompanionWindow ($script:preferences.petName + ' · 待办与提醒') 650 760
  $panel = $dialog.Tag.panel; $controls = @{}
  $rootPanel=$panel
  [void](Add-CompanionLabel $panel '把今天拆成一件件小事' 21)
  $controls.summary=Add-CompanionLabel $panel '' 14
  [void](Add-CompanionLabel $panel '待办和提醒只存在本机。重启会记得；隐藏、离开时，到期提醒会合并留到你回来。')
  $tabs=New-Object Windows.Controls.TabControl;[void]$panel.Children.Add($tabs)
  $taskPanel=New-Object Windows.Controls.StackPanel;$taskPanel.Margin=New-Object Windows.Thickness(10)
  $reminderPanel=New-Object Windows.Controls.StackPanel;$reminderPanel.Margin=New-Object Windows.Thickness(10)
  foreach($pair in @(@{title='待办';panel=$taskPanel},@{title='提醒';panel=$reminderPanel})){$tab=New-Object Windows.Controls.TabItem;$tab.Header=$pair.title;$tab.Content=$pair.panel;[void]$tabs.Items.Add($tab)}
  $panel=$taskPanel;$controls.tabs=$tabs
  $controls.newTask = Add-CompanionInput $panel '一件想做的事（最多 120 字）' '' 120
  $add = Add-CompanionButton $panel '加入待办'; $add.Add_Click({ Invoke-CompanionListAction 'add' $controls }.GetNewClosure())
  $controls.add=$add
  $controls.newTask.Add_KeyDown({if($_.Key -eq [Windows.Input.Key]::Enter){Invoke-CompanionListAction 'add' $controls;$_.Handled=$true}elseif($_.Key -eq [Windows.Input.Key]::Escape){$controls.editId='';$controls.newTask.Clear();$controls.add.Content='加入待办'}}.GetNewClosure())
  $filters=New-Object Windows.Controls.WrapPanel;[void]$panel.Children.Add($filters)
  $controls.filter=Add-CompanionChoice $filters @('全部待办','只看待做','只看已完成')
  $controls.search=Add-CompanionInput $panel '搜索待办' '' 120
  $controls.tasks = New-Object System.Windows.Controls.ListBox; $controls.tasks.Height = 135
  $controls.tasks.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Stretch
  [void]$panel.Children.Add($controls.tasks)
  $controls.empty=Add-CompanionLabel $panel '' 12
  $row = New-Object System.Windows.Controls.WrapPanel; [void]$panel.Children.Add($row)
  $done = Add-CompanionButton $row '完成选中待办'; $done.Add_Click({ Invoke-CompanionListAction 'done' $controls }.GetNewClosure())
  $controls.done=$done
  $edit=Add-CompanionButton $row '修改内容';$edit.Add_Click({Invoke-CompanionListAction 'edit' $controls}.GetNewClosure())
  $delete = Add-CompanionButton $row '删除选中待办'; $delete.Add_Click({ Invoke-CompanionListAction 'delete' $controls }.GetNewClosure())
  $panel=$reminderPanel
  $controls.newReminder = Add-CompanionInput $panel '想让我提醒的事（例如：关烤箱、去开会）' '' 120
  $controls.minutes = Add-CompanionInput $panel '多少分钟后提醒（1～1440）' '15' 4
  $presets = New-Object System.Windows.Controls.WrapPanel; [void]$panel.Children.Add($presets)
  foreach ($minute in @(5, 15, 30)) {
    $preset = Add-CompanionButton $presets ($minute.ToString() + ' 分钟')
    $value = [string]$minute; $preset.Add_Click({ $controls.minutes.Text = $value }.GetNewClosure())
  }
  $remind = Add-CompanionButton $panel '设置这条提醒'; $remind.Add_Click({ Invoke-CompanionListAction 'remind' $controls }.GetNewClosure())
  $reminderEnter={if($_.Key -eq [Windows.Input.Key]::Enter){Invoke-CompanionListAction 'remind' $controls;$_.Handled=$true}}.GetNewClosure()
  $controls.newReminder.Add_KeyDown($reminderEnter);$controls.minutes.Add_KeyDown($reminderEnter)
  $controls.reminders = New-Object System.Windows.Controls.ListBox; $controls.reminders.Height = 85
  [void]$panel.Children.Add($controls.reminders)
  $cancel = Add-CompanionButton $panel '取消选中提醒'; $cancel.Add_Click({ Invoke-CompanionListAction 'cancelReminder' $controls }.GetNewClosure())
  $snooze=Add-CompanionButton $panel '10 分钟后再提醒';$snooze.Add_Click({Invoke-CompanionListAction 'snooze' $controls}.GetNewClosure())
  $panel=$rootPanel
  $controls.undo=Add-CompanionButton $panel '撤销删除';$controls.undo.IsEnabled=$false;$controls.undo.Add_Click({Invoke-CompanionListAction 'undo' $controls}.GetNewClosure())
  $controls.status = Add-CompanionLabel $panel ''
  $controls.filter.Add_SelectionChanged({Refresh-CompanionLists $controls}.GetNewClosure())
  $controls.search.Add_TextChanged({Refresh-CompanionLists $controls}.GetNewClosure())
  $controls.tasks.Add_SelectionChanged({Update-PetTaskSelection $controls}.GetNewClosure())
  $dialog.Tag.controls = $controls; $dialog.Tag.add = $add; $dialog.Tag.done = $done; $dialog.Tag.delete = $delete; $dialog.Tag.remind = $remind
  Refresh-CompanionLists $controls
  [void](Start-CompanionWindowTimer $dialog {Refresh-CompanionLists $controls}.GetNewClosure() 5)
  return $dialog
}
function Show-PetTasks {
  if ($script:tasksWindow -and $script:tasksWindow.IsVisible) { Refresh-CompanionLists $script:tasksWindow.Tag.controls; [void]$script:tasksWindow.Activate(); return }
  $script:tasksWindow = New-PetTasksWindow; $script:tasksWindow.Show()
}
function Open-PetNewsSource([string]$Url) {
  if (-not (Test-PetNewsUrl $Url)) { return $false }
  try { Start-Process -FilePath $Url -ErrorAction Stop;return $true } catch { petLog ('cannot open news source: ' + $_.Exception.Message);return $false }
}
function Format-PetNewsTime([string]$Value) {
  $timestamp = [DateTimeOffset]::MinValue
  if ([DateTimeOffset]::TryParse($Value, [ref]$timestamp)) { return $timestamp.ToLocalTime().ToString('yyyy-MM-dd HH:mm') }
  return '来源未提供发布时间'
}
function Refresh-PetNewsInbox($Panel,$Controls=$null) {
  $scroll=if($Controls){$Controls.scroll}else{$null}
  $offset=if($scroll){$scroll.VerticalOffset}else{0}
  $Panel.Children.Clear()
  $library=Get-PetNewsLibrary (Join-Path $PetHome 'news-library.json')
  $cache = Read-Json (Join-Path $PetHome 'news.json')
  if ($cache) {
    $cacheStatus = '最近更新：' + $(if ($cache.lastFetchedAt) { Format-PetNewsTime ([string]$cache.lastFetchedAt) } else { '尚未获取成功' })
    if ($cache.status -eq 'offline') { $cacheStatus += ' · 当前离线，显示旧缓存' }
    elseif ($cache.status -eq 'partial') { $cacheStatus += ' · 部分来源暂时不可用' }
    [void](Add-CompanionLabel $Panel $cacheStatus 11)
  }
  $items = @(); if (Get-Command Get-WhaleNewsItems -ErrorAction SilentlyContinue) { $items = @(Get-WhaleNewsItems -PetHome $PetHome) }
  if($Controls){
    if($Controls.filter.SelectedIndex -eq 2){$items=@($library.savedItems)}
    elseif($Controls.filter.SelectedIndex -eq 1){$items=@($items|Where-Object{$library.readIds -notcontains [string]$_.id})}
    $topic=@('','ai','tech','china','world','games')[$Controls.topic.SelectedIndex]
    $query=$Controls.search.Text.Trim()
    $items=@($items|Where-Object{(-not $topic -or @($_.topics) -contains $topic) -and (-not $query -or (([string]$_.title+' '+[string]$_.source+' '+[string]$_.summary).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0))})
    $Controls.count.Text='找到 '+$items.Count+' 条；收藏 '+$library.savedItems.Count+' 条'
  }
  if (-not $items.Count) { [void](Add-CompanionLabel $Panel '这里还没有匹配的新闻。可以调整筛选，或点“获取新消息”；获取完成后会自动显示。'); return }
  $limit=if($Controls -and $Controls.limit){[int]$Controls.limit}else{30}
  foreach ($item in $items | Select-Object -First $limit) {
    $box = New-Object System.Windows.Controls.StackPanel
    $box.Margin = New-Object System.Windows.Thickness(0, 5, 0, 14)
    [void]$Panel.Children.Add($box)
    $read=($library.readIds -contains [string]$item.id)
    [void](Add-CompanionLabel $box ($(if($read){'已读  '}else{''})+[string]$item.title) 15)
    $source = [string]$item.source
    if($item.language -eq 'en'){$source+=' · 英文原文'}
    $source += ' · ' + (Format-PetNewsTime ([string]$item.publishedAt))
    [void](Add-CompanionLabel $box $source 11)
    if ($item.summary) { [void](Add-CompanionLabel $box ([string]$item.summary) 12) }
    $actions=New-Object Windows.Controls.WrapPanel;[void]$box.Children.Add($actions)
    $open = Add-CompanionButton $actions '打开原文'
    $url = [string]$item.url; $open.IsEnabled = Test-PetNewsUrl $url
    $article=$item
    $open.Add_Click({Invoke-PetNewsItemAction 'open' $article $Controls $Panel}.GetNewClosure())
    if($Controls){
      $saved=@($library.savedItems|Where-Object{$_.id -eq $article.id}).Count -gt 0
      $save=Add-CompanionButton $actions $(if($saved){'取消收藏'}else{'收藏这条'})
      $save.Add_Click({Invoke-PetNewsItemAction 'save' $article $Controls $Panel}.GetNewClosure())
      if(-not $read){$mark=Add-CompanionButton $actions '标为已读';$mark.Add_Click({Invoke-PetNewsItemAction 'read' $article $Controls $Panel}.GetNewClosure())}
    }
  }
  if($Controls -and $items.Count -gt $limit){$more=Add-CompanionButton $Panel ('再看 '+[Math]::Min(30,$items.Count-$limit)+' 条');$more.Add_Click({$Controls.limit=[int]$Controls.limit+30;$Controls.signature='';Update-PetNewsWindow $Controls.dialog}.GetNewClosure())}
  if($scroll){$scroll.UpdateLayout();$scroll.ScrollToVerticalOffset($offset)}
}
function Invoke-PetNewsItemAction([string]$Action,$Item,$Controls,$Panel){
  try{
    $library=Get-PetNewsLibrary (Join-Path $PetHome 'news-library.json')
    if($Action -eq 'open'){if(-not (Open-PetNewsSource ([string]$Item.url))){throw '无法打开浏览器，可以稍后再试。'};$Action='read'}
    Set-PetNewsLibraryItem $library $Item $Action
    Write-Json (Join-Path $PetHome 'news-library.json') $library
    if($Controls){$Controls.status.Text=if($Action -eq 'save'){'收藏已更新，会随重启保留。'}else{'已经标为已读。'};$Controls.signature=''}
    Refresh-PetNewsInbox $Panel $Controls
  }catch{if($Controls){$Controls.status.Text=$_.Exception.Message}else{petLog $_.Exception.Message}}
}
function Test-PetNewsRefreshing {
  if(Get-Command Test-WhaleNewsRefreshing -ErrorAction SilentlyContinue){return [bool](Test-WhaleNewsRefreshing -PetHome $PetHome)}
  $file=Join-Path $PetHome 'news-refresh.lock'
  return ([IO.File]::Exists($file) -and ([DateTime]::UtcNow-[IO.File]::GetLastWriteTimeUtc($file)).TotalMinutes -lt 4)
}
function Get-PetNewsSourceHealthRows($Cache){
  $records=@{};foreach($record in @($Cache.sources)){if($record -and $record.id){$records[[string]$record.id]=$record}}
  $sources=if(Get-Command Get-WhaleNewsSources -ErrorAction SilentlyContinue){@(Get-WhaleNewsSources)}else{@($Cache.sources)}
  $topics=if(Get-Command Get-WhaleNewsTopics -ErrorAction SilentlyContinue){@(Get-WhaleNewsTopics $script:preferences)}else{@($script:preferences.newsTopics)}
  foreach($source in $sources){
    if(-not $source -or -not $source.id){continue}
    $record=$records[[string]$source.id]
    $selected=if(Get-Command Test-WhaleNewsSourceTopics -ErrorAction SilentlyContinue){Test-WhaleNewsSourceTopics $source $topics}else{$true}
    $state=if(-not $selected){'not-selected'}elseif(-not $record){'unchecked'}elseif($record.state){[string]$record.state}elseif($record.ok){'ok'}else{'failed'}
    $label=switch($state){'not-selected'{'未订阅话题'};'unchecked'{'尚未检查'};'ok'{'可用'};'empty'{'可连接，暂无匹配新闻'};'stale'{'更新较慢／可能停更'};'undated'{'缺少发布时间'};default{'本次失败'}}
    $lines=@([string]$source.name+' · '+$label+$(if($record -and $selected -and $record.count){' · 本次 '+$record.count+' 条'}else{''}))
    if($record){
      $checked=if($record.lastCheckedAt){[string]$record.lastCheckedAt}else{[string]$Cache.lastAttemptAt}
      if($checked){$lines+='检查：'+(Format-PetNewsTime $checked)}
      if($record.lastSuccessAt){$lines+='最近成功：'+(Format-PetNewsTime ([string]$record.lastSuccessAt))}
      if($record.newestPublishedAt){$lines+='最新文章：'+(Format-PetNewsTime ([string]$record.newestPublishedAt))}
      if($state -eq 'failed'){
        $reason=if($record.message){[string]$record.message}else{'来源暂不可用，已有新闻仍保留。'}
        $lines+='原因：'+$reason
      }
    }
    [pscustomobject]@{id=[string]$source.id;state=$state;selected=[bool]$selected;healthy=($state -in @('ok','empty'));text=($lines -join "`n")}
  }
}
function Update-PetNewsSourceHealth($Controls){
  if(-not $Controls.sourceHealthText){return}
  $rows=@(Get-PetNewsSourceHealthRows (Read-Json (Join-Path $PetHome 'news.json')))
  $selected=@($rows|Where-Object{$_.selected});$healthy=@($selected|Where-Object{$_.healthy})
  $Controls.sourceHealth.Header='来源健康 · '+$healthy.Count+' 个可用 / '+$selected.Count+' 个已订阅'
  $Controls.sourceHealthText.Text=if($rows.Count){(@($rows|ForEach-Object{$_.text}) -join "`n`n")}else{'还没有来源检查记录，获取新消息后会显示各来源结果。'}
}
function Update-PetNewsWindow($Dialog){
  $c=$Dialog.Tag.controls;$busy=Test-PetNewsRefreshing
  $c.refresh.IsEnabled=-not $busy
  if($busy){$c.status.Text='正在获取新消息，完成后会自动显示。'}
  else{
    $refreshState=Read-Json (Join-Path $PetHome 'news-refresh-status.json')
    $stateKey=if($refreshState){[string]$refreshState.at+'|'+[string]$refreshState.state}else{''}
    if($c.wasBusy -or ($stateKey -and $stateKey -cne $c.refreshStateKey)){
      $cache=Read-Json (Join-Path $PetHome 'news.json')
      if($refreshState.state -eq 'failed'){$c.status.Text=if($refreshState.message){[string]$refreshState.message}else{'这次获取没有完成，可以重试；原来的新闻已保留。'}}
      elseif($refreshState.state -in @('queued','running')){$c.status.Text='上次获取没有完成，可以重新获取；原来的新闻已保留。'}
      elseif($cache.status -eq 'offline' -or $refreshState.cacheStatus -eq 'offline'){$c.status.Text='这次未能连接来源，已保留原来的新闻。'}
      elseif($cache.status -eq 'partial' -or $refreshState.cacheStatus -eq 'partial'){$c.status.Text='新闻已更新；部分来源暂时不可用，稍后可以重试。'}
      elseif($refreshState.cacheStatus -eq 'disabled'){$c.status.Text='先在设置中选择感兴趣的新闻话题吧。'}
      else{$c.status.Text='新闻已更新，可以直接往下看。'}
      $c.refreshStateKey=$stateKey
    }
  }
  $c.wasBusy=$busy
  $filterKey=[string]$c.filter.SelectedIndex+'|'+[string]$c.topic.SelectedIndex+'|'+$c.search.Text
  if($c.filterKey -cne $filterKey){$c.filterKey=$filterKey;$c.limit=30}
  $signature=$filterKey+'|'+$c.limit
  $signature+='|'+(@($script:preferences.newsTopics)-join ',')
  foreach($name in @('news.json','news-library.json')){$file=Join-Path $PetHome $name;if([IO.File]::Exists($file)){$info=New-Object IO.FileInfo($file);$signature+='|'+$info.LastWriteTimeUtc.Ticks+':'+$info.Length}}
  if($signature -cne $c.signature){$c.signature=$signature;Refresh-PetNewsInbox $c.items $c;Update-PetNewsSourceHealth $c}
}
function Request-PetNewsRefresh($Dialog){
  $c=$Dialog.Tag.controls
  try{
    if(-not (Get-Command Start-WhaleNewsRefresh -ErrorAction SilentlyContinue)){throw '新闻组件暂时不可用。'}
    $started=Start-WhaleNewsRefresh -PetHome $PetHome
    if(-not $started -and -not (Test-PetNewsRefreshing)){throw '暂时无法开始更新，请稍后重试。'}
    Update-PetNewsWindow $Dialog
  }catch{$c.status.Text=$_.Exception.Message}
}
function New-PetNewsWindow {
  $dialog = New-CompanionWindow ($script:preferences.petName + ' · 新闻收件箱') 640 690
  $panel = $dialog.Tag.panel;$c=@{}
  [void](Add-CompanionLabel $panel '偶尔看看外面的世界' 21)
  [void](Add-CompanionLabel $panel '以下是公开来源的新闻摘要。发布时间、来源和原文链接会一起保留。')
  $actions = New-Object System.Windows.Controls.WrapPanel; [void]$panel.Children.Add($actions)
  $refresh = Add-CompanionButton $actions '获取新消息';$c.refresh=$refresh
  $c.filter=Add-CompanionChoice $actions @('全部新闻','只看未读','我的收藏')
  $c.topic=Add-CompanionChoice $actions @('全部话题','AI','科技','国内','国际','游戏')
  $c.search=Add-CompanionInput $panel '搜索标题、摘要或来源' '' 120
  $c.count=Add-CompanionLabel $panel '' 12
  $status = Add-CompanionLabel $panel '';$c.status=$status
  $sourceHealth=New-Object Windows.Controls.Expander;$sourceHealth.Header='来源健康';$sourceHealth.Margin=New-Object Windows.Thickness(0,4,0,10)
  $sourceScroll=New-Object Windows.Controls.ScrollViewer;$sourceScroll.MaxHeight=280;$sourceScroll.VerticalScrollBarVisibility='Auto'
  $sourceText=New-Object Windows.Controls.TextBlock;$sourceText.TextWrapping='Wrap';$sourceText.FontSize=11;$sourceText.Margin=New-Object Windows.Thickness(8)
  $sourceScroll.Content=$sourceText;$sourceHealth.Content=$sourceScroll;[void]$panel.Children.Add($sourceHealth)
  $c.sourceHealth=$sourceHealth;$c.sourceHealthText=$sourceText
  $itemsPanel = New-Object System.Windows.Controls.StackPanel; [void]$panel.Children.Add($itemsPanel)
  $c.items=$itemsPanel;$c.scroll=$dialog.Content;$c.dialog=$dialog;$c.limit=30;$dialog.Tag.controls=$c
  $refresh.Add_Click({Request-PetNewsRefresh $dialog}.GetNewClosure())
  $c.filter.Add_SelectionChanged({Update-PetNewsWindow $dialog}.GetNewClosure())
  $c.topic.Add_SelectionChanged({Update-PetNewsWindow $dialog}.GetNewClosure())
  $c.search.Add_TextChanged({Update-PetNewsWindow $dialog}.GetNewClosure())
  [void](Start-CompanionWindowTimer $dialog {Update-PetNewsWindow $dialog}.GetNewClosure())
  Update-PetNewsWindow $dialog
  return $dialog
}
function Show-PetNewsInbox {
  if ($script:newsWindow -and $script:newsWindow.IsVisible) { [void]$script:newsWindow.Activate(); return }
  $script:newsWindow = New-PetNewsWindow; $script:newsWindow.Show()
}
function Save-PetCommandResult([string]$ResultPath, [string]$CommandPath, $Result) {
  try {
    Write-Json $ResultPath $Result
    Remove-Item -LiteralPath $CommandPath -Force -ErrorAction SilentlyContinue
    [void]$script:handledCommands.Remove([string]$Result.id)
    return $true
  } catch { petLog ('command result could not be saved: ' + [string]$Result.id); return $false }
}
function Clear-OldPetCommandResults([string]$PetHome, [DateTime]$Now) {
  $day = $Now.ToString('yyyy-MM-dd')
  if ($script:commandCleanupDay -eq $day) { return }
  $script:commandCleanupDay = $day
  $folder = Join-Path $PetHome 'command-results'
  if (-not (Test-Path -LiteralPath $folder)) { return }
  $kept = 0
  foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
    # Pending commands keep their receipts so persistence retries can never execute them twice.
    if (Test-Path -LiteralPath (Join-Path (Join-Path $PetHome 'commands') $file.Name)) { continue }
    if ($file.LastWriteTimeUtc -lt $Now.ToUniversalTime().AddDays(-7) -or $kept -ge 1000) {
      Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    } else { $kept++ }
  }
}
function Process-PetCommands([string]$PetHome, [DateTime]$Now = [DateTime]::Now) {
  $inbox = Join-Path $PetHome 'commands'
  if (-not (Test-Path -LiteralPath $inbox)) { return }
  if (-not $script:handledCommands) { $script:handledCommands = @{} }
  Clear-OldPetCommandResults $PetHome $Now
  foreach ($file in @(Get-ChildItem -LiteralPath $inbox -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -First 25)) {
    $id = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($id -notmatch '^[a-zA-Z0-9_-]{8,80}$') { continue }
    $resultPath = Join-Path (Join-Path $PetHome 'command-results') ($id + '.json')
    if (Test-Path -LiteralPath $resultPath) {
      [void]$script:handledCommands.Remove($id)
      Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue; continue
    }
    if ($script:handledCommands.ContainsKey($id)) {
      [void](Save-PetCommandResult $resultPath $file.FullName $script:handledCommands[$id]); continue
    }
    $command = Read-Json $file.FullName
    $errorText = ''; $status = 'completed'; $completionMessage = ''
    try {
      if (-not $command -or [string]$command.id -ne $id) { throw '命令身份无效。' }
      $stamp=0.0
      if(-not [double]::TryParse([string]$command.at,[ref]$stamp) -or [double]::IsNaN($stamp) -or [double]::IsInfinity($stamp)){throw '命令时间无效。'}
      $age = [DateTimeOffset]::new($Now.ToUniversalTime()).ToUnixTimeMilliseconds() - $stamp
      if ($stamp -le 0 -or $age -lt -30000 -or $age -gt 300000) { throw '命令已经过期。' }
      if ($command.action -notin @('say', 'focus', 'cancel_focus', 'pause_focus', 'resume_focus', 'set_names', 'add_todo', 'set_todo_done', 'remind', 'refresh_news', 'open_panel')) { throw '不支持的陪伴动作。' }
      if ($command.action -eq 'say' -and ($script:away -or (-not $window.IsVisible -and $script:preferences.displayMode -ne 'native') -or $script:pending -or $script:focusUntil)) { continue }
      switch ([string]$command.action) {
        'say' {
          $text = ConvertTo-PetSingleLine ([string]$command.text) 240; if (-not $text) { throw '消息为空。' }
          if(-not $window.IsVisible -and $script:preferences.displayMode -eq 'native'){
            if(-not (Show-PetNativeNotice $text -Raw)){throw '通知暂时不可用，消息没有展示。'}
          }else{Say $text 7000 -Raw}
        }
        'focus' {
          if($script:companion.focus){throw '已经有一段专注正在进行或已暂停。请先查看、继续或结束当前专注。'}
          if($null -ne $command.minutes){
            $minutes=Get-PetBoundedNumber $command.minutes 0 5 180
            if(-not $minutes){throw '专注分钟数无效。'}
          }else{$minutes=[int]$script:preferences.focusMinutes}
          Start-Focus $minutes
        }
        'cancel_focus' { Cancel-Focus }
        'pause_focus' {
          if(-not $script:companion.focus){throw '目前没有正在进行的专注。'}
          if(-not $script:companion.focus.paused -and (Get-PetFocusRemainingSeconds $script:companion $Now) -le 0){throw '这次专注已经结束。'}
          Pause-PetFocus
        }
        'resume_focus' {
          if(-not $script:companion.focus){throw '目前没有可继续的专注。'}
          if(-not $script:companion.focus.paused){throw '专注已经在计时了。'}
          Resume-PetFocus
        }
        'open_panel' {
          switch([string]$command.panel){
            'tasks'{Show-PetTasks}
            'focus'{Show-PetFocus}
            'settings'{Show-PetSettings}
            'news'{Show-PetNewsInbox}
            'diagnostics'{if(-not (Get-Command Show-PetDiagnostics -ErrorAction SilentlyContinue)){throw '诊断面板暂时不可用。'};Show-PetDiagnostics}
            default{throw '请选择待办、专注、设置、新闻或诊断面板。'}
          }
        }
        'set_names' {
          $next = @{}; foreach ($key in $script:preferences.Keys) { $next[$key] = $script:preferences[$key] }
          foreach ($key in @('petName', 'userName')) {
            if ($null -ne $command.$key) {
              $name = ConvertTo-PetSingleLine ([string]$command.$key) 24
              if (-not $name) { throw '称呼不能为空。' }; $next[$key] = $name
            }
          }
          Write-Json $preferencesFile $next; $script:preferences = $next
          Update-PetIdentity;Update-Tray
        }
        'add_todo' {
          if (-not @($script:companion.tasks | Where-Object { $_.commandId -eq $id }).Count) {
            $next = Copy-PetCompanionData $script:companion
            $task = Add-PetTask $next ([string]$command.text); $task.commandId = $id
            Write-Json $companionFile $next; $script:companion = $next
          }
        }
        'set_todo_done' {
          if($command.done -isnot [bool]){throw '待办完成状态无效。'}
          $taskId=[string]$command.taskId
          if(-not $taskId -or -not @($script:companion.tasks|Where-Object{[string]$_.id -ceq $taskId}).Count){throw '没有找到这条待办，请先查看待办列表。'}
          $next=Copy-PetCompanionData $script:companion
          [void](Set-PetTaskDone $next $taskId ([bool]$command.done))
          Write-Json $companionFile $next;$script:companion=$next
        }
        'remind' {
          if (-not @($script:companion.reminders | Where-Object { $_.commandId -eq $id }).Count) {
            $minutes = Get-PetBoundedNumber $command.minutes 0 1 1440
            if (-not $minutes) { throw '提醒分钟数无效。' }
            $next = Copy-PetCompanionData $script:companion
            $reminder = Add-PetReminder $next ([string]$command.text) $minutes $Now; $reminder.commandId = $id
            Write-Json $companionFile $next; $script:companion = $next
          }
        }
        'refresh_news' {
          if (-not (Get-Command Start-WhaleNewsRefresh -ErrorAction SilentlyContinue)) { throw '新闻组件不可用。' }
          $started=Start-WhaleNewsRefresh -PetHome $PetHome
          if($started){$completionMessage='已请求后台刷新，新闻是否更新请查看新闻状态。'}
          elseif((Get-Command Test-WhaleNewsRefreshing -ErrorAction SilentlyContinue) -and (Test-WhaleNewsRefreshing -PetHome $PetHome)){$completionMessage='已有新闻刷新正在进行中，请稍后查看新闻状态。'}
          else{throw '新闻刷新没有启动，请稍后重试或打开新闻面板检查。'}
        }
      }
    } catch { $status = 'failed'; $errorText = $_.Exception.Message }
    $result = @{ id = $id; status = $status; error = $errorText; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    if($completionMessage){$result.message=$completionMessage}
    $script:handledCommands[$id] = $result
    [void](Save-PetCommandResult $resultPath $file.FullName $result)
  }
}
