<#
  Whale Musume desktop pet (polished).
  - bubble sits right above her head and has a tail pointing at her
  - approval card only appears while an approval is really pending
  - idle: breathing bob, wink flashes, occasional hop, occasional short walk
  - tray icon with menu; drag anywhere; double click raises the selected host
#>
param([string]$PetHome = $PSScriptRoot)
$commonFile = Join-Path $PSScriptRoot 'whale-pet-common.ps1'
. $commonFile
$uiCreated = $false
$script:uiMutex = New-Object System.Threading.Mutex($true, (Get-PetMutexName 'UI' $PetHome), [ref]$uiCreated)
if (-not $uiCreated) { $script:uiMutex.Dispose(); exit 0 }
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$stateFile    = Join-Path $PetHome 'state.json'
$posFile      = Join-Path $PetHome 'position.json'
$linesFile    = Join-Path $PetHome 'lines.json'
$icoFile      = Join-Path $PetHome 'assets\whale.ico'
$activateFile = Join-Path (Split-Path -Parent $PetHome) 'dsh-desktop-notify.activate'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$petLogFile = Join-Path (Split-Path -Parent $PetHome) 'dsh-whale-pet.log'
$statsFile = Join-Path $PetHome 'pet-stats.json'
$showFile = Join-Path $PetHome 'show.json'
$aliveFile = Join-Path $PetHome 'alive.json'
$hiddenFile = Join-Path $PetHome 'hidden.json'
$controlFile = Join-Path $PetHome 'control.json'
$preferencesFile = Join-Path $PetHome 'pet-preferences.json'
$companionFile = Join-Path $PetHome 'companion-data.json'
$companionModuleRoot = $PSScriptRoot
. (Join-Path $companionModuleRoot 'whale-companion.ps1')
. (Join-Path $companionModuleRoot 'whale-companion-ui.ps1')
foreach ($optionalModule in @('whale-host.ps1', 'whale-news.ps1', 'whale-diagnostics.ps1')) {
  $modulePath = Join-Path $companionModuleRoot $optionalModule
  if (Test-Path -LiteralPath $modulePath) { . $modulePath }
}
function petLog([string]$m) { try { [System.IO.File]::AppendAllText($petLogFile, ((Get-Date).ToString('s') + ' ' + $m + "`n"), $utf8) } catch { } }
function Read-Json([string]$p) { return (Read-PetJson $p) }
function Write-Json([string]$p, $o) { Write-PetJson $p $o }
function Read-Record([string]$p, [hashtable]$defaults) {
  $saved = Read-Json $p
  $record = @{}
  foreach ($key in $defaults.Keys) { $record[$key] = $defaults[$key] }
  if ($saved -is [System.Collections.IDictionary]) {
    foreach ($key in $saved.Keys) { $record[$key] = $saved[$key] }
  } elseif ($saved) {
    foreach ($property in $saved.PSObject.Properties) { $record[$property.Name] = $property.Value }
  }
  return $record
}
$oldPosition = Read-Json $posFile
$oldWalk = if ($null -ne $oldPosition.walk) { [bool]$oldPosition.walk } else { $true }
$preferenceDefaults = Get-PetPreferenceDefaults
$preferenceDefaults.walk = $oldWalk
$script:preferences = Repair-PetPreferences (Read-Record $preferencesFile $preferenceDefaults)
Write-Json $preferencesFile $script:preferences
$script:companion = Get-PetCompanionData $companionFile
$lines = Read-Json $linesFile
function Pick-Line([string]$k) { try { $b = $lines.$k; if ($b -and $b.Count -gt 0) { return [string]$b[(Get-Random -Minimum 0 -Maximum $b.Count)] } } catch { }; return '' }
function Brush([int]$a, [int]$r, [int]$g, [int]$b) { return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb($a, $r, $g, $b))) }

$cyan = Brush 255 56 189 248
$cyanSoft = Brush 150 56 189 248
$deep = Brush 246 8 24 42
$deep2 = Brush 250 6 20 36

$window = New-Object System.Windows.Window
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.Width = 300
$window.SizeToContent = [System.Windows.SizeToContent]::Height
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
$window.Title = $script:preferences.petName + ' · 桌面陪伴'

# vertical stack: [card] [bubble] [her]  -> bubble always hugs her head
$stack = New-Object System.Windows.Controls.StackPanel
$stack.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
$rootGrid = New-Object System.Windows.Controls.Grid
[void]$rootGrid.Children.Add($stack)
$fxCanvas = New-Object System.Windows.Controls.Canvas
$fxCanvas.Background = $null
[void]$rootGrid.Children.Add($fxCanvas)
$window.Content = $rootGrid

# ---------- approval card ----------
$card = New-Object System.Windows.Controls.Border
$card.Background = $deep2
$card.BorderBrush = $cyan
$card.BorderThickness = New-Object System.Windows.Thickness(2)
$card.CornerRadius = New-Object System.Windows.CornerRadius(16)
$card.Padding = New-Object System.Windows.Thickness(12, 10, 12, 11)
$card.Margin = New-Object System.Windows.Thickness(6, 0, 6, 6)
$card.Visibility = [System.Windows.Visibility]::Collapsed
$cardShadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$cardShadow.Color = [System.Windows.Media.Colors]::Black
$cardShadow.BlurRadius = 26
$cardShadow.ShadowDepth = 8
$cardShadow.Opacity = 0.6
$card.Effect = $cardShadow
$cardStack = New-Object System.Windows.Controls.StackPanel
$headRow = New-Object System.Windows.Controls.StackPanel
$headRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$dot = New-Object System.Windows.Shapes.Ellipse
$dot.Width = 9; $dot.Height = 9
$dot.Fill = $cyan
$dot.Margin = New-Object System.Windows.Thickness(0, 3, 7, 0)
$headText = New-Object System.Windows.Controls.TextBlock
$headText.Text = $script:preferences.petName + ' · 等你看看'
$headText.Foreground = (Brush 220 148 200 240)
$headText.FontSize = 11
$headText.FontFamily = 'Microsoft YaHei UI'
[void]$headRow.Children.Add($dot)
[void]$headRow.Children.Add($headText)
$cardTool = New-Object System.Windows.Controls.TextBlock
$cardTool.Foreground = (Brush 255 125 211 252)
$cardTool.FontSize = 14
$cardTool.FontWeight = [System.Windows.FontWeights]::Bold
$cardTool.TextWrapping = [System.Windows.TextWrapping]::Wrap
$cardTool.FontFamily = 'Microsoft YaHei UI'
$cardTool.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
$cardReason = New-Object System.Windows.Controls.TextBlock
$cardReason.Foreground = (Brush 235 214 226 240)
$cardReason.FontSize = 11.5
$cardReason.TextWrapping = [System.Windows.TextWrapping]::Wrap
$cardReason.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
$cardReason.MaxHeight = 76
$cardReason.FontFamily = 'Microsoft YaHei UI'
$buttons = New-Object System.Windows.Controls.WrapPanel
$buttons.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$buttons.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
$btnGo = New-Object System.Windows.Controls.Button
$btnGo.Content = '带我去看 →'
$btnGo.FontSize = 12.5
$btnGo.FontFamily = 'Microsoft YaHei UI'
$btnGo.Foreground = (Brush 255 186 230 253)
$btnGo.Background = (Brush 40 56 189 248)
$btnGo.BorderBrush = (Brush 200 56 189 248)
$btnGo.BorderThickness = New-Object System.Windows.Thickness(1.2)
$btnGo.Padding = New-Object System.Windows.Thickness(12, 8, 12, 8)
$btnGo.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
$btnGo.Cursor = [System.Windows.Input.Cursors]::Hand
$btnGo.Visibility = [System.Windows.Visibility]::Collapsed
$btnYes = New-Object System.Windows.Controls.Button
$btnYes.Content = '√  允许一次'
$btnYes.FontSize = 13.5; $btnYes.FontWeight = [System.Windows.FontWeights]::Bold
$btnYes.FontFamily = 'Microsoft YaHei UI'
$btnYes.Foreground = (Brush 255 5 46 43)
$btnYes.Background = (Brush 255 52 211 153)
$btnYes.BorderThickness = New-Object System.Windows.Thickness(0)
$btnYes.Padding = New-Object System.Windows.Thickness(14, 8, 14, 8)
$btnYes.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
$btnYes.Cursor = [System.Windows.Input.Cursors]::Hand
$btnNo = New-Object System.Windows.Controls.Button
$btnNo.Content = '×  拒绝'
$btnNo.FontSize = 13.5; $btnNo.FontWeight = [System.Windows.FontWeights]::Bold
$btnNo.FontFamily = 'Microsoft YaHei UI'
$btnNo.Foreground = (Brush 255 253 164 175)
$btnNo.Background = (Brush 40 251 113 133)
$btnNo.BorderBrush = (Brush 220 251 113 133)
$btnNo.BorderThickness = New-Object System.Windows.Thickness(1.4)
$btnNo.Padding = New-Object System.Windows.Thickness(14, 8, 14, 8)
$btnNo.Cursor = [System.Windows.Input.Cursors]::Hand
[void]$buttons.Children.Add($btnYes)
[void]$buttons.Children.Add($btnNo)
[void]$buttons.Children.Add($btnGo)
[void]$cardStack.Children.Add($headRow)
[void]$cardStack.Children.Add($cardTool)
[void]$cardStack.Children.Add($cardReason)
[void]$cardStack.Children.Add($buttons)
$card.Child = $cardStack
[void]$stack.Children.Add($card)

