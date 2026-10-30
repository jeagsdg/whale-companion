# Focus controls share the persisted companion model; timers update presentation only.
function Pause-PetFocus {
  if(-not $script:companion.focus -or $script:companion.focus.paused){return}
  $remaining=Get-PetFocusRemainingSeconds $script:companion
  if($remaining -le 0){Update-Companion ([DateTime]::Now);return}
  $next=Copy-PetCompanionData $script:companion
  $next.focus=@{minutes=[int]$script:companion.focus.minutes;until='';paused=$true;remainingSeconds=$remaining}
  Write-Json $companionFile $next
  $script:companion=$next;$script:focusUntil=$null;Update-Tray
}
function Resume-PetFocus {
  if(-not $script:companion.focus.paused){return}
  $next=Copy-PetCompanionData $script:companion
  $deadline=[DateTime]::Now.AddSeconds([int]$next.focus.remainingSeconds)
  $next.focus=@{minutes=[int]$next.focus.minutes;until=$deadline.ToUniversalTime().ToString('o')}
  Write-Json $companionFile $next
  $script:companion=$next;$script:focusUntil=$deadline;Update-Tray
}
function Update-PetFocusWindow($Dialog){
  $c=$Dialog.Tag.controls;$focus=$script:companion.focus
  $seconds=Get-PetFocusRemainingSeconds $script:companion
  if($focus){
    $span=[TimeSpan]::FromSeconds($seconds)
    $c.clock.Text=if($seconds -ge 3600){$span.ToString('hh\:mm\:ss')}else{$span.ToString('mm\:ss')}
    $c.progress.Value=[Math]::Max(0,[Math]::Min(100,100*(1-$seconds/([double]$focus.minutes*60))))
    $c.state.Text=if($focus.paused){'已经暂停。回来时点继续，剩余时间不会偷偷走掉。'}else{'正在专注。临时有事可以暂停，做完再回来。'}
    $c.pause.Content=if($focus.paused){'继续专注'}else{'暂停一下'}
  }else{
    $c.clock.Text='准备好了';$c.progress.Value=0
    $c.state.Text='只做眼前这一件事。选一个时长，我们一起开始。'
  }
  $c.start.IsEnabled=-not [bool]$focus;$c.minutes.IsEnabled=-not [bool]$focus
  $c.pause.IsEnabled=[bool]$focus;$c.cancel.IsEnabled=[bool]$focus
  $c.summary.Text='已经完成 '+[int]$script:companion.focusCompletedCount+' 次专注。每一次开始都算数。'
}
function Invoke-PetFocusAction([string]$Action,$Dialog){
  $c=$Dialog.Tag.controls
  try{
    switch($Action){
      'start'{$minutes=0;if(-not [int]::TryParse($c.minutes.Text,[ref]$minutes) -or $minutes -lt 5 -or $minutes -gt 180){throw '请输入 5 到 180 分钟。'};Start-Focus $minutes}
      'pause'{if($script:companion.focus.paused){Resume-PetFocus}else{Pause-PetFocus}}
      'cancel'{Cancel-Focus}
    }
    $c.status.Text='';Update-PetFocusWindow $Dialog
  }catch{$c.status.Text='未能保存：'+$_.Exception.Message}
}
function New-PetFocusWindow {
  $dialog=New-CompanionWindow ($script:preferences.petName+' · 陪我专注') 490 520
  $panel=$dialog.Tag.panel;$c=@{}
  [void](Add-CompanionLabel $panel '留一点时间，只做一件事' 21)
  $c.clock=Add-CompanionLabel $panel '' 42
  $c.clock.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#127C91')
  $c.progress=New-Object Windows.Controls.ProgressBar;$c.progress.Height=7;$c.progress.Maximum=100
  [void]$panel.Children.Add($c.progress)
  $c.state=Add-CompanionLabel $panel ''
  $c.minutes=Add-CompanionInput $panel '专注多久（分钟）' $script:preferences.focusMinutes 3
  $presets=New-Object Windows.Controls.WrapPanel;[void]$panel.Children.Add($presets)
  foreach($duration in @(15,25,45,60)){
    $preset=Add-CompanionButton $presets ($duration.ToString()+' 分钟');$value=[string]$duration
    $preset.Add_Click({if($c.minutes.IsEnabled){$c.minutes.Text=$value}}.GetNewClosure())
  }
  $row=New-Object Windows.Controls.WrapPanel;[void]$panel.Children.Add($row)
  $c.start=Add-CompanionButton $row '开始专注';$c.start.Add_Click({Invoke-PetFocusAction 'start' $dialog}.GetNewClosure())
  Set-CompanionPrimaryButton $c.start
  $c.pause=Add-CompanionButton $row '暂停一下';$c.pause.Add_Click({Invoke-PetFocusAction 'pause' $dialog}.GetNewClosure())
  $c.cancel=Add-CompanionButton $row '结束本次';$c.cancel.Add_Click({Invoke-PetFocusAction 'cancel' $dialog}.GetNewClosure())
  $c.summary=Add-CompanionLabel $panel '' 12;$c.status=Add-CompanionLabel $panel '' 12
  $dialog.Tag.controls=$c
  [void](Start-CompanionWindowTimer $dialog {Update-PetFocusWindow $dialog}.GetNewClosure())
  Update-PetFocusWindow $dialog
  return $dialog
}
function Show-PetFocus {
  if($script:focusWindow -and $script:focusWindow.IsVisible){[void]$script:focusWindow.Activate();return}
  $script:focusWindow=New-PetFocusWindow;$script:focusWindow.Show()
}
