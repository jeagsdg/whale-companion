$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-pet-common.ps1')
. (Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-news.ps1')
$script:passed = 0
function Assert($Condition, [string]$Name) { if (-not $Condition) { throw ('FAIL: ' + $Name) }; $script:passed++; Write-Output ('PASS: ' + $Name) }
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\.diag'))
$testHome = Join-Path $testRoot ('whale-news-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testHome)
$time = New-Object DateTimeOffset([datetime]'2026-10-14T10:00:00')
$source = @(Get-WhaleNewsSources | Where-Object { $_.id -eq 'ithome' })[0]
$pub = $time.AddMinutes(-10).ToString('r')
$xml = @"
<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel>
<item><title>AI 新进展 &amp; 研究</title><link>https://www.ithome.com/0/111/222.htm?utm_source=feed</link><description><![CDATA[<p>简短摘要 <b>文字</b></p><script>steal()</script>]]></description><pubDate>$pub</pubDate></item>
<item><title>AI 新进展 &amp; 研究</title><link>https://www.ithome.com/0/111/222.htm?utm_source=feed</link><pubDate>$pub</pubDate></item>
<item><title>危险来源</title><link>https://www.ithome.com.evil.example/entry</link><pubDate>$pub</pubDate></item>
<item><title>京东开抢红包</title><link>https://www.ithome.com/0/111/333.htm</link><pubDate>$pub</pubDate></item>
</channel></rss>
"@
try {
  $parsed = @(ConvertFrom-WhaleNewsFeed -Xml $xml -Source $source -Now $time)
  Assert ($parsed.Count -eq 1) 'RSS去重、限定来源域名、过滤促销'
  Assert ($parsed[0].title -eq 'AI 新进展 & 研究' -and $parsed[0].summary -eq '简短摘要 文字') '标题与短摘要安全解码，移除HTML脚本'
  Assert ($parsed[0].url -eq 'https://www.ithome.com/0/111/222.htm' -and $parsed[0].topics -contains 'ai') '去除追踪参数并识别AI主题'
  $gameXml = '<rss><channel><item><title>Steam 游戏更新</title><link>https://www.ithome.com/0/111/444.htm</link></item></channel></rss>'
  $games = @(ConvertFrom-WhaleNewsFeed -Xml $gameXml -Source $source -Now $time)
  Assert ($games[0].topics -contains 'games') '中文科技源中的游戏新闻归入游戏话题'
  Assert ((Test-WhaleNewsSourceTopics $source @('ai')) -and (Test-WhaleNewsSourceTopics $source @('games'))) '只选AI或游戏时也抓取有对应中文新闻的科技来源'
  Assert ([DateTimeOffset]::Parse($parsed[0].publishedAt) -eq $time.AddMinutes(-10)) '保留来源发布时间，不把抓取时间当发布时间'
  foreach ($bad in @('<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///C:/Windows/win.ini">]><rss><channel><item><title>&x;</title></item></channel></rss>', '<html><body>not rss</body></html>', '<rss><broken></rss>')) {
    $threw = $false
    try { [void](ConvertFrom-WhaleNewsFeed -Xml $bad -Source $source -Now $time) } catch { $threw = $true }
    Assert $threw '拒绝DTD、非RSS和损坏XML'
  }
  $atomSource = @(Get-WhaleNewsSources | Where-Object { $_.id -eq 'mit-ai' })[0]
  $atom = '<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Research</title><link rel="alternate" href="https://news.mit.edu/2026/research"/><summary>Short summary</summary><published>' + $time.AddHours(-1).ToString('o') + '</published></entry></feed>'
  $atomItems = @(ConvertFrom-WhaleNewsFeed -Xml $atom -Source $atomSource -Now $time)
  Assert ($atomItems.Count -eq 1 -and $atomItems[0].source -eq 'MIT News') 'Atom命名空间与alternate链接解析'
  Assert (-not (Test-WhaleNewsUrl 'https://www.ithome.com@evil.test/item' $source.articleHosts)) '拒绝用户信息伪装域名'
  Assert (-not (Test-WhaleNewsUrl 'https://www.ithome.com:9443/item' $source.articleHosts)) '拒绝非标准HTTPS端口'
  Assert (-not (Get-WhaleNewsArticleUrl 'file:///C:/test.txt' $source)) '拒绝本地和非HTTP链接'
  Assert ((Get-WhaleNewsArticleUrl 'http://www.ithome.com/0/111/222.htm' $source) -eq 'https://www.ithome.com/0/111/222.htm') '仅对白名单来源升级旧HTTP链接'
  Assert (-not (Get-WhaleNewsPublishedAt 'wrong-date' $source $time)) '错误日期不会伪造成今日新闻'
  Assert (-not (Get-WhaleNewsPublishedAt $time.AddDays(1).ToString('o') $source $time)) '未来日期不会伪造成今日新闻'
  $cnTime = Get-WhaleNewsPublishedAt '2026-10-14 09:00:00' $source $time
  Assert ($cnTime -eq '2026-10-14T01:00:00.0000000+00:00') '无时区中文来源使用东八区'
  $prefs = @{ newsTopics = @('tech'); newsEnabled = $true; newsMinMinutes = 60; newsMaxMinutes = 180; newsDailyLimit = 3 }
  $fetchFixture = { param($s) if($s.id -eq 'ithome'){return $xml}; return ('<rss><channel><item><title>'+ $s.id +'研究新闻</title><link>https://'+$s.articleHosts[0]+'/fixture</link><pubDate>'+$pub+'</pubDate></item></channel></rss>') }
  $cache = Update-WhaleNewsCache -PetHome $testHome -Preferences $prefs -Now $time -Fetcher $fetchFixture
  Assert ($cache.status -eq 'ok' -and $cache.items.Count -gt 1 -and @($cache.items|Where-Object{$_.sourceId -eq 'ithome'}).Count -eq 1) '成功抓取写入原子缓存'
  $offline = Update-WhaleNewsCache -PetHome $testHome -Preferences $prefs -Now $time.AddHours(1) -Fetcher { throw 'offline' }
  Assert ($offline.status -eq 'offline' -and $offline.items.Count -eq $cache.items.Count -and $offline.lastFetchedAt -eq $cache.lastFetchedAt -and $offline.lastAttemptAt -ne $offline.lastFetchedAt) '离线保留原缓存和原抓取时间'
  Assert ($offline.sources[0].code -eq 'source-unavailable' -and $offline.sources[0].durationMs -ge 0 -and $offline.sources[0].message -notmatch 'offline') '来源失败记录固定故障码与耗时，不保存原始异常内容'
  Assert ($offline.sources[0].lastSuccessAt -eq $cache.sources[0].lastSuccessAt -and $offline.sources[0].lastCheckedAt -ne $offline.sources[0].lastSuccessAt) '失败仍保留每源最近成功时间，检查时间独立更新'
  $timeoutError=New-Object Net.WebException('request failed',[Net.WebExceptionStatus]::Timeout)
  $wrappedError=New-Object Reflection.TargetInvocationException($timeoutError)
  Assert ((Get-WhaleNewsFailureCode ([pscustomobject]@{Exception=$wrappedError})) -eq 'timeout') 'PowerShell包装后的网络超时仍能归类，便于诊断'
  $aiHome = Join-Path $testHome 'ai-only'
  $ai = Update-WhaleNewsCache -PetHome $aiHome -Preferences @{newsTopics=@('ai')} -Now $time -Fetcher {param($s) if($s.id -eq 'ithome'){return $xml};throw 'offline'}
  Assert ($ai.items.Count -eq 1 -and $ai.items[0].sourceId -eq 'ithome' -and $ai.items[0].language -eq 'zh') '仅订阅AI也能获得中文AI资讯'
  $none = Update-WhaleNewsCache -PetHome (Join-Path $testHome 'no-topics') -Preferences @{newsTopics=@()} -Now $time -Fetcher {throw '不应抓取'}
  Assert ($none.status -eq 'disabled' -and $none.sources.Count -eq 0) '未选新闻话题时不请求网络，也不误报离线'
  $empty = Update-WhaleNewsCache -PetHome (Join-Path $testHome 'empty-feed') -Preferences @{newsTopics=@('tech')} -Now $time -Fetcher {return '<rss><channel></channel></rss>'}
  Assert ($empty.sources[0].state -eq 'empty' -and $empty.sources[0].ok) '空RSS与来源不可用分别展示，空订阅不是连接失败'
  $staleXml='<rss><channel><item><title>旧来源文章</title><link>https://www.ithome.com/0/111/222.htm</link><pubDate>'+$time.AddDays(-30).ToString('r')+'</pubDate></item></channel></rss>'
  $stale = Update-WhaleNewsCache -PetHome (Join-Path $testHome 'stale-feed') -Preferences @{newsTopics=@('tech')} -Now $time -Fetcher {return $staleXml}
  Assert ($stale.sources[0].state -eq 'stale' -and $stale.items.Count -eq 0 -and $stale.status -eq 'partial') 'HTTP成功但长期无更新的来源明确标旧，不把旧文当今日资讯'
  $old = $parsed[0] | Select-Object *; $old.id = 'old'; $old.publishedAt = $time.AddDays(-2).ToString('o')
  $unknown = $parsed[0] | Select-Object *; $unknown.id = 'unknown'; $unknown.publishedAt = ''
  Assert (-not (Select-WhaleNewsForShare -Items @($old,$unknown) -Preferences $prefs -Now $time)) '不主动分享过期或未知日期新闻'
  Assert (-not (Select-WhaleNewsForShare -Items $parsed -Preferences $prefs -Seen @($parsed[0].id) -Now $time)) '已经分享的新闻不重复推送'
  $untrusted = $parsed[0] | Select-Object *; $untrusted.url = 'https://evil.example/article'
  Assert (-not (Select-WhaleNewsForShare -Items @($untrusted) -Preferences $prefs -Now $time)) '缓存被改写后仍拒绝非来源白名单链接'
  $merge = @(Merge-WhaleNewsItems @($parsed[0]) @($parsed[0],$atomItems[0]) $time)
  Assert ($merge.Count -eq 2) '跨次刷新按稳定ID去重并保留其他来源'
  $volume = @()
  for ($n=0;$n -lt 105;$n++) {
    $copy=$parsed[0]|Select-Object *;$copy.id='volume-'+$n;$copy.title='科技资讯 '+$n;$copy.url='https://www.ithome.com/0/111/'+$n+'.htm';$copy.publishedAt=$time.AddMinutes(-$n).ToString('o');$volume+=$copy
  }
  $official=$atomItems[0]|Select-Object *;$official.publishedAt=$time.AddDays(-1).ToString('o')
  $balanced=@(Merge-WhaleNewsItems $volume @($official) $time)
  Assert ($balanced.Count -eq 100 -and @($balanced|Where-Object{$_.sourceId -eq 'mit-ai'}).Count -eq 1) '百条缓存为低频官方来源保留位置，不被高频来源全部挤掉'
  $allSources=@(Get-WhaleNewsSources);$allItems=@()
  foreach($s in $allSources){for($n=0;$n -lt 12;$n++){$allItems+=[pscustomobject]@{id=$s.id+'-'+$n;sourceId=$s.id;title=$s.id+' news '+$n;url='https://'+$s.articleHosts[0]+'/fixture/'+$n;publishedAt=$time.AddMinutes(-$n).ToString('o')}}}
  $allBalanced=@(Merge-WhaleNewsItems $allItems @() $time)
  Assert ($allSources.Count -eq 11 -and $allBalanced.Count -eq 100 -and @($allBalanced|Group-Object sourceId).Count -eq 11) '十一来源动态分配缓存保留位置，总量仍为一百且不会挤掉来源'
  $fakeSources=@(@{id='fast';xml='<rss/>';delay=20},@{id='broken';fail=$true;delay=0},@{id='also-fast';xml='<feed/>';delay=20})
  $parallel=@(Get-WhaleNewsFetchedFeeds -Sources $fakeSources -BudgetMs 5000 -SourceFetcher {param($s) if($s.fail){throw 'remote body must not persist'};Start-Sleep -Milliseconds $s.delay;return $s.xml})
  Assert ($parallel.Count -eq 3 -and $parallel[0].ok -and -not $parallel[1].ok -and $parallel[2].ok) '单个并发来源失败不拖垮其余来源，按源返回结果'
  Assert ($parallel[1].code -eq 'source-unavailable' -and -not $parallel[1].ContainsKey('message')) '并发错误不泄漏原始远端异常正文'
  $budgetWatch=[Diagnostics.Stopwatch]::StartNew()
  $budget=@(Get-WhaleNewsFetchedFeeds -Sources @(@{id='slow';delay=10000},@{id='quick';delay=10}) -BudgetMs 1500 -SourceFetcher {param($s) Start-Sleep -Milliseconds $s.delay;return '<rss/>'})
  Assert ($budget[0].code -eq 'refresh-budget' -and $budget[1].ok -and $budgetWatch.ElapsedMilliseconds -lt 5000) '整轮预算会取消慢来源并回收池，同时保留已完成来源'
  . (Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-companion-ui.ps1')
  $script:preferences=@{newsTopics=@('tech','ai','world','china','games')}
  $healthRows=@(Get-PetNewsSourceHealthRows $offline)
  Assert ($healthRows.Count -eq 11 -and $healthRows[0].state -eq 'failed' -and $healthRows[0].text -match '最近成功：' -and $healthRows[0].text -match '原因：') '新闻面板逐源解释失败，并显示检查与最近成功时间'
  $emptyRows=@(Get-PetNewsSourceHealthRows $empty)
  Assert ($emptyRows[0].text -match '暂无匹配新闻' -and $emptyRows[0].healthy) '来源健康面板区分空结果与连接故障'
  Write-PetJson (Join-Path $testHome 'news-refresh.lock') @{pid=2147483647;startedAtTicks=1}
  Assert (-not (Test-WhaleNewsRefreshing -PetHome $testHome)) '已崩溃worker的锁立即失效，不让手动刷新空等四分钟'
  $current=[Diagnostics.Process]::GetCurrentProcess()
  try { Write-PetJson (Join-Path $testHome 'news-refresh.lock') @{pid=$PID;startedAtTicks=$current.StartTime.ToUniversalTime().Ticks} } finally {$current.Dispose()}
  Assert (Test-WhaleNewsRefreshing -PetHome $testHome) '运行中的worker锁保留，防止重复启动'
  Write-PetJson (Join-Path $testHome 'news-refresh.lock') @{pid=$PID;startedAtTicks=1}
  Assert (-not (Test-WhaleNewsRefreshing -PetHome $testHome)) 'PID被重用时不把其他进程当成新闻worker'
  Remove-Item -LiteralPath (Join-Path $testHome 'news-refresh.lock') -Force
  Set-WhaleNewsRefreshStatus -PetHome $testHome -State 'failed' -Code 'worker-update-failed' -Message '保留缓存'
  $refreshStatus=Read-PetJson (Join-Path $testHome 'news-refresh-status.json')
  Assert ($refreshStatus.state -eq 'failed' -and $refreshStatus.code -eq 'worker-update-failed' -and [long]$refreshStatus.at -gt 0) '独立记录后台刷新结果，面板可以显示真实失败'
  Remove-Item -LiteralPath (Join-Path $testHome 'news-refresh-status.json') -Force
  $script:newsStarts = 0
  function Start-WhaleNewsRefresh { param([string]$PetHome) $script:newsStarts++; return $true }
  $schedule = @{ version = 1; day = $time.LocalDateTime.ToString('yyyy-MM-dd'); sharedToday = 0; seen = @(); nextShareAt = $time.ToUnixTimeMilliseconds() - 1; nextRefreshAt = $time.ToUnixTimeMilliseconds() + 3600000 }
  Write-PetJson (Join-Path $testHome 'news.json') $cache
  foreach ($flag in @('IsHidden','IsAway','IsBusy')) {
    Write-PetJson (Join-Path $testHome 'news-schedule.json') $schedule
    $arguments = @{ PetHome = $testHome; Preferences = $prefs; Now = $time }; $arguments[$flag] = $true
    Assert (-not (Invoke-WhaleNewsTick @arguments)) ('不打断 ' + $flag)
    Assert ((Read-PetJson (Join-Path $testHome 'news-schedule.json')).sharedToday -eq 0) '被抑制的推送不消耗日配额'
  }
  $night = New-Object DateTimeOffset([datetime]'2026-10-14T23:30:00')
  Assert (-not (Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $night)) '23点到8点不主动推送或联网'
  Assert ($script:newsStarts -eq 0) '安静条件下没有启动后台刷新'
  Write-PetJson (Join-Path $testHome 'news-schedule.json') $schedule
  $share = Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $time
  $saved = Read-PetJson (Join-Path $testHome 'news-schedule.json')
  Assert ($share.id -eq $parsed[0].id -and $saved.sharedToday -eq 1 -and $saved.seen -contains $share.id) '只在实际分享时记录配额与去重'
  $delay = ([long]$saved.nextShareAt - $time.ToUnixTimeMilliseconds()) / 1000
  Assert ($delay -ge 3600 -and $delay -le 10800) '下一次分享在随机60至180分钟内'
  $schedule.sharedToday = 3
  Write-PetJson (Join-Path $testHome 'news-schedule.json') $schedule
  Assert (-not (Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $time)) '达到每日3次后停止主动分享'
  $prefs.newsEnabled = $false
  Assert (-not (Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $time)) '用户关闭新闻后停止计划任务'
  $prefs.newsEnabled = $true; $schedule.sharedToday = 0
  Write-PetJson (Join-Path $testHome 'news-schedule.json') $schedule
  $cache.lastFetchedAt = $time.AddDays(-2).ToString('o'); Write-PetJson (Join-Path $testHome 'news.json') $cache
  Assert (-not (Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $time)) '离线旧缓存不会作为新鲜资讯主动播报'
  Write-PetJson (Join-Path $testHome 'news-schedule.json') @{ day = 'old'; sharedToday = 'bad'; nextShareAt = 'bad'; nextRefreshAt = -1 }
  Assert (-not (Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $time)) '损坏的旧计划字段能够自动恢复'
  $repaired = Read-PetJson (Join-Path $testHome 'news-schedule.json')
  Assert ($repaired.sharedToday -eq 0 -and $repaired.nextShareAt -gt $time.ToUnixTimeMilliseconds()) '恢复计划后随机延期，不在启动瞬间打扰'
  $schedule.sharedToday=0;$schedule.nextShareAt=$time.ToUnixTimeMilliseconds()+100000;$schedule.nextRefreshAt=0
  function Start-WhaleNewsRefresh { param([string]$PetHome) $script:newsStarts++; return $false }
  Write-PetJson (Join-Path $testHome 'news-schedule.json') $schedule
  [void](Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $time)
  Assert ((Read-PetJson (Join-Path $testHome 'news-schedule.json')).nextRefreshAt -eq $time.ToUnixTimeMilliseconds()+60000) '后台启动失败一分钟后可再试，不再空等一小时'
  foreach($outcome in @(@{state='failed';cacheStatus='';delay=300000},@{state='completed';cacheStatus='offline';delay=300000},@{state='completed';cacheStatus='partial';delay=900000},@{state='completed';cacheStatus='ok';delay=3600000})){
    $schedule.nextRefreshAt=$time.ToUnixTimeMilliseconds()+3600000;$schedule.lastRefreshResultAt=0
    Write-PetJson (Join-Path $testHome 'news-schedule.json') $schedule
    Write-PetJson (Join-Path $testHome 'news-refresh-status.json') @{state=$outcome.state;cacheStatus=$outcome.cacheStatus;at=$time.ToUnixTimeMilliseconds()}
    [void](Invoke-WhaleNewsTick -PetHome $testHome -Preferences $prefs -Now $time)
    $saved=Read-PetJson (Join-Path $testHome 'news-schedule.json')
    Assert ($saved.nextRefreshAt -eq $time.ToUnixTimeMilliseconds()+$outcome.delay) ('刷新结果采用共享恢复间隔 '+$outcome.state+'/'+$outcome.cacheStatus)
  }
  # Exercise the actual worker without any network: no selected topics means no requests.
  $workerHome=Join-Path $testHome 'worker-offline-test'
  Write-PetJson (Join-Path $workerHome 'pet-preferences.json') @{newsTopics=@()}
  $workerPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-news-worker.ps1'))
  $info=New-Object Diagnostics.ProcessStartInfo
  $info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$workerPath+'" -PetHome "'+$workerHome+'"'
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $worker=[Diagnostics.Process]::Start($info)
  try {
    if(-not $worker.WaitForExit(15000)){$worker.Kill();throw '测试worker超时'}
    Assert ($worker.ExitCode -eq 0) '实际新闻worker无网络完成并正常退出'
  } finally {$worker.Dispose()}
  $workerStatus=Read-PetJson (Join-Path $workerHome 'news-refresh-status.json')
  Assert ($workerStatus.state -eq 'completed' -and $workerStatus.cacheStatus -eq 'disabled' -and -not [IO.File]::Exists((Join-Path $workerHome 'news-refresh.lock'))) '实际worker写完成状态并清理刷新锁'
  $failedHome=Join-Path $testHome 'worker-persistence-test'
  Write-PetJson (Join-Path $failedHome 'pet-preferences.json') @{newsTopics=@()}
  [void][IO.Directory]::CreateDirectory((Join-Path $failedHome 'news.json'))
  $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$workerPath+'" -PetHome "'+$failedHome+'"'
  $worker=[Diagnostics.Process]::Start($info)
  try { if(-not $worker.WaitForExit(15000)){$worker.Kill();throw '测试worker超时'} } finally {$worker.Dispose()}
  $failedStatus=Read-PetJson (Join-Path $failedHome 'news-refresh-status.json')
  Assert ($failedStatus.state -eq 'failed' -and $failedStatus.code -eq 'worker-update-failed' -and $failedStatus.message -notmatch [regex]::Escape($failedHome)) '实际worker遇到缓存写盘失败时记录真实失败，避免假报更新成功'
  Assert (-not [IO.File]::Exists((Join-Path $failedHome 'news-refresh.lock'))) '写盘失败仍清理刷新锁，允许恢复后再次刷新'
  $concurrentHome=Join-Path $testHome 'shared-scheduler'
  [void][IO.Directory]::CreateDirectory($concurrentHome)
  $modulePath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-news.ps1')).Replace("'","''")
  $childCode=". '"+$modulePath+"'; function Start-WhaleNewsRefresh {param([string]`$PetHome) return `$false}; [void](Invoke-WhaleNewsTick -PetHome '"+$concurrentHome.Replace("'","''")+"' -Preferences @{newsEnabled=`$true;newsTopics=@('ai')} -Now '"+$time.ToString('o')+"')"
  $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
  $scheduleMutex=New-Object Threading.Mutex($true,(Get-PetMutexName 'NewsSchedule' $concurrentHome))
  try {
    $child=[Diagnostics.Process]::Start($info)
    try {if(-not $child.WaitForExit(15000)){$child.Kill();throw '共享调度测试未能非阻塞退出'};Assert ($child.ExitCode -eq 0) '共享新闻调度繁忙时另一个进程快速退出'} finally {$child.Dispose()}
    Assert (-not [IO.File]::Exists((Join-Path $concurrentHome 'news-schedule.json'))) 'UI与后台不能同时写同一份新闻配额或重复推送'
  } finally {$scheduleMutex.ReleaseMutex();$scheduleMutex.Dispose()}
  $child=[Diagnostics.Process]::Start($info)
  try {if(-not $child.WaitForExit(15000)){$child.Kill();throw '共享调度测试退出超时'};Assert ($child.ExitCode -eq 0) '共享新闻调度锁释放后可继续工作'} finally {$child.Dispose()}
  Assert ([IO.File]::Exists((Join-Path $concurrentHome 'news-schedule.json'))) '调度锁不会永久阻止之后的新闻计划'
  Write-Output ('News checks passed: ' + $script:passed)
} finally {
  # Only delete the unique test directory created above, beneath this workspace's .diag.
  $resolved = [IO.Path]::GetFullPath($testHome)
  $tempRoot = $testRoot.TrimEnd('\') + '\'
  if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('whale-news-test-')) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