# ---------- bubble (with a tail pointing at her) ----------
$bubbleBox = New-Object System.Windows.Controls.StackPanel
$bubbleBox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$bubbleBox.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
$bubbleBox.Visibility = [System.Windows.Visibility]::Collapsed
$bubble = New-Object System.Windows.Controls.Border
$bubble.Background = $deep
$bubble.BorderBrush = $cyanSoft
$bubble.BorderThickness = New-Object System.Windows.Thickness(1.3)
$bubble.CornerRadius = New-Object System.Windows.CornerRadius(15)
$bubble.Padding = New-Object System.Windows.Thickness(12, 8, 12, 8)
$bubble.MaxWidth = 262
$bubbleText = New-Object System.Windows.Controls.TextBlock
$bubbleText.Foreground = [System.Windows.Media.Brushes]::White
$bubbleText.FontSize = 13
$bubbleText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$bubbleText.FontFamily = 'Microsoft YaHei UI'
$bubbleText.TextAlignment = [System.Windows.TextAlignment]::Center
$bubbleContent=New-Object System.Windows.Controls.StackPanel
$bubbleNameText=New-Object System.Windows.Controls.TextBlock
$bubbleNameText.FontSize=10;$bubbleNameText.Foreground=$cyanSoft;$bubbleNameText.TextAlignment=[System.Windows.TextAlignment]::Center
$bubbleNameText.MaxWidth=240;$bubbleNameText.TextTrimming=[Windows.TextTrimming]::CharacterEllipsis
$bubbleNameText.Margin=New-Object System.Windows.Thickness(0,0,0,4)
[void]$bubbleContent.Children.Add($bubbleNameText);[void]$bubbleContent.Children.Add($bubbleText)
$bubble.Child = $bubbleContent
$tail = New-Object System.Windows.Shapes.Polygon
$pts = New-Object System.Windows.Media.PointCollection
$pts.Add((New-Object System.Windows.Point(0, 0)))
$pts.Add((New-Object System.Windows.Point(18, 0)))
$pts.Add((New-Object System.Windows.Point(9, 10)))
$tail.Points = $pts
$tail.Fill = $deep
$tail.Stroke = $cyanSoft
$tail.StrokeThickness = 1.3
$tail.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$tail.Margin = New-Object System.Windows.Thickness(0, -1, 0, 0)
[void]$bubbleBox.Children.Add($bubble)
[void]$bubbleBox.Children.Add($tail)
[void]$stack.Children.Add($bubbleBox)

# ---------- her ----------
$image = New-Object System.Windows.Controls.Image
$image.Width = 250; $image.Height = 250
$image.Stretch = [System.Windows.Media.Stretch]::Uniform
$image.Cursor = [System.Windows.Input.Cursors]::SizeAll
$image.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.9)
$tf = New-Object System.Windows.Media.TransformGroup
$translate = New-Object System.Windows.Media.TranslateTransform
$scale = New-Object System.Windows.Media.ScaleTransform(1, 1)
$tf.Children.Add($scale); $tf.Children.Add($translate)
$image.RenderTransform = $tf
$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$shadow.Color = [System.Windows.Media.Colors]::Black
$shadow.BlurRadius = 24; $shadow.ShadowDepth = 7; $shadow.Opacity = 0.6
$image.Effect = $shadow
[void]$stack.Children.Add($image)

# ---------- state ----------
$script:pending = $null
$script:decidedIds = @{}
$script:cache = @{}
$script:forcedPose = $null; $script:forcedUntil = $null
$script:lastPose = ''
$script:lastLine = ''
$script:bubbleUntil = $null
$script:walk = [bool]$script:preferences.walk
$script:feetBottom = 0
$script:dragStart = $null; $script:dragged = $false
$script:tick = 0; $script:hopUntil = $null; $script:winkUntil = $null; $script:popUntil = $null; $script:pulse = 0
$script:idleNextAt = [DateTime]::Now.AddSeconds(14)
$script:nightMode = $false
$script:mouseSaid = [DateTime]::MinValue
$script:rapid = 0; $script:rapidSince = [DateTime]::MinValue
$script:away = $false; $script:awaySince = [DateTime]::Now; $script:birds = 0; $script:lastNote = ''; $script:bubbleNextAt = [DateTime]::Now.AddSeconds(120)
$script:stickerNextAt = [DateTime]::Now.AddSeconds(60)
$script:focusUntil = Get-PetFocusDeadline $script:companion
$script:focusMinutes = if ($script:companion.focus) { [int]$script:companion.focus.minutes } else { [int]$script:preferences.focusMinutes }
$script:breakNextAt = [DateTime]::Now.AddMinutes(50)
$script:gentleReminder = ''
$script:lastState = $null
$script:stateNextAt = [DateTime]::MinValue
$script:maintenanceNextAt = [DateTime]::MinValue
$script:greetAt = $null
$script:lastNewsNotice = ''
$script:newsNextAt = [DateTime]::Now.AddSeconds(20)
$script:catalog = Read-Json (Join-Path $PetHome 'sticker-catalog.json')
$IDLE_DAY = @('v3-hello','v3-calm','v3-tea','v3-received','v3-comfort')
$IDLE_NIGHT = @('v3-calm','v3-tired','v3-tea')
$IDLE_LINES=@{
  'v3-hello'='{user}，{pet}在这儿呢，想说话时就摸摸头。'
  'v3-calm'='肩膀放松一点，{user}。{pet}安静陪着你。'
  'v3-tea'='{user}，喝口水吧，给自己充一点电。'
  'v3-received'='收到，{user}。需要帮忙的时候，{pet}就在这里。'
  'v3-comfort'='{user}，慢慢来也没关系，{pet}陪着你。'
  'v3-tired'='累了就歇一小会儿，{user}。{pet}不催你。'
}

