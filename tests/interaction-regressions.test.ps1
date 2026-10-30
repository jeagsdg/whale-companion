$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$source=Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-pet.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors){throw ($errors|Out-String)}
foreach($name in @('Get-RpsOutcome','Invoke-PetRps','Show-Pet','Hide-Pet','Set-PetDisplayMode')){
  $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
  . ([scriptblock]::Create($fn.Extent.Text))
}
function Say($text,$ms){}
function Pick-Line($key){return $key}
function Show-Pose($pose,$ms){}
function Save-Stats{$script:saves++}
function Add-Xp($n,$reason){$script:xp+=$n}
function Unlock($id,$pose,$text){}
function petLog($message){}
function Get-Random{return $script:opponent}
$script:stats=@{rpsWin=0;rpsLose=0;rpsStreak=0};$script:saves=0;$script:xp=0
$handler=$ast.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_Click' -and $n.Arguments[0].Extent.Text -match 'Invoke-PetRps'},$true).Arguments[0].ScriptBlock.GetScriptBlock()
$pick=New-Object Windows.Controls.MenuItem;$pick.Tag='石头';$pick.Add_Click($handler)
$script:opponent='剪刀';$pick.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.MenuItem]::ClickEvent)))
if($script:stats.rpsWin -ne 1 -or $script:xp -ne 4 -or $script:saves -ne 1){throw 'Real menu click did not persist the winning round.'}
$script:opponent='布';$pick.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.MenuItem]::ClickEvent)))
if($script:stats.rpsLose -ne 1 -or $script:stats.rpsStreak -ne 0 -or $script:saves -ne 2){throw 'Real menu click did not persist the losing round.'}
$script:opponent='石头';$pick.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.MenuItem]::ClickEvent)))
if($script:stats.rpsWin -ne 1 -or $script:stats.rpsLose -ne 1 -or $script:saves -ne 2){throw 'Draw changed the saved score.'}
$script:moods=@()
function Show-PetMood([string]$Mood){$script:moods+=,$Mood}
$moodHandler=$ast.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Add_Click' -and $n.Arguments[0].Extent.Text -match 'Show-PetMood'},$true).Arguments[0].ScriptBlock.GetScriptBlock()
foreach($id in @('tired','happy')){
  $item=New-Object Windows.Controls.MenuItem;$item.Tag=$id;$item.Add_Click($moodHandler)
  $item.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.MenuItem]::ClickEvent)))
}
if(($script:moods -join ',') -ne 'tired,happy'){throw 'Mood menu lost the clicked item identity.'}
$window=[PSCustomObject]@{IsVisible=$true;Topmost=$false}
$window|Add-Member ScriptMethod Hide {$this.IsVisible=$false}
$window|Add-Member ScriptMethod Show {$this.IsVisible=$true}
$fxCanvas=New-Object Windows.Controls.Canvas
[void]$fxCanvas.Children.Add((New-Object Windows.Shapes.Ellipse))
$script:bubbles=@(@{el='test'});$script:visibilityWrites=@()
$hiddenFile=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()+'.json')
$showFile=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()+'.json')
function Write-Json($path,$value){$script:visibilityWrites+=,$value}
function Show-GentleReminder{}
function Update-Tray{}
Set-PetDisplayMode 'native'
if($window.IsVisible -or $fxCanvas.Children.Count -ne 0 -or $script:bubbles.Count -ne 0){throw 'Native mode did not hide the old character and stop its particles.'}
Set-PetDisplayMode 'desktop'
if(-not $window.IsVisible -or -not $window.Topmost){throw 'Explicit desktop mode did not restore the character.'}
'Interaction menu regressions passed.'
