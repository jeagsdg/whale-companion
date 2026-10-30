# Read-only health checks. Dot sourcing has no WPF, process or network side effects.
function Read-PetDiagnosticJson([string]$Path, [int]$MaxBytes = 1048576) {
  $stream = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    if ($stream.Length -gt $MaxBytes) { return @{ state = 'too-large'; data = $null } }
    # Most records are a few hundred bytes. Do not allocate a megabyte for each
    # small receipt, and reject a concurrently growing file rather than chasing it.
    $buffer = New-Object byte[] ([int]$stream.Length + 1); $count = 0
    while ($count -lt $buffer.Length) {
      $read = $stream.Read($buffer, $count, $buffer.Length - $count)
      if ($read -eq 0) { break }; $count += $read
    }
    if ($count -eq $buffer.Length -and $stream.ReadByte() -ge 0) { return @{ state = 'invalid'; data = $null } }
    if ($count -gt $MaxBytes) { return @{ state = 'too-large'; data = $null } }
    $raw = [Text.Encoding]::UTF8.GetString($buffer, 0, $count).TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{ state = 'invalid'; data = $null } }
    $raw = $raw.Trim()
    if (-not $raw.StartsWith('{') -or -not $raw.EndsWith('}')) { return @{ state = 'invalid'; data = $null } }
    $data = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $data -or $data -is [Array] -or $data -is [string] -or $data -is [ValueType]) { return @{ state = 'invalid'; data = $null } }
    return @{ state = 'ok'; data = $data }
  } catch [IO.FileNotFoundException] { return @{ state = $(if ($stream) { 'invalid' } else { 'missing' }); data = $null } }
  catch [IO.DirectoryNotFoundException] { return @{ state = $(if ($stream) { 'invalid' } else { 'missing' }); data = $null } }
  catch { return @{ state = 'invalid'; data = $null } }
  finally { if ($stream) { $stream.Dispose() } }
}
function ConvertTo-PetDiagnosticStamp($Value) {
  $stamp = 0.0
  if (-not [double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$stamp)) { return $null }
  if ([double]::IsNaN($stamp) -or [double]::IsInfinity($stamp) -or $stamp -le 0 -or $stamp -gt 253402300799999) { return $null }
  return $stamp
}
function ConvertTo-PetDiagnosticTime($Value) {
  $stamp = ConvertTo-PetDiagnosticStamp $Value
  if ($null -ne $stamp) { try { return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$stamp).ToString('o') } catch { return $null } }
  # News uses ISO timestamps; heartbeats are checked separately as numeric UTC ms.
  $text = [string]$Value; $parsed = [DateTimeOffset]::MinValue
  if ($text.Length -le 64 -and $text -match '^\d{4}-\d{2}-\d{2}T' -and [DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $parsed.ToUniversalTime().ToString('o') }
  return $null
}
function Test-PetDiagnosticFlag($Value) { return ($Value -eq $true -or [string]$Value -ceq 'true') }
function Get-PetDiagnosticHeartbeat([string]$PetHome, [string]$Name, [string]$File, [double]$NowMs, [bool]$Stopped) {
  $record = Read-PetDiagnosticJson (Join-Path $PetHome $File)
  $result = [ordered]@{ name = $Name; state = 'missing'; pid = $null; processRunning = $false; ageSeconds = $null; lastSeenAt = $null; message = '没有收到运行信号。' }
  if ($record.state -eq 'missing') {
    if ($Stopped) { $result.state = 'stopped'; $result.message = '已按你的选择退出。' }
    return [pscustomobject]$result
  }
  if ($record.state -ne 'ok') { $result.state = 'invalid'; $result.message = '运行信号无法读取；稍后刷新，若仍出现请重新打开功能服务。'; return [pscustomobject]$result }
  $stamp = ConvertTo-PetDiagnosticStamp $record.data.at; $processId = 0
  if ($null -eq $stamp -or -not [int]::TryParse([string]$record.data.pid, [ref]$processId) -or $processId -le 0) {
    $result.state = 'invalid'; $result.message = '运行信号中的时间或进程编号不正确。'; return [pscustomobject]$result
  }
  $result.pid = $processId; $result.lastSeenAt = ConvertTo-PetDiagnosticTime $stamp
  $age = $NowMs - $stamp; $result.ageSeconds = [Math]::Round($age / 1000, 1)
  if ($age -lt -30000) { $result.state = 'invalid'; $result.message = '运行信号的时间在未来，请检查系统时间后刷新。'; return [pscustomobject]$result }
  $process = $null
  try { $process = [Diagnostics.Process]::GetProcessById($processId); $result.processRunning = -not $process.HasExited }
  catch { $result.processRunning = $false }
  finally { if ($process) { $process.Dispose() } }
  if (-not $result.processRunning) { $result.state = if ($Stopped) { 'stopped' } else { 'offline' }; $result.message = if ($Stopped) { '已按你的选择退出。' } else { '服务进程已结束，功能可能暂时无法响应。' } }
  elseif ($age -ge 45000) { $result.state = if ($Stopped) { 'stopped' } else { 'stale' }; $result.message = if ($Stopped) { '已退出，旧运行信号仍在本机保留。' } else { '超过 45 秒没有更新，服务可能无响应。' } }
  else { $result.state = 'healthy'; $result.message = '正在正常响应。' }
  return [pscustomobject]$result
}
function Get-PetDiagnosticFiles([string]$Folder, [int]$Limit = 256) {
  $files = New-Object 'System.Collections.Generic.List[object]'; $iterator = $null; $limited = $false; $unavailable = $false
  try {
    if (-not [IO.Directory]::Exists($Folder)) { return @{ files = @(); limited = $false; unavailable = $false } }
    $iterator = [IO.Directory]::EnumerateFiles($Folder, '*.json', [IO.SearchOption]::TopDirectoryOnly).GetEnumerator()
    while ($iterator.MoveNext()) {
      if ($files.Count -ge $Limit) { $limited = $true; break }
      try { $info = New-Object IO.FileInfo ([string]$iterator.Current); $files.Add($info) } catch { $unavailable = $true }
    }
  } catch { $unavailable = $true }
  finally { if ($iterator -is [IDisposable]) { $iterator.Dispose() } }
  return @{ files = @($files.ToArray()); limited = $limited; unavailable = $unavailable }
}
function Get-PetDiagnosticLogSummary([string]$Path) {
  $stream = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $length = [int][Math]::Min(32768, $stream.Length); [void]$stream.Seek(-$length, [IO.SeekOrigin]::End)
    $bytes = New-Object byte[] $length; $count = 0
    while ($count -lt $length) { $read = $stream.Read($bytes, $count, $length - $count); if (-not $read) { break }; $count += $read }
    $tail = [Text.Encoding]::UTF8.GetString($bytes, 0, $count)
    # Never return raw log text: it may include paths or user-authored content.
    $matches = [regex]::Matches($tail, '(?im)^.*(?:failed|exception|\berror\b|失败|错误).*$')
    return @{ file = [IO.Path]::GetFileName($Path); inspectedBytes = $count; failureLines = [Math]::Min($matches.Count, 1000); modifiedAt = [IO.File]::GetLastWriteTimeUtc($Path).ToString('o') }
  } catch { return $null }
  finally { if ($stream) { $stream.Dispose() } }
}
function Get-PetHealthReport([string]$PetHome, [DateTime]$Now = [DateTime]::Now) {
  $homePath = ''; $pathValid = $true
  try { $homePath = [IO.Path]::GetFullPath($PetHome) } catch { $pathValid = $false }
  $nowMs = [DateTimeOffset]::new($Now.ToUniversalTime()).ToUnixTimeMilliseconds()
  $suggestions = New-Object 'System.Collections.Generic.List[string]'
  if (-not $pathValid) { return [pscustomobject]@{ schemaVersion = 1; checkedAt = $Now.ToUniversalTime().ToString('o'); home = ''; status = 'attention'; summary = '安装目录无效。'; suggestions = @('请提供桌宠安装目录后重新检查。'); components = @(); missingFiles = @(); dataIssues = @(); commands = $null; news = $null; logs = @(); mode = $null; version = $null; limits = @{ jsonBytes = 1048576; fileCountPerFolder = 256; receiptsRead = 64; logTailBytes = 32768 } } }
  $prefs = Read-PetDiagnosticJson (Join-Path $homePath 'pet-preferences.json')
  $control = Read-PetDiagnosticJson (Join-Path $homePath 'control.json')
  $hidden = Read-PetDiagnosticJson (Join-Path $homePath 'hidden.json')
  $version = Read-PetDiagnosticJson (Join-Path $homePath 'runtime-version.json')
  $news = Read-PetDiagnosticJson (Join-Path $homePath 'news.json')
  $refresh = Read-PetDiagnosticJson (Join-Path $homePath 'news-refresh-status.json')
  $stopped = Test-PetDiagnosticFlag $control.data.stopped
  $mode = if ($prefs.data.displayMode -eq 'native') { 'native' } else { 'desktop' }
  $components = @(
    (Get-PetDiagnosticHeartbeat $homePath '功能服务' 'alive.json' $nowMs $stopped),
    (Get-PetDiagnosticHeartbeat $homePath 'Codex 连接桥' 'bridge-alive.json' $nowMs $stopped),
    (Get-PetDiagnosticHeartbeat $homePath '自动唤醒监视器' 'host-watch-alive.json' $nowMs $false)
  )
  $modeDescription = if ($stopped) { '已退出：待办等操作暂不接收，需主动重新打开功能服务。' } elseif ($mode -eq 'native') { '正在使用应用内置宠物，独立桌宠保持隐藏；功能面板仍可单独打开。内置宠物是否显示，请在应用的宠物设置中查看。' } elseif ($hidden.state -ne 'missing') { '独立桌宠已隐藏；功能服务正常时，待办、提醒和专注数据仍会保留。' } else { '独立桌宠模式；请结合运行信号确认服务是否正常。' }
  if ($stopped) { $suggestions.Add('你已选择退出。需要待办、专注或设置时，可主动打开对应面板；检查本身不会启动服务。') }
  if ($mode -eq 'native') { $suggestions.Add('内置宠物的外观和显示由应用设置控制；原有待办、提醒、专注和新闻通过功能面板使用。') }
  $unhealthy = @($components | Where-Object { $_.state -notin @('healthy', 'stopped') })
  if ($unhealthy.Count -and -not $stopped) { $suggestions.Add('先刷新一次；若功能服务或连接桥仍未响应，请主动重新打开功能面板。仍无法恢复时，用本项目安装程序修复后再检查。') }
  if ($components[2].state -ne 'healthy') { $suggestions.Add('自动唤醒监视器没有正常响应，可能影响下次打开 Codex 时唤醒。请运行项目安装程序修复自动唤醒注册。') }
  $missing = New-Object 'System.Collections.Generic.List[string]'
  foreach ($file in @('whale-pet.ps1','whale-pet-start.ps1','whale-pet-common.ps1','whale-companion.ps1','whale-companion-ui.ps1','whale-focus.ps1','whale-media.ps1','whale-news.ps1','whale-news-worker.ps1','whale-pet-http.ps1','whale-codex-core.ps1','whale-host-watch.exe','whale-host-native.dll','whale-mcp.mjs','sticker-catalog.json')) {
    if (-not [IO.File]::Exists((Join-Path $homePath $file))) { $missing.Add($file) }
  }
  if ($missing.Count) { $suggestions.Add('有必要组件缺失，请运行项目安装程序修复；不要删除偏好、待办或收藏文件。') }
  $issues = New-Object 'System.Collections.Generic.List[object]'
  foreach ($entry in @(@{ file = 'pet-preferences.json'; record = $prefs }, @{ file = 'control.json'; record = $control }, @{ file = 'hidden.json'; record = $hidden }, @{ file = 'runtime-version.json'; record = $version }, @{ file = 'news.json'; record = $news }, @{ file = 'news-refresh-status.json'; record = $refresh })) {
    if ($entry.record.state -notin @('ok','missing')) { $issues.Add(@{ file = $entry.file; state = $entry.record.state }) }
  }
  if ($issues.Count) { $suggestions.Add('部分本机状态文件无法读取，诊断已跳过。请保留原文件和备份；不要靠清空待办或设置来修复。') }
  $inbox = Get-PetDiagnosticFiles (Join-Path $homePath 'commands')
  $receipts = Get-PetDiagnosticFiles (Join-Path $homePath 'command-results')
  $failed = 0; $expired = 0; $invalid = 0; $queuedSampled = 0; $receiptSampled = 0; $lastFailedAt = $null
  foreach ($file in @($inbox.files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 64)) {
    $queuedSampled++; $command = Read-PetDiagnosticJson $file.FullName; $stamp = ConvertTo-PetDiagnosticStamp $command.data.at
    if ($command.state -ne 'ok' -or $null -eq $stamp -or $stamp -gt $nowMs + 30000) { $invalid++; continue }
    if ($nowMs - $stamp -gt 300000) { $expired++ }
  }
  foreach ($file in @($receipts.files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 64)) {
    $receiptSampled++; $receipt = Read-PetDiagnosticJson $file.FullName
    if ($receipt.state -ne 'ok') { $invalid++; continue }
    if ($receipt.data.status -eq 'failed') { $failed++; $time = ConvertTo-PetDiagnosticTime $receipt.data.at; if ($time -and (-not $lastFailedAt -or $time -gt $lastFailedAt)) { $lastFailedAt = $time } }
  }
  if ($expired) { $suggestions.Add('有操作排队超过 5 分钟，已无法确认完成。恢复功能服务后，请查看原数据，再重新提交需要的操作。') }
  if ($failed) { $suggestions.Add('最近保留的操作结果中有失败记录。请查看对应待办、专注或提醒是否生效；排队成功并不等于执行完成。') }
  $queueLimited = $inbox.limited -or $receipts.limited -or $inbox.files.Count -gt 64 -or $receipts.files.Count -gt 64
  $commands = [pscustomobject]@{ pendingCount = $inbox.files.Count; pendingCountIsLowerBound = [bool]$inbox.limited; inspectedPending = $queuedSampled; expiredInSample = $expired; failedInSample = $failed; inspectedResults = $receiptSampled; invalidInSample = $invalid; lastFailedAt = $lastFailedAt; sampleLimited = [bool]$queueLimited; unavailable = [bool]($inbox.unavailable -or $receipts.unavailable) }
  $newsState = if ($news.state -eq 'ok' -and $news.data.status -in @('ok','partial','offline','empty','ready','fresh','stale','error','disabled')) { [string]$news.data.status } elseif ($news.state -eq 'missing') { 'empty' } else { $news.state }
  $refreshState = if ($refresh.state -eq 'ok' -and $refresh.data.state -in @('queued','running','completed','failed')) { [string]$refresh.data.state } elseif ($refresh.state -eq 'missing') { 'idle' } else { 'invalid' }
  $refreshStamp = ConvertTo-PetDiagnosticStamp $refresh.data.at; $refreshAge = $null
  if ($null -ne $refreshStamp) { $refreshAge = [Math]::Round(($nowMs - $refreshStamp) / 1000, 1) }
  if ($refreshState -in @('queued','running') -and ($null -eq $refreshAge -or $refreshAge -lt -30 -or $refreshAge -gt 180)) { $refreshState = 'stalled' }
  $newsMessage = switch ($refreshState) { 'running' { '正在更新，原有新闻仍可查看。' } 'queued' { '已请求更新，等待新闻服务响应。' } 'failed' { '本次更新失败，原有新闻仍保留。可以稍后重试。' } 'stalled' { '更新状态停留过久，请打开新闻面板再试一次。' } 'completed' { '最近一次更新已结束。' } 'invalid' { '更新状态无法读取，原有收藏不会被修改。' } default { if ($newsState -eq 'empty') { '还没有新闻缓存，可打开新闻面板获取。' } else { '可以打开新闻面板查看缓存和收藏。' } } }
  if ($newsState -eq 'offline') { $newsMessage += ' 新闻来源暂时连接不上，正在保留旧缓存。' }
  elseif ($newsState -eq 'partial') { $newsMessage += ' 部分新闻来源暂不可用，其它来源与旧缓存仍可查看。' }
  elseif ($newsState -eq 'disabled') { $newsMessage += ' 当前没有启用的新闻话题，可在设置中选择。' }
  if ($refreshState -in @('failed','stalled','invalid')) { $suggestions.Add('新闻更新未正常完成。打开新闻面板重试；网络不通时仍可查看已有缓存和收藏。') }
  $itemCount = if ($news.state -eq 'ok' -and $news.data.items -is [Array]) { [Math]::Min($news.data.items.Count, 10000) } else { 0 }
  $fetched = ConvertTo-PetDiagnosticTime $news.data.lastFetchedAt; if (-not $fetched) { $fetched = ConvertTo-PetDiagnosticTime $news.data.fetchedAt }
  $versionValue = if ($version.state -eq 'ok' -and [string]$version.data.version -match '^[0-9A-Za-z][0-9A-Za-z.+_-]{0,39}$') { [string]$version.data.version } else { '未知' }
  if ($version.state -eq 'missing') { $suggestions.Add('当前安装没有版本标记，可能来自较早版本；运行安装程序可补齐组件和版本信息。') }
  $logs = @(); foreach ($file in @('host-watch.log','host-bootstrap.log')) { $log = Get-PetDiagnosticLogSummary (Join-Path $homePath $file); if ($log) { $logs += $log } }
  $parentPath = [IO.Path]::GetDirectoryName($homePath.TrimEnd('\','/'))
  if ($parentPath) { $log = Get-PetDiagnosticLogSummary (Join-Path $parentPath 'dsh-whale-pet.log'); if ($log) { $logs += $log } }
  $attention = $missing.Count -or $issues.Count -or $unhealthy.Count -or $expired -or $failed -or $invalid -or $refreshState -in @('failed','stalled','invalid') -or $newsState -in @('offline','error') -or $version.state -ne 'ok' -or $commands.unavailable
  $status = if ($stopped -and -not $missing.Count -and -not $issues.Count) { 'stopped' } elseif ($attention) { 'attention' } else { 'healthy' }
  $summary = switch ($status) { 'healthy' { '必要组件齐全，功能服务正在响应。' } 'stopped' { '已按你的选择退出，个人数据仍保留。' } default { '发现需要查看的项目，下方提供了恢复建议。' } }
  if (-not $suggestions.Count) { $suggestions.Add('当前无需修复。某个操作无响应时，可先在这里刷新，或查看该操作的执行结果。') }
  return [pscustomobject]@{ schemaVersion = 1; checkedAt = $Now.ToUniversalTime().ToString('o'); home = $homePath; status = $status; summary = $summary; version = @{ value = $versionValue; state = $version.state }; mode = @{ displayMode = $mode; hidden = ($hidden.state -ne 'missing'); stopped = $stopped; supportOnly = (Test-PetDiagnosticFlag $hidden.data.supportOnly); description = $modeDescription }; components = $components; commands = $commands; news = @{ cacheState = $newsState; cachedItems = $itemCount; fetchedAt = $fetched; refreshState = $refreshState; refreshAgeSeconds = $refreshAge; message = $newsMessage }; missingFiles = @($missing.ToArray()); dataIssues = @($issues.ToArray()); logs = $logs; suggestions = @($suggestions.ToArray() | Select-Object -Unique); limits = @{ jsonBytes = 1048576; fileCountPerFolder = 256; receiptsRead = 64; logTailBytes = 32768 }; privacy = '只检查本机运行状态，不读取聊天正文、配置密钥或待办内容；不联网、不修改原数据。' }
}
function ConvertTo-PetHealthText($Report) {
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('桌宠健康检查'); $lines.Add([string]$Report.summary); $lines.Add('检查时间：' + [string]$Report.checkedAt); $lines.Add('安装目录：' + [string]$Report.home)
  if ($Report.version) { $lines.Add('安装版本：' + [string]$Report.version.value) }
  if ($Report.mode) { $lines.Add(''); $lines.Add([string]$Report.mode.description) }
  foreach ($component in @($Report.components)) {
    $age = if ($null -ne $component.ageSeconds) { '（距今 ' + [string]$component.ageSeconds + ' 秒）' } else { '' }
    $lines.Add($component.name + '：' + $component.message + $age)
  }
  if ($Report.commands) {
    $countLabel = if ($Report.commands.pendingCountIsLowerBound) { '至少 ' } else { '' }
    $lines.Add(''); $lines.Add('等待处理的操作：' + $countLabel + [string]$Report.commands.pendingCount)
    $lines.Add('已抽查排队操作 ' + [string]$Report.commands.inspectedPending + ' 条、执行结果 ' + [string]$Report.commands.inspectedResults + ' 条；失败 ' + [string]$Report.commands.failedInSample + ' 条，过期 ' + [string]$Report.commands.expiredInSample + ' 条，无法读取 ' + [string]$Report.commands.invalidInSample + ' 条。')
    if ($Report.commands.sampleLimited) { $lines.Add('目录较大，结果为有数量限制的抽查，不代表完整历史。') }
    if ($Report.commands.unavailable) { $lines.Add('有操作目录暂时无法访问，数量可能不完整。') }
  }
  if ($Report.news) { $lines.Add(''); $lines.Add('新闻：' + [string]$Report.news.message); $lines.Add('缓存新闻数：' + [string]$Report.news.cachedItems) }
  if (@($Report.missingFiles).Count) { $lines.Add(''); $lines.Add('缺失组件：' + ($Report.missingFiles -join '、')) }
  foreach ($issue in @($Report.dataIssues)) { $lines.Add('无法读取的本机状态：' + [string]$issue.file + '（' + [string]$issue.state + '）') }
  foreach ($log in @($Report.logs)) { if ($log.failureLines) { $lines.Add('日志 ' + $log.file + ' 的末尾发现 ' + [string]$log.failureLines + ' 条错误提示；这是有限抽查，可能包含旧记录。') } }
  $lines.Add(''); $lines.Add('建议：'); foreach ($suggestion in @($Report.suggestions)) { $lines.Add('• ' + $suggestion) }
  $lines.Add(''); $lines.Add([string]$Report.privacy)
  return ($lines -join [Environment]::NewLine)
}
function New-PetDiagnosticsWindow([string]$PetHome) {
  $dialog = New-CompanionWindow '桌宠 · 健康检查' 660 740; $panel = $dialog.Tag.panel
  [void](Add-CompanionLabel $panel '哪里没响应，一起看清楚' 21)
  [void](Add-CompanionLabel $panel '只在你打开或刷新时检查；不会自动重启服务或清空数据。')
  $row = New-Object Windows.Controls.WrapPanel; [void]$panel.Children.Add($row)
  $refresh = Add-CompanionButton $row '刷新检查'; $copy = Add-CompanionButton $row '复制报告'; $export = Add-CompanionButton $row '导出到文件'
  $status = Add-CompanionLabel $panel ''
  $text = New-Object Windows.Controls.TextBox; $text.IsReadOnly = $true; $text.TextWrapping = [Windows.TextWrapping]::Wrap
  $text.MinHeight = 390; $text.Padding = New-Object Windows.Thickness(10); $text.AcceptsReturn = $true; [void]$panel.Children.Add($text)
  $context = @{ home = $PetHome; report = $null; text = $text; status = $status }
  $refreshAction = {
    try { $context.report = Get-PetHealthReport $context.home; $context.text.Text = ConvertTo-PetHealthText $context.report; $context.status.Text = '已完成本机检查。' }
    catch { $context.status.Text = '检查暂时未完成，请稍后刷新。原数据没有被修改。' }
  }.GetNewClosure()
  $refresh.Add_Click($refreshAction)
  $copy.Add_Click({ try { if (-not $context.report) { return }; [Windows.Clipboard]::SetText($context.text.Text); $context.status.Text = '报告已复制，可粘贴给帮助你排查的人。' } catch { $context.status.Text = '剪贴板正忙，请稍后再复制。' } }.GetNewClosure())
  $export.Add_Click({
    try {
      if (-not $context.report) { return }
      $save = New-Object Microsoft.Win32.SaveFileDialog; $save.Title = '保存本机健康报告'; $save.Filter = '文字报告 (*.txt)|*.txt|结构化报告 (*.json)|*.json'; $save.FileName = '桌宠健康检查-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss'); $save.AddExtension = $true
      if ($save.ShowDialog() -eq $true) {
        $content = if ($save.FilterIndex -eq 2) { $context.report | ConvertTo-Json -Depth 10 } else { $context.text.Text }
        [IO.File]::WriteAllText($save.FileName, $content, (New-Object Text.UTF8Encoding($true))); $context.status.Text = '报告已保存到你选择的位置。'
      }
    } catch { $context.status.Text = '报告没有保存成功，请选择可写的位置后重试。' }
  }.GetNewClosure())
  # No recurring timer or background work remains after this window is closed.
  $dialog.Add_Closed({ $context.report = $null }.GetNewClosure())
  $dialog.Tag.controls = @{ refresh = $refresh; copy = $copy; export = $export; text = $text; status = $status }; $dialog.Tag.context = $context
  & $refreshAction
  return $dialog
}
function Show-PetDiagnostics([string]$PetHome = '') {
  if (-not $PetHome) { $PetHome = [string](Get-Variable -Name PetHome -Scope 1 -ValueOnly -ErrorAction SilentlyContinue) }
  if (-not $PetHome) { $PetHome = $PSScriptRoot }
  if ($script:diagnosticsWindow -and $script:diagnosticsWindow.IsVisible) { [void]$script:diagnosticsWindow.Activate(); return }
  $script:diagnosticsWindow = New-PetDiagnosticsWindow $PetHome
  $script:diagnosticsWindow.Show()
}