function Load-Pose([string]$key) {
  $p=Get-PetPosePath $key
  if(-not $script:poseCacheOrder){$script:poseCacheOrder=New-Object 'Collections.Generic.List[string]'}
  [void]$script:poseCacheOrder.Remove($p);$script:poseCacheOrder.Add($p)
  if($script:cache.ContainsKey($p)){return $script:cache[$p]}
  try{
    $b=Read-PetBitmap $p 320;$script:cache[$p]=$b
    while($script:poseCacheOrder.Count -gt 8){$old=$script:poseCacheOrder[0];$script:poseCacheOrder.RemoveAt(0);$script:cache.Remove($old)}
    return $b
  }catch{return $null}
}
# ---------- 表情包状态表（中英双字幕，和贴纸一套） ----------
$STICKERS = @(
  @{ p = 'success'; cn = '搞定'; en = "Done" },
  @{ p = 'failure'; cn = '又炸了'; en = "It broke" },
  @{ p = 'abstract'; cn = '我裂开了'; en = "I'm broken" },
  @{ p = 'star'; cn = '绝了'; en = "Amazing" },
  @{ p = 'meme-omg'; cn = '离谱'; en = "No way" },
  @{ p = 'meme-doge'; cn = '就这？'; en = "That's it?" },
  @{ p = 'afk'; cn = '摸鱼中'; en = "Slacking" },
  @{ p = 'daily-eat'; cn = '干饭时间'; en = "Food time" },
  @{ p = 'daily-pajama'; cn = '下班了'; en = "Off duty" },
  @{ p = 'daily-coffee'; cn = '续命中'; en = "Coffee" },
  @{ p = 'meme-worship'; cn = '大佬带带我'; en = "Teach me" },
  @{ p = 'meme-sike'; cn = '想得美'; en = "Nice try" },
  @{ p = 'meme-smile-pain'; cn = '我没事'; en = "I'm fine" },
  @{ p = 'meme-kyun'; cn = '心动'; en = "Heartbeat" },
  @{ p = 'meme-heart'; cn = '爱你'; en = "Love you" },
  @{ p = 'angry'; cn = '别惹我'; en = "Don't" },
  @{ p = 'blush'; cn = '害羞'; en = "Blush" },
  @{ p = 'meme-shock'; cn = '震惊'; en = "Shocked" },
  @{ p = 'work-meeting'; cn = '开会中'; en = "Meeting" },
  @{ p = 'work-debug'; cn = '修 bug 中'; en = "Debugging" },
  @{ p = 'work-deploy'; cn = '上线了'; en = "Deploying" },
  @{ p = 'work-pat'; cn = '加油'; en = "You got this" },
  @{ p = 'sleep'; cn = '睡了'; en = "Sleeping" },
  @{ p = 'idle-cute'; cn = '在的'; en = "I'm here" },
  @{ p = 'waiting'; cn = '等你'; en = "Waiting" },
  @{ p = 'daily-melt'; cn = '化了'; en = "Melting" },
  @{ p = 'meme-ojisan'; cn = '想当年'; en = "Back then" },
  @{ p = 'meme-music'; cn = '听歌中'; en = "Music on" },
  @{ p = 'meme-peace'; cn = '随缘'; en = "Whatever" },
  @{ p = 'cool-shades'; cn = '稳'; en = "Too cool" },
  @{ p = 'react-head'; cn = '摸摸头'; en = "Pat pat" },
  @{ p = 'game-win'; cn = '赢了'; en = "I win" },
  @{ p = 'game-lose'; cn = '输了'; en = "I lost" },
  @{ p = 'celebrate'; cn = '好耶'; en = "Yay" },
  @{ p = 'levelup'; cn = '升级了'; en = "Level up" },
  @{ p = 'work-boss'; cn = '老板来了'; en = "Boss is here" },
  @{ p = 'work-deadline'; cn = '要 deadline 了'; en = "Deadline!" },
  @{ p = 'meme-broke'; cn = '吃土'; en = "Broke" },
  @{ p = 'daily-gaming'; cn = '打游戏'; en = "Gaming" },
  @{ p = 'meme-doubt'; cn = '你确定？'; en = "You sure?" },
  @{ p = 'meme-no'; cn = '不行'; en = "Nope" },
  @{ p = 'meme-yes'; cn = '可以'; en = "Yes" }
)
function Show-Sticker([int]$hold = 4200) {
  try {
    if ($script:catalog -and $script:catalog.stickers) {
      $pool=@($script:catalog.stickers|Where-Object{$_.recommended -eq $true});if(-not $pool.Count){$pool=@($script:catalog.stickers)}
      Show-CatalogSticker ($pool | Get-Random) $hold
      return
    }
    $s = $STICKERS | Get-Random
    Show-Pose $s.p $hold
    Say ($s.cn + ' · ' + $s.en) ($hold - 400)
    petLog ('sticker ' + $s.cn + '/' + $s.en)
  } catch { }
}
function Show-CatalogSticker($Sticker, [int]$Hold = 4600) {
  if (-not $Sticker -or [string]$Sticker.pose -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { return }
  Show-Pose ([string]$Sticker.pose) $Hold
  Say ([string]$Sticker.caption + $(if ($Sticker.en -and $Sticker.recommended -ne $true) { ' · ' + [string]$Sticker.en } else { '' })) ($Hold - 300) -Raw
}
function Copy-CurrentSticker {
  try {
    if ($image.Source) {
      $data=New-PetStickerClipboardData (Get-PetPosePath $script:lastPose)
      [Windows.Clipboard]::SetDataObject($data,$true)
      Say '纯净表情复制好了，支持 PNG 的应用会保留透明背景。' 4000
    }
  } catch { Say '剪贴板暂时被占用了，过一会儿再试试吧。' 3200 }
}
function Add-PetCatalogMenu($Menu) {
  if (-not $script:catalog -or -not $script:catalog.stickers) { return }
  foreach($recommended in @($true,$false)){
  $catalogMenu = New-Object System.Windows.Controls.MenuItem; $catalogMenu.Header = if($recommended){'常用表情 · 新版 🎨'}else{'旧版表情 · 保留浏览'}
  foreach ($group in $script:catalog.groups) {
    $groupMenu = New-Object System.Windows.Controls.MenuItem; $groupMenu.Header = [string]$group.label
    foreach ($sticker in @($script:catalog.stickers | Where-Object { $_.group -eq $group.id -and ($_.recommended -eq $true) -eq $recommended })) {
      $item = New-Object System.Windows.Controls.MenuItem; $item.Header = [string]$sticker.caption
      $item.Tag=$sticker;$item.Add_Click({Show-CatalogSticker $this.Tag 15000})
      [void]$groupMenu.Items.Add($item)
    }
    if ($groupMenu.Items.Count) { [void]$catalogMenu.Items.Add($groupMenu) }
  }
  [void]$Menu.Items.Add($catalogMenu)
  }
}
function Show-PetMood([string]$Mood) {
  $responses = @{
    tired = @{ pose = 'v3-tired'; lines = @('{user}，{pet}陪你歇一会儿。先放下肩膀，喝口水，事情可以等一下。','{user}，电量低的时候不用硬撑。{pet}在这里，先给自己留一点休息时间。') }
    low = @{ pose = 'v3-comfort'; lines = @('{user}，今天不必表现得很厉害。{pet}先陪着你，不急着把心情变好。','想安静坐一会儿也可以，{user}。{pet}在这里，不催你。') }
    happy = @{ pose = 'v3-happy'; lines = @('{user}，这份开心{pet}收到了！可以给自己一点掌声，今天值得记住。','好耶，{user}！{pet}也跟着开心起来了，想分享的时候我就听着。') }
    anxious = @{ pose = 'v3-calm'; lines = @('{user}，先慢慢呼一口气。{pet}陪你只看眼前最小的一步，不必一次解决所有事情。','{user}，先把手松开、肩膀放下来。我们把没做完的事记到待办里，慢慢来。') }
    angry = @{ pose = 'v3-calm'; lines = @('{user}，先不用急着回复或做决定。{pet}陪你缓一下，等舒服一点再处理。') }
    overwhelmed = @{ pose = 'v3-comfort'; lines = @('{user}，事情太多的时候，我们先只选一件最小的。其余交给待办，{pet}陪你一步一步来。') }
  }
  if ($responses.ContainsKey($Mood)) {
    $response = $responses[$Mood];Show-Pose $response.pose 15000
    $line=@($response.lines)|Where-Object{$_ -ne $script:lastMoodLine}|Get-Random
    if(-not $line){$line=$response.lines[0]};$script:lastMoodLine=$line
    Say $line 12000
  }
}

$script:stats = Read-Record $statsFile @{ pats = 0; clicks = 0; approvals = 0; level = 1; xp = 0; streak = 0; lastDay = ''; achievements = @(); rpsWin = 0; rpsLose = 0; rpsStreak = 0; bubbles = 0; birds = 0; focusSessions = 0 }
$script:stats.achievements = @($script:stats.achievements | Where-Object { $_ })
if ([int]$script:stats.level -lt 1) { $script:stats.level = 1 }
$script:companion.focusCompletedCount=[Math]::Max([int]$script:companion.focusCompletedCount,[int]$script:stats.focusSessions)
$script:stats.focusSessions=$script:companion.focusCompletedCount
function Save-Stats { try { $script:stats.focusSessions=[Math]::Max([int]$script:stats.focusSessions,[int]$script:companion.focusCompletedCount); Write-Json $statsFile $script:stats } catch { petLog ('stats save failed: '+$_.Exception.Message) } }
function Add-Xp([int]$n, [string]$why) {
  try {
    $script:stats.xp = [int]$script:stats.xp + $n
    $need = 20 * [int]$script:stats.level
    if ($script:stats.xp -ge $need) {
      $script:stats.xp = 0
      $script:stats.level = [int]$script:stats.level + 1
      if ($why -ne 'signin' -or -not (Test-Calm)) { Show-Pose 'levelup' 4200 }
      Say (Pick-Line 'levelup') 4200 -Ambient:($why -eq 'signin')
      petLog ('levelup -> ' + $script:stats.level + ' (' + $why + ')')
    }
    Save-Stats
    Update-Tray
  } catch { }
}
function Unlock([string]$id, [string]$pose, [string]$line) {
  try {
    if ($script:stats.achievements -contains $id) { return }
    $script:stats.achievements = @($script:stats.achievements) + $id
    Save-Stats
    Show-Pose $pose 4200
    Say $line 4200
    petLog ('achievement ' + $id)
  } catch { }
}
function Update-Tray {
  try {
    $status = $script:preferences.petName + ' Lv.' + $script:stats.level + ' · 连续 ' + $script:stats.streak + ' 天'
    if ($script:focusUntil) {
      $remaining = [Math]::Max(0, [int][Math]::Ceiling(($script:focusUntil - [DateTime]::Now).TotalMinutes))
      $status += ' · 专注剩余 ' + $remaining + ' 分钟'
    } elseif ($script:companion.focus.paused) { $status += ' · 专注已暂停' }
    elseif ($script:gentleReminder) { $status += ' · ' + $script:gentleReminder }
    $tray.Text = $status.Substring(0, [Math]::Min(63, $status.Length))
    if ($miFocus) { $miFocus.Text = if ($script:companion.focus) { '查看专注计时' } else { '陪我专注…' }; $miFocus.Enabled = $true }
    if ($miCancelFocus) { $miCancelFocus.Enabled = [bool]$script:companion.focus }
  } catch { }
}
function Test-Calm { return ([bool]$script:preferences.quiet -or [bool]$script:focusUntil) }
function Say([string]$t, [int]$ms, [switch]$Ambient, [switch]$Raw) {
  if ([string]::IsNullOrWhiteSpace($t) -or $script:pending -or ($Ambient -and (Test-Calm))) { return }
  $bubbleText.Text = if ($Raw) { $t } else { Get-PetCompanionText $t $script:preferences }
  if($bubbleNameText){$bubbleNameText.Text=$script:preferences.petName+' · 陪着 '+$script:preferences.userName}
  $bubbleBox.Visibility = [System.Windows.Visibility]::Visible
  $script:bubbleUntil = [DateTime]::Now.AddMilliseconds($ms)
}
function Show-Pose([string]$k, [int]$ms) {
  if ($script:pending -and $k -ne 'wait') { return }
  $i = Load-Pose $k
  if ($i) { $image.Source = $i; $script:lastPose = $k }
  $script:forcedPose = $k; $script:forcedUntil = [DateTime]::Now.AddMilliseconds($ms)
}
function Restore-Pose($state, [DateTime]$now) {
  if ($script:forcedUntil -and $now -lt $script:forcedUntil -and -not $script:pending) { return }
  $script:forcedPose = $null; $script:forcedUntil = $null
  $pose = 'idle'
  if ($script:pending) { $pose = 'wait' }
  elseif ($script:away) { $pose = 'sleep' }
  elseif ($state -and $state.pose -and (-not $state.at -or ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [double]$state.at) -lt 75000)) { $pose = [string]$state.pose }
  elseif ($script:nightMode) { $pose = 'night' }
  if ($pose -ne $script:lastPose) {
    $i = Load-Pose $pose
    if ($i) { $image.Source = $i; $script:lastPose = $pose }
  }
}
function Save-Preferences { Write-Json $preferencesFile $script:preferences }
function Set-Quiet([bool]$enabled) {
  $previous=$script:preferences.quiet
  $script:preferences.quiet = $enabled
  try{Save-Preferences}catch{$script:preferences.quiet=$previous;throw}
  $miQuiet.Checked = $enabled
  if ($enabled) { $bubbleBox.Visibility = [System.Windows.Visibility]::Collapsed }
  Say $(if ($enabled) { '好，我安静陪着你。需要我的时候，摸摸头就好。' } else { '我回来啦，今天也一起慢慢来。' }) 4000
}
function Set-BreakReminders([bool]$enabled) {
  $previous=$script:preferences.breakReminders
  $script:preferences.breakReminders = $enabled
  try{Save-Preferences}catch{$script:preferences.breakReminders=$previous;throw}
  $script:breakNextAt = [DateTime]::Now.AddMinutes(50)
  $miBreak.Checked = $enabled
  Say $(if ($enabled) { '每 50 分钟轻轻提醒你起身、喝口水。' } else { '休息提醒关好啦，按你的节奏来。' }) 3600
}
function Start-Focus([int]$Minutes = 0) {
  if ($script:companion.focus) { return }
  if ($Minutes -eq 0) { $Minutes = Get-PetBoundedNumber $script:preferences.focusMinutes 25 5 180 }
  if ($Minutes -lt 5 -or $Minutes -gt 180) { throw '专注时间支持 5 到 180 分钟。' }
  $deadline = [DateTime]::Now.AddMinutes($Minutes)
  $script:companion.focus = @{ until = $deadline.ToUniversalTime().ToString('o'); minutes = $Minutes }
  try { Save-CompanionData } catch { $script:companion.focus = $null; throw }
  $script:focusUntil = $deadline; $script:focusMinutes = $Minutes
  $script:gentleReminder = ''
  $bubbleBox.Visibility = [System.Windows.Visibility]::Collapsed
  Say ('{user}，接下来 ' + $Minutes + ' 分钟，我陪你专心做一件事。慢慢来。') 4200
  Update-Tray
}
function Cancel-Focus {
  if (-not $script:companion.focus) { return }
  $previous=$script:companion.focus
  $script:companion.focus = $null
  try{Save-CompanionData}catch{$script:companion.focus=$previous;throw}
  $script:focusUntil = $null
  $script:breakNextAt = [DateTime]::Now.AddMinutes(50)
  Say '计时停好了。愿意开始，就已经很不错了。' 4000
  Update-Tray
}
function Show-PetNativeNotice([string]$Text, [switch]$Raw) {
  # Native mode has no visible WPF bubble. Only explicitly requested messages,
  # saved reminders and completed focus sessions use this notification channel.
  # Quiet mode continues to suppress ambient activity; it does not suppress a
  # reminder the user deliberately scheduled. Windows controls notification DND.
  if($script:preferences.displayMode -ne 'native' -or $window.IsVisible -or $script:away -or $script:pending -or $script:focusUntil){return $false}
  if(-not $tray -or -not $tray.Visible -or [string]::IsNullOrWhiteSpace($Text)){return $false}
  try {
    $body=if($Raw){$Text}else{Get-PetCompanionText $Text $script:preferences}
    [void]$tray.ShowBalloonTip(6500,([string]$script:preferences.petName+' · 提醒'),$body,[System.Windows.Forms.ToolTipIcon]::Info)
    return $true
  } catch {petLog ('native notice could not be presented: '+$_.Exception.Message);return $false}
}
function Show-PetNewsNotice($Item) {
  if(-not $Item){return}
  $intro=Get-PetCompanionText '{user}，有一条新消息想和你分享：' $script:preferences
  $title=ConvertTo-PetSingleLine ([string]$Item.title) 500
  if($title.Length -gt 78){$title=$title.Substring(0,78)+'…'}
  if($script:preferences.displayMode -eq 'native' -and -not $window.IsVisible){
    [void](Show-PetNativeNotice ($intro+$title+'（在聊天中说“打开新闻面板”查看来源）') -Raw)
  }else{
    Show-Pose 'daily-coffee' 8500
    Say ($intro+$title+'（右键打开新闻收件箱查看来源）') 10000 -Raw
  }
}
function Show-GentleReminder {
  if (-not $script:gentleReminder -or $script:focusUntil -or $script:pending -or $script:away) { return }
  if(-not $window.IsVisible){
    if($script:preferences.displayMode -ne 'native'){return}
    # A break reminder queued before switching modes must not become an ambient
    # Windows notification or block a deliberately scheduled reminder forever.
    if(-not $script:companion.focusNotice -and -not $script:gentleReminderRaw){$script:gentleReminder='';return}
    if(-not (Show-PetNativeNotice $script:gentleReminder -Raw:([bool]$script:gentleReminderRaw))){return}
  } else {Say $script:gentleReminder 6500 -Raw:([bool]$script:gentleReminderRaw)}
  if($script:companion.focusNotice){
    $previous=$script:companion.focusNotice;$script:companion.focusNotice=$null
    try{Save-CompanionData}catch{$script:companion.focusNotice=$previous;petLog 'focus notice acknowledgment will retry';return}
  }
  $script:gentleReminder = ''; Update-Tray
}
function Update-Companion([DateTime]$now) {
  if ($script:focusUntil -and $now -ge $script:focusUntil) {
    $previous=Copy-PetCompanionData $script:companion
    $script:companion.focus = $null
    $script:companion.focusCompletedCount=[Math]::Max([int]$script:companion.focusCompletedCount,[int]$script:stats.focusSessions)+1
    $script:companion.focusNotice=@{minutes=$script:focusMinutes;at=$now.ToUniversalTime().ToString('o')}
    try{Save-CompanionData}catch{$script:companion=$previous;throw}
    $script:focusUntil = $null
    $script:stats.focusSessions = [int]$script:companion.focusCompletedCount
    Save-Stats
    $script:gentleReminder = [string]$script:focusMinutes + ' 分钟到了，辛苦啦。松松肩、喝口水，刚才的努力算数。'
    $script:gentleReminderRaw = $false
    $script:breakNextAt = $now.AddMinutes(50)
  } elseif ($script:preferences.breakReminders -and $window.IsVisible -and -not $script:focusUntil -and $now -ge $script:breakNextAt) {
    $script:breakNextAt = $now.AddMinutes(50)
    if (-not $script:away -and -not $script:gentleReminder) { $script:gentleReminder = '陪你坐了好一会儿，起来伸个懒腰、看看远处吧。'; $script:gentleReminderRaw = $false }
  }
  if(-not $script:gentleReminder -and $script:companion.focusNotice -and -not $script:focusUntil){
    $script:gentleReminder='上次 '+[string]$script:companion.focusNotice.minutes+' 分钟的专注完成啦，辛苦了。放松一下，刚才的努力算数。'
    $script:gentleReminderRaw=$false
  }
  $nativeNotifications=($script:preferences.displayMode -eq 'native' -and -not $window.IsVisible)
  if (-not $script:gentleReminder -and -not $script:away -and -not $script:pending -and -not $script:focusUntil -and ($window.IsVisible -or $nativeNotifications)) {
    $due = @(Get-PetDueReminders $script:companion $now)
    if ($due.Count) {
      $details = (@($due | Select-Object -First 3 | ForEach-Object { [string]$_.text }) -join '；')
      if ($due.Count -gt 3) { $details += '；还有 ' + ($due.Count - 3) + ' 条（到待办与提醒查看）' }
      $message=(Get-PetCompanionText '{user}，之前记下的提醒到啦：' $script:preferences) + $details
      # Do not acknowledge an invisible reminder when the native notification
      # channel is unavailable; keep the saved reminder eligible for retry.
      if($nativeNotifications -and -not (Show-PetNativeNotice $message -Raw)){Update-Tray;return}
      $next=Copy-PetCompanionData $script:companion
      $dueIds=@($due|ForEach-Object{[string]$_.id})
      foreach($reminder in $next.reminders){if($dueIds -contains [string]$reminder.id){$reminder.notified=$true}}
      Write-Json $companionFile $next;$script:companion=$next
      if(-not $nativeNotifications){$script:gentleReminder = $message;$script:gentleReminderRaw = $true}
    }
  }
  Show-GentleReminder
  Update-Tray
}
function Update-SignIn([DateTime]$now) {
  $today = $now.ToString('yyyy-MM-dd')
  if ([string]$script:stats.lastDay -eq $today) { return }
  $yesterday = $now.AddDays(-1).ToString('yyyy-MM-dd')
  if ([string]$script:stats.lastDay -eq $yesterday) { $script:stats.streak = [int]$script:stats.streak + 1 } else { $script:stats.streak = 1 }
  $script:stats.lastDay = $today
  Save-Stats; Add-Xp 5 'signin'
  Say ((Pick-Line 'signin') + '（连续 ' + $script:stats.streak + ' 天）') 3600 -Ambient
  petLog ('signin streak=' + $script:stats.streak)
}
function Show-Pet {
  Remove-Item -LiteralPath $hiddenFile -Force -ErrorAction SilentlyContinue
  $window.Show(); $window.Topmost = $true
  Show-GentleReminder
}
function Hide-Pet {
  Write-Json $hiddenFile @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
  $window.Hide()
  $fxCanvas.Children.Clear();$script:bubbles=@()
}
function Set-PetDisplayMode([string]$Mode) {
  if($Mode -notin @('desktop','native')){throw '请选择独立桌宠或内置宠物模式。'}
  if($Mode -eq 'native'){
    Remove-Item -LiteralPath $showFile -Force -ErrorAction SilentlyContinue
    Hide-Pet
  } else {Show-Pet}
  Update-Tray
}
function Stop-Pet {
  Write-Json $controlFile @{ stopped = $true; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
  $tray.Visible = $false; $window.Close()
}
function Get-RpsOutcome([string]$pick, [string]$her) {
  if ($pick -eq $her) { return 'draw' }
  $beats = @{ '石头' = '剪刀'; '剪刀' = '布'; '布' = '石头' }
  if ($beats[$pick] -eq $her) { return 'win' }
  return 'lose'
}
function Invoke-PetRps([string]$Pick, [string]$Her = '') {
  if ($Pick -notin @('石头','剪刀','布')) { return }
  if ($Her -notin @('石头','剪刀','布')) { $Her = @('石头','剪刀','布') | Get-Random }
  $outcome = Get-RpsOutcome $Pick $Her
  if ($outcome -eq 'draw') {
    Say ((Pick-Line 'rps_draw') + '（她也出' + $Her + '）') 3600
    Show-Pose 'game-think' 2600
  } elseif ($outcome -eq 'lose') {
    $script:stats.rpsLose = [int]$script:stats.rpsLose + 1
    $script:stats.rpsStreak = 0; Save-Stats
    Say ((Pick-Line 'rps_win') + '（她出' + $Her + '，这次她赢啦）') 4000
    Show-Pose 'game-win' 3000
    Unlock 'rps-lose' 'achievement' '成就解锁：输给了鲸鱼娘一次（她得意坏了）'
  } else {
    $script:stats.rpsWin = [int]$script:stats.rpsWin + 1
    $script:stats.rpsStreak = [int]$script:stats.rpsStreak + 1; Save-Stats
    Say ((Pick-Line 'rps_lose') + '（她出' + $Her + '，你赢啦）战绩 ' + $script:stats.rpsWin + ' 胜') 4000
    Show-Pose 'game-lose' 3000; Add-Xp 4 'rps'
    Unlock 'rps-win' 'achievement' '成就解锁：猜拳首胜！'
    if ([int]$script:stats.rpsStreak -ge 3) { Unlock 'rps-3' 'achievement' '成就解锁：猜拳三连胜，你就是运气本尊' }
  }
  petLog ('rps me=' + $Pick + ' her=' + $Her)
}
function Get-Bottom { try { return [System.Windows.SystemParameters]::WorkArea.Bottom - 10 } catch { return 1382 } }
function Anchor-Bottom {
  try {
    $a = [System.Windows.SystemParameters]::WorkArea
    $h = [Math]::Max($window.ActualHeight, 140)
    $top = $script:feetBottom - $h
    if ($top -lt $a.Top) { $top = $a.Top }
    if (($top + $h) -gt $a.Bottom) { $top = $a.Bottom - $h }
    $window.Top = $top
  } catch { }
}
function Clamp-Feet {
  try {
    $a = [System.Windows.SystemParameters]::WorkArea
    $min = $a.Top + 220
    $max = $a.Bottom - 10
    if ($script:feetBottom -lt $min) { $script:feetBottom = $min }
    if ($script:feetBottom -gt $max) { $script:feetBottom = $max }
  } catch { }
}
function Clamp-X { try { $a = [System.Windows.SystemParameters]::WorkArea; if ($window.Left -lt $a.Left) { $window.Left = $a.Left }; if ($window.Left -gt ($a.Right - $window.Width)) { $window.Left = $a.Right - $window.Width } } catch { } }

$image.Add_MouseLeftButtonDown({
  param($sender, $eventArgs)
  $script:dragStart = [System.Windows.Input.Mouse]::GetPosition($window); $script:dragged = $false
  $script:skipClick = ($eventArgs.ClickCount -ge 2)
  if ($script:skipClick) {
    $script:dragStart = $null
    Open-CurrentSession
    $eventArgs.Handled = $true
  }
})
$image.Add_MouseMove({ if ($script:dragStart -ne $null -and [System.Windows.Input.Mouse]::LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) { $n = [System.Windows.Input.Mouse]::GetPosition($window); if ([Math]::Abs($n.X - $script:dragStart.X) -gt 3 -or [Math]::Abs($n.Y - $script:dragStart.Y) -gt 3) { $script:dragged = $true }; if ($script:dragged) { try { $window.DragMove() } catch { } } } })
$image.Add_MouseLeftButtonUp({
  if (-not $script:dragged -and -not $script:skipClick) {
    $now = [DateTime]::Now
    $script:popUntil = [DateTime]::Now.AddMilliseconds(320)
    $script:stats.clicks = [int]$script:stats.clicks + 1
    if (($now - $script:rapidSince).TotalSeconds -gt 2.5) { $script:rapidSince = $now; $script:rapid = 0 }
    $script:rapid = $script:rapid + 1
    $p = [System.Windows.Input.Mouse]::GetPosition($image)
    $ny = if ($image.ActualHeight -gt 10) { $p.Y / $image.ActualHeight } else { 0.5 }
    if ($script:nightMode -and $script:rapid -lt 5) {
      Say (Pick-Line 'night_click') 3200
      Show-Pose 'sleep' 2400
    } elseif ($script:rapid -ge 8) {
      Say (Pick-Line 'rapid_soft') 3200; Show-Pose 'meme-smile-pain' 2600
    } elseif ($script:rapid -ge 5) {
      Say (Pick-Line 'rapid') 3200; Show-Pose 'angry' 2600
    } elseif ($ny -lt 0.45) {
      Show-Pose 'react-head' 2600; Say (Pick-Line 'pat_head') 3200
      $script:stats.pats = [int]$script:stats.pats + 1
      Add-Xp 2 'pat'
      $pn = [int]$script:stats.pats
      if ($pn -ge 1) { Unlock 'first-pat' 'achievement' '成就解锁：第一次摸头！（好感 +1）' }
      if ($pn -ge 10) { Unlock 'pat-10' 'achievement' '成就解锁：摸头 10 次，她已经离不开你了' }
      if ($pn -ge 100) { Unlock 'pat-100' 'achievement' '成就解锁：摸头 100 次，鱼鱼已被你摸顺' }
      $h = (Get-Date).Hour
      if ($h -ge 1 -and $h -lt 5) { Unlock 'night-owl' 'achievement' '成就解锁：夜猫子（凌晨还在陪她）' }
      if ($h -ge 6 -and $h -lt 9) { Unlock 'early-bird' 'achievement' '成就解锁：早起鸟（一早就在）' }
    } elseif ($ny -lt 0.78) {
      Show-Pose 'react-belly' 2600; Say (Pick-Line 'pat_belly') 3200
    } else {
      Show-Pose 'react-tail' 2600; Say (Pick-Line 'pat_tail') 3200
    }
    Save-Stats; Update-Tray
  }
  $script:dragStart = $null
})

# ---------- tray ----------
$tray = New-Object System.Windows.Forms.NotifyIcon
try { if (Test-Path -LiteralPath $icoFile) { $tray.Icon = New-Object System.Drawing.Icon($icoFile) } else { $tray.Icon = [System.Drawing.SystemIcons]::Application } } catch { $tray.Icon = [System.Drawing.SystemIcons]::Application }
$tray.Text = $script:preferences.petName + '桌宠'
$tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $menu.Items.Add('叫' + $script:preferences.petName + '出来')
$miHide = $menu.Items.Add('先藏一会')
$miHome = $menu.Items.Add('回到右下角')
$miWalk = $menu.Items.Add('自动溜达')
$miWalk.CheckOnClick = $true; $miWalk.Checked = $script:walk
$miQuiet = $menu.Items.Add('安静陪伴')
$miQuiet.CheckOnClick = $true; $miQuiet.Checked = [bool]$script:preferences.quiet
$miFocus = $menu.Items.Add('陪我专注 ' + $script:preferences.focusMinutes + ' 分钟')
$miCancelFocus = $menu.Items.Add('结束本次专注')
$miCancelFocus.Enabled = $false
$miBreak = $menu.Items.Add('休息提醒（每 50 分钟）')
$miBreak.CheckOnClick = $true; $miBreak.Checked = [bool]$script:preferences.breakReminders
$miTasks = $menu.Items.Add('待办与提醒 📝')
$miSettings = $menu.Items.Add('设置与称呼 ⚙')
$miNews = $menu.Items.Add('新闻收件箱 📰')
$miDiagnostics = $menu.Items.Add('检查与修复建议')
$miStickerTray = $menu.Items.Add('来张随机表情 🎴')
$miCopy = $menu.Items.Add('复制当前表情')
$menu.Items.Add('-') | Out-Null
$miQuit = $menu.Items.Add('退出')
$tray.ContextMenuStrip = $menu
$miShow.Add_Click({ Show-Pet })
$miHide.Add_Click({ Hide-Pet })
$miHome.Add_Click({ $a = [System.Windows.SystemParameters]::WorkArea; $window.Left = $a.Right - $window.Width - 30; $script:feetBottom = $a.Bottom - 10; Anchor-Bottom; Write-Json $posFile @{ left = [int]$window.Left; feetBottom = [int]$script:feetBottom; walk = $script:walk } })
$miWalk.Add_Click({ $script:walk = $miWalk.Checked; $script:preferences.walk = $script:walk; Save-Preferences })
$miQuiet.Add_Click({ Set-Quiet $miQuiet.Checked })
$miFocus.Add_Click({ Show-PetFocus })
$miCancelFocus.Add_Click({ Cancel-Focus })
$miBreak.Add_Click({ Set-BreakReminders $miBreak.Checked })
$miTasks.Add_Click({ Show-PetTasks })
$miSettings.Add_Click({ Show-PetSettings })
$miNews.Add_Click({ Show-PetNewsInbox })
$miDiagnostics.Add_Click({ Show-PetDiagnostics })
$miStickerTray.Add_Click({ Show-Sticker 6000 })
$miCopy.Add_Click({ Copy-CurrentSticker })
$miQuit.Add_Click({ Stop-Pet })
$tray.Add_MouseDoubleClick({ Show-Pet })

# ---------- right click menu on her ----------
$image.Add_MouseRightButtonUp({
  $cm = New-Object System.Windows.Controls.ContextMenu
  $quietItem = New-Object System.Windows.Controls.MenuItem; $quietItem.Header = '安静陪伴'; $quietItem.IsCheckable = $true; $quietItem.IsChecked = [bool]$script:preferences.quiet
  $quietItem.Add_Click({ Set-Quiet ([bool]$this.IsChecked) })
  [void]$cm.Items.Add($quietItem)
  $focusItem = New-Object System.Windows.Controls.MenuItem
  $focusItem.Header = '专注计时…'
  $focusItem.Add_Click({ Show-PetFocus })
  [void]$cm.Items.Add($focusItem)
  $breakItem = New-Object System.Windows.Controls.MenuItem; $breakItem.Header = '休息提醒（每 50 分钟）'; $breakItem.IsCheckable = $true; $breakItem.IsChecked = [bool]$script:preferences.breakReminders
  $breakItem.Add_Click({ Set-BreakReminders ([bool]$this.IsChecked) })
  [void]$cm.Items.Add($breakItem)
  $taskItem = New-Object System.Windows.Controls.MenuItem; $taskItem.Header = '待办与提醒 📝'; $taskItem.Add_Click({ Show-PetTasks }); [void]$cm.Items.Add($taskItem)
  $settingsItem = New-Object System.Windows.Controls.MenuItem; $settingsItem.Header = '设置与称呼 ⚙'; $settingsItem.Add_Click({ Show-PetSettings }); [void]$cm.Items.Add($settingsItem)
  $newsItem = New-Object System.Windows.Controls.MenuItem; $newsItem.Header = '新闻收件箱 📰'; $newsItem.Add_Click({ Show-PetNewsInbox }); [void]$cm.Items.Add($newsItem)
  $diagnosticsItem=New-Object System.Windows.Controls.MenuItem;$diagnosticsItem.Header='检查与修复建议';$diagnosticsItem.Add_Click({Show-PetDiagnostics});[void]$cm.Items.Add($diagnosticsItem)
  $moodMenu = New-Object System.Windows.Controls.MenuItem; $moodMenu.Header = '今天的心情 🌤'
  foreach ($mood in @(@{ id = 'tired'; label = '有点累，陪我歇歇' }, @{ id = 'low'; label = '有点低落，安静陪我' }, @{ id = 'anxious'; label = '有点焦虑，缓一缓' }, @{ id = 'happy'; label = '今天开心，一起庆祝' },@{id='angry';label='有些生气，先缓一下'},@{id='overwhelmed';label='事情太多，拆小一步'})) {
    $moodItem = New-Object System.Windows.Controls.MenuItem; $moodItem.Header = $mood.label
    $moodItem.Tag = $mood.id
    $moodItem.Add_Click({ param($sender,$eventArgs) Show-PetMood ([string]$sender.Tag) })
    [void]$moodMenu.Items.Add($moodItem)
  }
  [void]$cm.Items.Add($moodMenu)
  if ($script:sid) {
    $viewItem = New-Object System.Windows.Controls.MenuItem; $viewItem.Header = '去当前会话看看 →'
    $viewItem.Add_Click({ Open-CurrentSession })
    [void]$cm.Items.Add($viewItem)
  }
  [void]$cm.Items.Add((New-Object System.Windows.Controls.Separator))
  Add-PetCatalogMenu $cm
  [void]$cm.Items.Add((New-Object System.Windows.Controls.Separator))
  $rps = New-Object System.Windows.Controls.MenuItem; $rps.Header = '猜拳 ✊✌✋'
  foreach ($pick in @('石头','剪刀','布')) {
    $miR = New-Object System.Windows.Controls.MenuItem; $miR.Header = ('出' + $pick); $miR.Tag = $pick
    $miR.Add_Click({ param($sender,$eventArgs) Invoke-PetRps ([string]$sender.Tag) })
    [void]$rps.Items.Add($miR)
  }
  [void]$cm.Items.Add($rps)
  $miSticker = New-Object System.Windows.Controls.MenuItem; $miSticker.Header = '随机表情 🎴'
  $miSticker.Add_Click({ Show-Sticker 4600 })
  [void]$cm.Items.Add($miSticker)
  $copySticker = New-Object System.Windows.Controls.MenuItem; $copySticker.Header = '复制当前表情'; $copySticker.Add_Click({ Copy-CurrentSticker }); [void]$cm.Items.Add($copySticker)
  $miBub = New-Object System.Windows.Controls.MenuItem; $miBub.Header = '戳泡泡 🫧'
  $miBub.Add_Click({ Spawn-Bubbles 4; Show-Pose 'game-happy' 2400; Say (Pick-Line 'bubble_invite') 3200 })
  [void]$cm.Items.Add($miBub)
  $miMem = New-Object System.Windows.Controls.MenuItem; $miMem.Header = ('我记得：' + $(if ($script:mem.project) { $script:mem.project } else { '（还没有项目名）' }))
  $miMem.IsEnabled = $false
  [void]$cm.Items.Add($miMem)
  $miStats = New-Object System.Windows.Controls.MenuItem; $miStats.Header = ('战绩：摸头 ' + $script:stats.pats + ' / 猜拳 ' + $script:stats.rpsWin + '胜' + $script:stats.rpsLose + '负 / Lv.' + $script:stats.level)
  $miStats.IsEnabled = $false
  [void]$cm.Items.Add($miStats)
  [void]$cm.Items.Add((New-Object System.Windows.Controls.Separator))
  $mh = New-Object System.Windows.Controls.MenuItem; $mh.Header = '回到右下角'
  $mh.Add_Click({ $a = [System.Windows.SystemParameters]::WorkArea; $window.Left = $a.Right - $window.Width - 30; $script:feetBottom = $a.Bottom - 10; Anchor-Bottom })
  [void]$cm.Items.Add($mh)
  $hideItem = New-Object System.Windows.Controls.MenuItem; $hideItem.Header = '先藏一会'
  $hideItem.Add_Click({ Hide-Pet })
  [void]$cm.Items.Add($hideItem)
  $mq = New-Object System.Windows.Controls.MenuItem; $mq.Header = '退出'
  $mq.Add_Click({ Stop-Pet })
  [void]$cm.Items.Add($mq)
  $cm.IsOpen = $true
})

function Get-ApprovalKey($approval) { return ([string]$approval.clientId + ':' + [string]$approval.id) }
function Test-ApprovalLive($approval, [double]$nowMs) {
  if (-not $approval -or [string]::IsNullOrWhiteSpace([string]$approval.id)) { return $false }
  if ($approval.expiresAt) { return ([double]$approval.expiresAt -gt $nowMs) }
  # Compatibility for pre-queue state: 75-second freshness plus 150-second grace.
  return ($script:pendingSeenAt -and ($nowMs - [double]$script:pendingSeenAt) -lt 225000)
}
function Clear-Pending {
  $script:pending = $null; $script:pendingSeenAt = $null
  $card.Visibility = [System.Windows.Visibility]::Collapsed
  $btnYes.IsEnabled = $false; $btnNo.IsEnabled = $false
}
function Update-PetState($state, [DateTime]$now) {
  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if ($state) {
    $fresh = (-not $state.at -or ($nowMs - [double]$state.at) -lt 75000)
    $codexState = ([string]$state.host -eq 'codex')
    if ($codexState -and $state.kind -in @('approval', 'question') -and $state.at -and ($nowMs - [double]$state.at) -lt 900000) {
      $noticeId = if ($state.noticeId) { [string]$state.noticeId } else { 'notice-' + [string]$state.at }
      $script:pending = @{ id = $noticeId; clientId = ''; notificationOnly = $true; expiresAt = [double]$state.at + 900000 }
      $script:sid = [string]$state.sid
      $headText.Text = $script:preferences.petName + ' · Codex 等你看看'
      $cardTool.Text = if ($state.kind -eq 'approval') { 'Codex 有一项权限请求' } else { 'Codex 想听听你的选择' }
      $cardReason.Text = '到 Codex 原会话查看并处理，我会在这里等你。'
      $btnYes.Visibility = [System.Windows.Visibility]::Collapsed; $btnNo.Visibility = [System.Windows.Visibility]::Collapsed
      $btnYes.IsEnabled = $false; $btnNo.IsEnabled = $false
      $btnGo.Visibility = [System.Windows.Visibility]::Visible
      $card.Visibility = [System.Windows.Visibility]::Visible; $bubbleBox.Visibility = [System.Windows.Visibility]::Collapsed
      $script:forcedPose = $null; $script:forcedUntil = $null
    } elseif (-not $codexState -and $script:preferences.host -eq 'dsh' -and $state.approval) {
      $approval = $state.approval
      $key = Get-ApprovalKey $approval
      $changed = (-not $script:pending -or (Get-ApprovalKey $script:pending) -ne $key)
      if ($changed) { $script:pendingSeenAt = if ($state.at) { [double]$state.at } else { $nowMs } }
      if ((Test-ApprovalLive $approval $nowMs) -and -not $script:decidedIds.ContainsKey($key)) {
        $script:pending = $approval
        $script:sid = if ($approval.sessionId) { [string]$approval.sessionId } else { [string]$state.sid }
        $btnGo.Visibility = if ($script:sid) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $canDecide = -not [string]::IsNullOrWhiteSpace([string]$approval.clientId)
        $btnYes.Visibility = [System.Windows.Visibility]::Visible; $btnNo.Visibility = [System.Windows.Visibility]::Visible
        $btnYes.IsEnabled = $canDecide; $btnNo.IsEnabled = $canDecide
        $headText.Text = $script:preferences.petName + $(if ([int]$state.approvalCount -gt 1) { ' · 待审批 ' + [int]$state.approvalCount + ' 项' } else { ' · 需要你裁决' })
        $cardTool.Text = [string]$approval.tool
        $cardReason.Text = [string]$approval.reason
        if (-not $canDecide) { $cardReason.Text += '（请到原会话处理这条旧版审批）' }
        $card.Visibility = [System.Windows.Visibility]::Visible
        $bubbleBox.Visibility = [System.Windows.Visibility]::Collapsed
        if ($changed) { $script:forcedPose = $null; $script:forcedUntil = $null }
      } elseif ($script:pending) { Clear-Pending }
    } elseif ($script:pending) { Clear-Pending }
    if (-not $script:pending -and $fresh) {
      $script:sid = [string]$state.sid
      if ($state.note -and [string]$state.note -ne $script:lastNote) { $script:lastNote = [string]$state.note; Remember $script:lastNote }
      $contextKey=[string]$state.host+'|'+[string]$state.note
      if ($state.line -and ([string]$state.line -ne $script:lastLine -or $contextKey -cne $script:lastLineContext)) {
        $script:lastLineContext=$contextKey
        $script:lastLine = [string]$state.line
        if ($codexState) {
          $line=Get-PetCompanionText $script:lastLine $script:preferences
          $project=if($state.note){[string]$state.note}else{'当前任务'}
          Say ($line.Replace('{project}',$project)) 6500 -Ambient -Raw
        }
        elseif ($script:lastLine -match '\{user\}|\{pet\}') { Say $script:lastLine 4200 -Ambient }
        else { Say $script:lastLine 4200 -Ambient -Raw }
      }
    }
  }
  if ($script:pending -and -not (Test-ApprovalLive $script:pending $nowMs)) { Clear-Pending }
}
function Submit-PetDecision([string]$outcome) {
  if ($script:preferences.host -ne 'dsh' -or -not $script:pending -or $script:pending.notificationOnly -or [string]::IsNullOrWhiteSpace([string]$script:pending.clientId)) { return }
  if (-not (Test-ApprovalLive $script:pending ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()))) { Clear-Pending; return }
  if ($outcome -notin @('allowed-once', 'rejected')) { return }
  try {
    $approval = $script:pending
    $path = Get-PetDecisionPath $PetHome ([string]$approval.clientId) ([string]$approval.id)
    Write-Json $path @{ id = [string]$approval.id; clientId = [string]$approval.clientId; sessionId = [string]$approval.sessionId; requestId = [string]$approval.requestId; outcome = $outcome; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    $script:decidedIds[(Get-ApprovalKey $approval)] = [DateTime]::Now
    petLog ('decision submitted id=' + [string]$approval.id + ' outcome=' + $outcome)
    $script:stats.approvals = [int]$script:stats.approvals + 1; Save-Stats
    Clear-Pending
    $pose = if ($outcome -eq 'allowed-once') { 'ok' } else { 'no' }
    Show-Pose $pose 2600; Say '已把你的选择送回会话。' 3000
  } catch {
    $cardReason.Text = '选择暂时没有保存，请再点一次，或到原会话处理。'
    petLog ('decision write failed: ' + $_.Exception.Message)
  }
}
$btnYes.Add_Click({ Submit-PetDecision 'allowed-once' })
$btnNo.Add_Click({ Submit-PetDecision 'rejected' })

function Open-CurrentSession {
  try {
    $sid = [string]$script:sid
    if (Get-Command Open-PetHost -ErrorAction SilentlyContinue) {
      [void](Open-PetHost -PetHome $PetHome -SessionId $sid)
    } elseif ($script:preferences.host -eq 'codex') {
      [void](New-Object -ComObject wscript.shell).AppActivate('Codex')
    } elseif (-not [string]::IsNullOrWhiteSpace($sid)) {
      [System.IO.File]::AppendAllText($activateFile, $sid.Trim() + "`n", $utf8)
    }
    Say '走，带你去看看～' 2600
  } catch { }
}
$btnGo.Add_Click({ Open-CurrentSession })

# ---------- 戳泡泡小游戏 ----------
$script:bubbles = @()
function Spawn-Bubbles([int]$n) {
  try {
    for ($i = 0; $i -lt $n; $i += 1) {
      $el = New-Object System.Windows.Shapes.Ellipse
      $d = Get-Random -Minimum 20 -Maximum 30
      $el.Width = $d; $el.Height = $d
      $rg = New-Object System.Windows.Media.RadialGradientBrush
      $rg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(150, 255, 255, 255), 0)))
      $rg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(60, 120, 220, 255), 0.6)))
      $rg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(20, 56, 189, 248), 1)))
      $el.Fill = $rg
      $el.Stroke = (Brush 210 180 235 255)
      $el.StrokeThickness = 1.2
      $el.Cursor = [System.Windows.Input.Cursors]::Hand
      $bx = Get-Random -Minimum 14 -Maximum 250
      $by = Get-Random -Minimum 210 -Maximum 420
      [System.Windows.Controls.Canvas]::SetLeft($el, $bx)
      [System.Windows.Controls.Canvas]::SetTop($el, $by)
      $el.Tag = ($bx.ToString() + ',' + $by.ToString())
      $el.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        $b = $sender
        Pop-Bubble $b
        $eventArgs.Handled = $true
      })
      [void]$fxCanvas.Children.Add($el)
      $script:bubbles += @{ el = $el; y = $by; vy = (0.55 + (Get-Random -Minimum 0 -Maximum 60) / 100.0) }
      petLog ('bubble spawn at ' + $bx + ',' + $by)
    }
  } catch { petLog ('bubble spawn failed: ' + $_.Exception.Message) }
}
function Pop-Bubble($el) {
  try {
    $fxCanvas.Children.Remove($el)
    $script:bubbles = @($script:bubbles | Where-Object { $_.el -ne $el })
    $script:stats.bubbles = [int]$script:stats.bubbles + 1
    Save-Stats
    Say (Pick-Line 'bubble_pop') 1600
    Add-Xp 1 'bubble'
    $bn = [int]$script:stats.bubbles
    if ($bn -ge 10) { Unlock 'bubble-10' 'achievement' '成就解锁：戳爆 10 个泡泡' }
    if ($bn -ge 50) { Unlock 'bubble-50' 'achievement' '成就解锁：戳爆 50 个泡泡，手速惊人' }
    if ($script:bubbles.Count -eq 0) {
      Show-Pose 'game-win' 3000
      Say (Pick-Line 'bubble_clear') 3600
      Add-Xp 3 'bubble-clear'
    }
    petLog ('bubble pop total=' + $bn)
  } catch { }
}

# ---------- 挂机陪伴：离开睡着 / 回来报告 ----------
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Idle2 {
  [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
  public static uint IdleMs() {
    LASTINPUTINFO i = new LASTINPUTINFO();
    i.cbSize = (uint)Marshal.SizeOf(i);
    if (!GetLastInputInfo(ref i)) return 0;
    return (uint)Environment.TickCount - i.dwTime;
  }
}
'@

# ---------- 她会记住你 ----------
$memFile = Join-Path $PetHome 'pet-memory.json'
$script:mem = Read-Record $memFile @{ project = ''; visits = 0; lastSeen = ''; lastProject = '' }
if ([string]$script:mem.lastSeen -eq "'; lastProject = '") { $script:mem.lastSeen = '' }
$script:mem.visits = [int]$script:mem.visits + 1
Write-Json $memFile $script:mem
function Remember([string]$note) {
  try {
    $t = ([string]$note).Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return }
    if ($t.Length -gt 28) { $t = $t.Substring(0, 28) }
    if ($t -ne [string]$script:mem.project) {
      $script:mem.lastProject = [string]$script:mem.project
      $script:mem.project = $t
      $script:mem.lastSeen = (Get-Date).ToString('s')
      Write-Json $memFile $script:mem
      petLog ('remember project=' + $t)
      Say ((Get-PetCompanionText (Pick-Line 'remember') $script:preferences) + '（' + $t + '）') 3600 -Ambient -Raw
    }
  } catch { }
}

$window.Add_Loaded({
  $pos = Read-Json $posFile
  $a = [System.Windows.SystemParameters]::WorkArea
  if ($pos -and $pos.left -ne $null) { $window.Left = [double]$pos.left } else { $window.Left = $a.Right - $window.Width - 30 }
  if ($pos -and $pos.feetBottom -ne $null) { $script:feetBottom = [double]$pos.feetBottom } else { $script:feetBottom = $a.Bottom - 10 }
  Clamp-Feet
  petLog ('load feetBottom=' + $script:feetBottom)
  Show-Pose 'idle' 1000
  Update-SignIn ([DateTime]::Now)
  if ($script:mem.project) { $script:greetAt = [DateTime]::Now.AddMilliseconds(900) }
  Update-Tray
  $window.UpdateLayout(); Anchor-Bottom
  if ((Test-Path -LiteralPath $hiddenFile) -or $script:preferences.displayMode -eq 'native') { $window.Hide() }
})
$window.Add_LocationChanged({ $script:lastMove = [DateTime]::Now })
$window.Add_SizeChanged({ Anchor-Bottom })

# ---------- animation loop ----------
$loop = New-Object System.Windows.Threading.DispatcherTimer
$loop.Interval = [TimeSpan]::FromMilliseconds(70)
$loop.Add_Tick({
  $script:tick = $script:tick + 1
  $now = [DateTime]::Now
  # breathing + hop + click pop
  $interval=if(-not $window.IsVisible){500}elseif($script:away){250}elseif(Test-Calm){120}else{80}
  if($loop.Interval.TotalMilliseconds -ne $interval){$loop.Interval=[TimeSpan]::FromMilliseconds($interval)}
  if($window.IsVisible){
  $y = [Math]::Sin($script:tick / 8.0) * $(if (Test-Calm) { 1.0 } else { 3.0 })
  if ($script:hopUntil -and $now -lt $script:hopUntil) { $y = -11 + $y }
  $translate.Y = $y
  if ($script:popUntil -and $now -lt $script:popUntil) { $scale.ScaleX = 1.06; $scale.ScaleY = 0.95 } else { $scale.ScaleX = 1; $scale.ScaleY = 1 }
  # idle wink flash
  if (-not $script:pending -and -not $script:away -and (-not $script:forcedUntil -or $now -gt $script:forcedUntil) -and ($script:tick % $(if (Test-Calm) { 450 } else { 90 })) -eq 0) { $script:winkUntil = $now.AddMilliseconds(150); Show-Pose 'wink' 150 }
  if ($script:winkUntil -and $now -gt $script:winkUntil -and $script:forcedPose -eq 'wink') { $script:forcedPose = $null; $script:forcedUntil = $null }
  }
  # ---------- 生活小剧场：随机生活姿势 + 台词 ----------
  $hour = (Get-Date).Hour
  $script:nightMode = ($hour -ge 23 -or $hour -lt 6)
  $hostBusy=($script:lastState.kind -in @('running','tool','approval','question') -and $script:lastState.at -and (Get-PetUtcMs)-[double]$script:lastState.at -lt 75000)
  $idleFree = (-not $hostBusy) -and (-not (Test-Calm)) -and $window.IsVisible -and (-not $script:away) -and (-not $script:pending) -and (-not $script:lastMove) -and ((-not $script:forcedUntil) -or ($now -gt $script:forcedUntil)) -and (-not $script:bubbleUntil -or $now -gt $script:bubbleUntil)
  if ($idleFree -and $now -gt $script:idleNextAt) {
    $pool = if ($script:nightMode) { $IDLE_NIGHT } else { $IDLE_DAY }
    $pick = $pool | Get-Random
    $script:idleNextAt = $now.AddSeconds((Get-Random -Minimum 20 -Maximum 46))
    Show-Pose $pick 5200
    $line = if($IDLE_LINES.ContainsKey($pick)){$IDLE_LINES[$pick]}else{Pick-Line ('idle_' + $pick)}
    if (-not $line) { $line = Pick-Line 'idle_daily_coffee' }
    if ($line) { Say $line 4200 -Ambient }
    petLog ('idle action ' + $pick)
  }
  # ---------- 贴纸时间：随机来一张表情包状态 ----------
  if ($idleFree -and $now -gt $script:stickerNextAt) {
    $script:stickerNextAt = $now.AddSeconds((Get-Random -Minimum 150 -Maximum 270))
    Show-Sticker 4400
  }

  # ---------- 她会看着鼠标（靠近才转头，不抽风） ----------
  if($window.IsVisible){try {
    $cur = [System.Windows.Forms.Cursor]::Position
    $cx = $window.Left + ($window.Width / 2)
    if ([Math]::Abs($cur.X - $cx) -lt 620) {
      $scale.ScaleX = if ($cur.X -lt $cx) { -1 } else { 1 }
      if (($now - $script:mouseSaid).TotalSeconds -gt 90 -and (-not $script:pending)) {
        $script:mouseSaid = $now
        Say (Pick-Line 'mouse_near') 2600 -Ambient
      }
    } else { $scale.ScaleX = 1 }
  } catch { }}

  # ---------- 心跳：看门狗靠它判断我是不是真的活着（桥接活着 ≠ 我活着） ----------
  if (-not $script:heartbeatNextAt -or $now -ge $script:heartbeatNextAt) {
    $script:heartbeatNextAt=$now.AddSeconds(7)
    try { Write-Json $aliveFile @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); pid = $PID } } catch { }
  }

  # ---------- 只响应明确的显示请求，隐藏后不自行拉起 ----------
  if (-not $script:showNextAt -or $now -ge $script:showNextAt) {
    $script:showNextAt=$now.AddMilliseconds(500)
    try {
      $hideRequest=Read-Json $hiddenFile
      if($hideRequest.supportOnly -and $window.IsVisible){$window.Hide()}
      if (Test-Path -LiteralPath $showFile) {
        Process-PetShowRequest
      }
    } catch { }
  }

  # ---------- 泡泡上浮 ----------
  if ($window.IsVisible -and $script:bubbles.Count -gt 0) {
    $keep = @()
    foreach ($b in $script:bubbles) {
      $b.y = $b.y - $b.vy
      try { [System.Windows.Controls.Canvas]::SetTop($b.el, $b.y) } catch { }
      if ($b.y -gt -30) { $keep += $b } else { try { $fxCanvas.Children.Remove($b.el) } catch { } }
    }
    $script:bubbles = $keep
  }
  # ---------- 挂机陪伴 ----------
  if (-not $script:idleCheckNextAt -or $now -ge $script:idleCheckNextAt) {
    $script:idleCheckNextAt=$now.AddSeconds(5)
    try {
      $idle = [Idle2]::IdleMs()
      if ($idle -gt 180000 -and -not $script:away) {
        $script:away = $true
        $script:awaySince = $now
        $script:birds = 0
        Show-Pose 'sleep' 600000
        Say (Pick-Line 'away_sleep') 4000 -Ambient
        petLog 'away: user idle, she sleeps'
      } elseif ($idle -lt 2500 -and $script:away) {
        $mins = [int](($now - $script:awaySince).TotalMinutes)
        $script:away = $false
        $script:forcedPose = $null; $script:forcedUntil = $null
        Show-Pose 'daily-stretch' 3200
        Say ((Pick-Line 'back_report') + '你离开 ' + $mins + ' 分钟，我数了 ' + $script:birds + ' 只飞过的鸟～') 4600 -Ambient
        petLog ('back after ' + $mins + ' min, birds=' + $script:birds)
      }
      if ($script:away) { $script:birds = $script:birds + (Get-Random -Minimum 0 -Maximum 2) }
    } catch { }
  }
  # ---------- 自动吹泡泡（她主动邀请你玩） ----------
  if ($idleFree -and $script:bubbles.Count -eq 0 -and $now -gt $script:bubbleNextAt) {
    $script:bubbleNextAt = $now.AddSeconds((Get-Random -Minimum 150 -Maximum 260))
    Spawn-Bubbles 4
    Show-Pose 'game-happy' 2600
    Say (Pick-Line 'bubble_invite') 3600
  }

  # card pulse
  if ($window.IsVisible -and $card.Visibility -eq [System.Windows.Visibility]::Visible) {
    $script:pulse = $script:pulse + 0.16
    $dot.Opacity = 0.35 + [Math]::Abs([Math]::Sin($script:pulse)) * 0.65
    $card.BorderBrush = Brush ([int](130 + [Math]::Abs([Math]::Sin($script:pulse)) * 125)) 56 189 248
  }
  # bubble / card lifetimes
  if ($script:bubbleUntil -and $now -gt $script:bubbleUntil -and -not $script:pending) { $bubbleBox.Visibility = [System.Windows.Visibility]::Collapsed; $script:bubbleUntil = $null }
  if ($now -ge $script:stateNextAt) {
    $script:stateNextAt = $now.AddMilliseconds(500)
    if(-not $script:stateCache){$script:stateCache=@{}}
    $script:lastState = Read-PetJsonCached $stateFile $script:stateCache
    Update-PetState $script:lastState $now
  }
  if($window.IsVisible){Restore-Pose $script:lastState $now}
  if ($now -ge $script:maintenanceNextAt) {
    $script:maintenanceNextAt = $now.AddSeconds(1)
    Update-SignIn $now
    Update-Companion $now
    Process-PetCommands -PetHome $PetHome -Now $now
    if ($now -ge $script:newsNextAt -and (Get-Command Invoke-WhaleNewsTick -ErrorAction SilentlyContinue)) {
      $script:newsNextAt = $now.AddSeconds(10)
      $newsItem = Invoke-WhaleNewsTick -PetHome $PetHome -Preferences $script:preferences -Now $now -IsHidden:((-not $window.IsVisible) -and $script:preferences.displayMode -ne 'native') -IsAway:$script:away -IsBusy:([bool]$script:focusUntil -or [bool]$script:pending -or [bool]$script:gentleReminder -or ($script:bubbleUntil -and $now -lt $script:bubbleUntil))
      if ($newsItem) {
        $script:lastNewsNotice = [string]$newsItem.id
        Show-PetNewsNotice $newsItem
      }
    }
    if ($script:greetAt -and $now -ge $script:greetAt) {
      $script:greetAt = $null
      Say ((Get-PetCompanionText (Pick-Line 'welcome_back') $script:preferences) + '（' + $script:mem.project + '）') 4200 -Ambient -Raw
      if (-not (Test-Calm)) { Show-Pose 'peek' 2600 }
    }
    foreach ($decidedKey in @($script:decidedIds.Keys)) {
      if (($now - $script:decidedIds[$decidedKey]).TotalHours -gt 24) { $script:decidedIds.Remove($decidedKey) }
    }
  }
  # persist position after a drag settles
  if ($script:lastMove -and ($now - $script:lastMove).TotalMilliseconds -gt 800) {
    $script:lastMove = $null
    Clamp-X
    $script:feetBottom = $window.Top + $window.ActualHeight
    Clamp-Feet
    Write-Json $posFile @{ left = [int]$window.Left; feetBottom = [int]$script:feetBottom; walk = $script:walk }
  }
})
$loop.Start()

# ---------- walk ----------
$walkTimer = New-Object System.Windows.Threading.DispatcherTimer
$walkTimer.Interval = [TimeSpan]::FromSeconds(19)
$walkTimer.Add_Tick({
  if (-not $script:walk -or $script:pending -or (Test-Calm) -or $script:away -or -not $window.IsVisible) { return }
  if ($script:lastMove -or ($script:bubbleUntil -and [DateTime]::Now -lt $script:bubbleUntil)) { return }
  $a = [System.Windows.SystemParameters]::WorkArea
  $step = Get-Random -Minimum -110 -Maximum 110
  $nx = [Math]::Min([Math]::Max($a.Left + 10, $window.Left + $step), $a.Right - $window.Width - 10)
  $window.Left = $nx
  Say (Pick-Line 'walk') 2200 -Ambient
  $script:hopUntil = [DateTime]::Now.AddMilliseconds(450)
})
$walkTimer.Start()

Write-Json $aliveFile @{ at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); pid = $PID }
$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$app.Add_DispatcherUnhandledException({
  param($sender,$eventArgs)
  $eventArgs.Handled=$true
  petLog ('UI action failed: '+$eventArgs.Exception.Message)
  try{Say '刚才这一步没能完成，数据没有保存成功的话，可以稍后再试一次。' 6000 -Raw}catch{}
})
try { [void]$app.Run($window) }
finally {
  $loop.Stop(); $walkTimer.Stop()
  try { $tray.Visible = $false; $tray.Dispose() } catch { }
  try { $script:uiMutex.ReleaseMutex(); $script:uiMutex.Dispose() } catch { }
  Remove-Item -LiteralPath $aliveFile -Force -ErrorAction SilentlyContinue
}
exit 0
