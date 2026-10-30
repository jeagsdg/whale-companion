# News helpers have no startup side effects. The UI only reads small local files;
# network and XML work run in whale-news-worker.ps1, outside the UI thread.
if (-not (Get-Command Read-PetJson -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'whale-pet-common.ps1') }
$script:WhaleNewsModuleHome = $PSScriptRoot

function Get-WhaleNewsSources {
  return @(
    @{ id = 'ithome'; name = 'IT之家'; topics = @('tech'); fetchTopics = @('tech','ai','games'); language = 'zh'; url = 'https://www.ithome.com/rss/'; feedHosts = @('www.ithome.com'); articleHosts = @('www.ithome.com'); offset = '+08:00' },
    @{ id = 'openai'; name = 'OpenAI 官方'; topics = @('ai'); language = 'en'; url = 'https://openai.com/news/rss.xml'; feedHosts = @('openai.com'); articleHosts = @('openai.com','www.openai.com'); offset = '+00:00' },
    @{ id = 'mit-ai'; name = 'MIT News'; topics = @('ai'); language = 'en'; url = 'https://news.mit.edu/rss/topic/artificial-intelligence2'; feedHosts = @('news.mit.edu'); articleHosts = @('news.mit.edu'); offset = '+00:00' },
    @{ id = 'ms-research'; name = 'Microsoft Research 官方'; topics = @('ai','tech'); language = 'en'; url = 'https://www.microsoft.com/en-us/research/feed/'; feedHosts = @('www.microsoft.com'); articleHosts = @('www.microsoft.com'); offset = '+00:00' },
    @{ id = 'google-research'; name = 'Google Research 官方'; topics = @('ai','tech'); language = 'en'; url = 'https://research.google/blog/rss/'; feedHosts = @('research.google'); articleHosts = @('research.google'); offset = '+00:00' },
    @{ id = 'nasa'; name = 'NASA 官方'; topics = @('tech'); language = 'en'; url = 'https://www.nasa.gov/feed/'; feedHosts = @('www.nasa.gov'); articleHosts = @('www.nasa.gov','science.nasa.gov'); offset = '+00:00' },
    @{ id = 'china'; name = '中新网 · 国内'; topics = @('china'); language = 'zh'; url = 'https://www.chinanews.com.cn/rss/china.xml'; feedHosts = @('www.chinanews.com.cn'); articleHosts = @('www.chinanews.com.cn','www.chinanews.com'); offset = '+08:00' },
    @{ id = 'world'; name = '中新网 · 国际'; topics = @('world'); language = 'zh'; url = 'https://www.chinanews.com.cn/rss/world.xml'; feedHosts = @('www.chinanews.com.cn'); articleHosts = @('www.chinanews.com.cn','www.chinanews.com'); offset = '+08:00' },
    @{ id = 'un-zh'; name = '联合国新闻 · 中文'; topics = @('world'); language = 'zh'; url = 'https://news.un.org/feed/subscribe/zh/news/all/rss.xml'; feedHosts = @('news.un.org'); articleHosts = @('news.un.org'); offset = '+00:00' },
    @{ id = 'xbox'; name = 'Xbox Wire 官方'; topics = @('games'); language = 'en'; url = 'https://news.xbox.com/en-us/feed/'; feedHosts = @('news.xbox.com'); articleHosts = @('news.xbox.com'); offset = '+00:00' },
    @{ id = 'playstation'; name = 'PlayStation 官方'; topics = @('games'); language = 'en'; url = 'https://blog.playstation.com/feed/'; feedHosts = @('blog.playstation.com'); articleHosts = @('blog.playstation.com'); offset = '+00:00' }
  )
}

function Get-WhaleNewsSetting($Preferences, [string]$Name, $Default) {
  if ($null -eq $Preferences) { return $Default }
  if ($Preferences -is [Collections.IDictionary]) { if ($Preferences.Contains($Name)) { return $Preferences[$Name] } }
  else { $property = $Preferences.PSObject.Properties[$Name]; if ($property) { return $property.Value } }
  return $Default
}
function Get-WhaleNewsTopics($Preferences) {
  $requested = @(Get-WhaleNewsSetting $Preferences 'newsTopics' @('tech','ai'))
  $result = @()
  foreach ($topic in $requested) {
    $topic = [string]$topic
    if ($topic -eq 'technology') { $topic = 'tech' }
    if ($topic -eq 'gaming') { $topic = 'games' }
    if ($topic -eq 'domestic') { $topic = 'china' }
    if ($topic -in @('tech','ai','china','world','games') -and $result -notcontains $topic) { $result += $topic }
  }
  return $result
}
function Test-WhaleNewsSourceTopics($Source, [string[]]$Topics) {
  $available = if ($Source.fetchTopics) { @($Source.fetchTopics) } else { @($Source.topics) }
  return (@($available | Where-Object { $Topics -contains $_ }).Count -gt 0)
}
function Get-WhaleNewsTime($Now) {
  if ($null -eq $Now) { return [DateTimeOffset]::Now }
  if ($Now -is [DateTimeOffset]) { return $Now }
  if ($Now -is [DateTime]) { return (New-Object DateTimeOffset($Now)) }
  if ($Now -is [long] -or $Now -is [double] -or $Now -is [int]) { return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Now) }
  return [DateTimeOffset]::Parse([string]$Now, [Globalization.CultureInfo]::InvariantCulture)
}
function ConvertTo-WhaleNewsRecord($Value, [hashtable]$Defaults) {
  $record = @{}
  foreach ($key in $Defaults.Keys) { $record[$key] = $Defaults[$key] }
  if ($Value -is [Collections.IDictionary]) { foreach ($key in $Value.Keys) { $record[$key] = $Value[$key] } }
  elseif ($Value) { foreach ($property in $Value.PSObject.Properties) { $record[$property.Name] = $property.Value } }
  return $record
}
function ConvertTo-WhaleNewsText([string]$Text, [int]$Limit = 180) {
  $clean = [Net.WebUtility]::HtmlDecode($Text)
  $clean = [regex]::Replace($clean, '(?is)<(script|style)\b[^>]*>.*?</\1\s*>', ' ')
  $clean = [regex]::Replace($clean, '<[^>]+>', ' ')
  # Decoding once more handles HTML embedded as escaped XML text.
  $clean = [Net.WebUtility]::HtmlDecode($clean)
  $clean = [regex]::Replace($clean, '[\x00-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2066-\u2069]', ' ')
  $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
  if ($clean.Length -gt $Limit) { $clean = $clean.Substring(0, $Limit).TrimEnd() + '…' }
  return $clean
}
function Test-WhaleNewsUrl([string]$Url, [string[]]$AllowedHosts) {
  $uri = $null
  if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $false }
  return ($uri.Scheme -eq 'https' -and $uri.Port -eq 443 -and -not $uri.UserInfo -and $AllowedHosts -contains $uri.DnsSafeHost.ToLowerInvariant())
}
function Get-WhaleNewsArticleUrl([string]$Url, $Source) {
  $uri = $null
  if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return '' }
  if ($uri.Scheme -eq 'http' -and $uri.Port -eq 80 -and -not $uri.UserInfo -and $Source.articleHosts -contains $uri.DnsSafeHost.ToLowerInvariant()) {
    $builder = New-Object UriBuilder($uri); $builder.Scheme = 'https'; $builder.Port = -1; $uri = $builder.Uri
  }
  if (-not (Test-WhaleNewsUrl $uri.AbsoluteUri $Source.articleHosts)) { return '' }
  $builder = New-Object UriBuilder($uri); $builder.Fragment = ''
  $query = @($builder.Query.TrimStart('?').Split('&') | Where-Object { $_ -and $_ -notmatch '^(utm_[^=]*|fbclid|gclid)=' })
  $builder.Query = ($query -join '&')
  return $builder.Uri.AbsoluteUri
}
function Get-WhaleNewsChildText($Node, [string[]]$Names) {
  foreach ($name in $Names) { foreach ($child in $Node.ChildNodes) { if ($child.LocalName -eq $name) { return [string]$child.InnerText } } }
  return ''
}
function Get-WhaleNewsPublishedAt([string]$Raw, $Source, [DateTimeOffset]$Now) {
  if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
  $date = [DateTimeOffset]::MinValue
  $rawDate = $Raw.Trim()
  # Sources sometimes publish an unzoned wall-clock time; use the feed's stated zone.
  if ($rawDate -match '^\d{4}[-/]\d{1,2}[-/]\d{1,2}[ T]\d{1,2}:\d{2}(:\d{2})?$') { $rawDate += [string]$Source.offset }
  $style = [Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [Globalization.DateTimeStyles]::AssumeUniversal
  if (-not [DateTimeOffset]::TryParse($rawDate, [Globalization.CultureInfo]::InvariantCulture, $style, [ref]$date)) { return '' }
  if ($date -gt $Now.AddMinutes(10) -or $date.Year -lt 2000) { return '' }
  return $date.ToUniversalTime().ToString('o')
}
function ConvertFrom-WhaleNewsFeed {
  param([Parameter(Mandatory=$true)][string]$Xml, [Parameter(Mandatory=$true)]$Source, [DateTimeOffset]$Now = [DateTimeOffset]::Now)
  if ($Xml.Length -gt 1048576) { throw 'RSS document is too large.' }
  $settings = New-Object Xml.XmlReaderSettings
  $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver = $null
  $settings.MaxCharactersInDocument = 1048576
  $settings.MaxCharactersFromEntities = 0
  $settings.IgnoreComments = $true
  $reader = $null; $stringReader = $null
  try {
    $stringReader = New-Object IO.StringReader($Xml)
    $reader = [Xml.XmlReader]::Create($stringReader, $settings)
    $doc = New-Object Xml.XmlDocument; $doc.XmlResolver = $null; $doc.Load($reader)
    $root = $doc.DocumentElement.LocalName
    if ($root -notin @('rss','RDF','feed')) { throw 'The response is not an RSS or Atom feed.' }
    $nodes = $doc.SelectNodes('//*[local-name()="item" or local-name()="entry"]')
    $result = @(); $seen = @{}
    foreach ($entry in $nodes) {
      if ($result.Count -ge 40) { break }
      $title = ConvertTo-WhaleNewsText (Get-WhaleNewsChildText $entry @('title')) 160
      $link = Get-WhaleNewsChildText $entry @('link')
      if ($entry.LocalName -eq 'entry') {
        foreach ($child in $entry.ChildNodes) { if ($child.LocalName -eq 'link' -and ($child.GetAttribute('rel') -in @('','alternate'))) { $link = $child.GetAttribute('href'); break } }
      }
      $url = Get-WhaleNewsArticleUrl $link $Source
      if (-not $title -or -not $url) { continue }
      # Commercial promotion is common in technology RSS; leave it out of a companion feed.
      if ($Source.id -eq 'ithome' -and $title -match '红包|优惠券|京东.*(开抢|直降)|淘宝.*(开抢|补贴)|拼多多|限时.*(元|折)|领券|折起|手慢无') { continue }
      $publishedAt = Get-WhaleNewsPublishedAt (Get-WhaleNewsChildText $entry @('pubDate','published','date','updated')) $Source $Now
      $summary = ConvertTo-WhaleNewsText (Get-WhaleNewsChildText $entry @('description','summary')) 160
      $id = Get-PetKey $url
      if ($seen.ContainsKey($id)) { continue }; $seen[$id] = $true
      $topics = @($Source.topics)
      if ($Source.id -eq 'ithome' -and $title -match '(?i)\bAI\b|人工智能|大模型|机器学习|OpenAI|GPT|Claude|DeepSeek|深度求索|通义|文心') { $topics += 'ai' }
      if ($Source.id -eq 'ithome' -and $title -match '(?i)游戏|电竞|任天堂|索尼.*主机|PlayStation|Xbox|Nintendo|\bSteam\b|\bSwitch\b') { $topics += 'games' }
      $result += [pscustomobject]@{ id = $id; title = $title; summary = $summary; url = $url; source = $Source.name; sourceId = $Source.id; topics = $topics; language = $Source.language; publishedAt = $publishedAt; fetchedAt = $Now.ToUniversalTime().ToString('o') }
    }
    return $result
  } finally { if ($reader) { $reader.Dispose() }; if ($stringReader) { $stringReader.Dispose() } }
}

function Get-WhaleNewsFeedXml($Source, [int]$TimeoutMs = 8000) {
  $target = [string]$Source.url; $watch = [Diagnostics.Stopwatch]::StartNew()
  # TLS 1.2 is required for the Windows PowerShell 5.1 worker. Certificate checks stay enabled.
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  for ($redirect = 0; $redirect -le 3; $redirect++) {
    if (-not (Test-WhaleNewsUrl $target $Source.feedHosts)) { throw 'RSS redirect was outside the allowed HTTPS hosts.' }
    $remaining = $TimeoutMs - [int]$watch.ElapsedMilliseconds
    if ($remaining -le 0) { throw 'RSS request timed out.' }
    $request = [Net.HttpWebRequest]::Create($target)
    $request.Method = 'GET'; $request.AllowAutoRedirect = $false
    $request.Timeout = $remaining; $request.ReadWriteTimeout = [Math]::Min(1000, $remaining)
    $request.UserAgent = 'WhaleDesktopCompanion/2.0 RSS'
    $request.Accept = 'application/rss+xml, application/atom+xml, application/xml, text/xml'
    $request.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $response = $null; $stream = $null; $bufferStream = $null
    try {
      $response = $request.GetResponse()
      $status = [int]$response.StatusCode
      if ($status -in @(301,302,303,307,308)) {
        $location = [string]$response.Headers['Location']
        if (-not $location) { throw 'RSS redirect had no destination.' }
        $target = (New-Object Uri((New-Object Uri($target)), $location)).AbsoluteUri
        continue
      }
      if ($status -ne 200) { throw ('RSS returned HTTP ' + $status) }
      if ($response.ContentLength -gt 1048576) { throw 'RSS response is too large.' }
      $stream = $response.GetResponseStream(); $bufferStream = New-Object IO.MemoryStream
      $buffer = New-Object byte[] 8192
      while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        if ($watch.ElapsedMilliseconds -gt $TimeoutMs) { throw 'RSS request timed out.' }
        if ($bufferStream.Length + $count -gt 1048576) { throw 'RSS response is too large.' }
        $bufferStream.Write($buffer, 0, $count)
      }
      $bytes = $bufferStream.ToArray()
      $encoding = [Text.Encoding]::UTF8
      $declaration = [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(256, $bytes.Length))
      $encodingName = ''
      if ($declaration -match 'encoding\s*=\s*["'']([\w-]+)["'']') { $encodingName = $Matches[1] }
      elseif ($response.CharacterSet) { $encodingName = $response.CharacterSet }
      if ($encodingName -and $encodingName -match '^(?i:utf-8|utf8|gb2312|gbk|gb18030|big5|utf-16|utf-16le|utf-16be|iso-8859-1)$') { try { $encoding = [Text.Encoding]::GetEncoding($encodingName) } catch {} }
      return $encoding.GetString($bytes).TrimStart([char]0xFEFF)
    } catch {
      # GetResponse throws for HTTP errors; its response still owns a pooled connection.
      $cause = $_.Exception
      for ($level = 0; $level -lt 8 -and $cause -and $cause -isnot [Net.WebException] -and $cause.InnerException; $level++) { $cause = $cause.InnerException }
      if (-not $response -and $cause -is [Net.WebException] -and $cause.Response) { $response = $cause.Response }
      throw
    } finally { if ($stream) { $stream.Dispose() }; if ($bufferStream) { $bufferStream.Dispose() }; if ($response) { $response.Close() }; $request.Abort() }
  }
  throw 'RSS redirected too many times.'
}

function Merge-WhaleNewsItems([object[]]$Fresh, [object[]]$Previous, [DateTimeOffset]$Now = [DateTimeOffset]::Now) {
  $seen = @{}; $titles = @{}; $result = @(); $sources = @{}
  foreach ($source in (Get-WhaleNewsSources)) { $sources[[string]$source.id] = $source }
  foreach ($item in @($Fresh) + @($Previous)) {
    if (-not $item -or -not $item.id -or -not $item.title -or -not $item.url) { continue }
    $source = $sources[[string]$item.sourceId]
    if (-not $source -or -not (Test-WhaleNewsUrl ([string]$item.url) $source.articleHosts)) { continue }
    $published = [DateTimeOffset]::MinValue
    if ($item.publishedAt -and [DateTimeOffset]::TryParse([string]$item.publishedAt, [ref]$published)) {
      if ($published -gt $Now.AddMinutes(10) -or $published -lt $Now.AddDays(-14)) { continue }
    }
    $titleKey = [regex]::Replace(([string]$item.title).ToLowerInvariant(), '[\s\p{P}]', '')
    if ($seen.ContainsKey([string]$item.id) -or $titles.ContainsKey($titleKey)) { continue }
    $seen[[string]$item.id] = $true; $titles[$titleKey] = $true; $result += $item
  }
  $ordered = @($result | Sort-Object @{Expression={ $date = [DateTimeOffset]::MinValue; if ($_.publishedAt -and [DateTimeOffset]::TryParse([string]$_.publishedAt, [ref]$date)) { $date.UtcTicks } else { 0 } }; Descending=$true})
  # Reserve a few places for each source. A high-volume feed must not evict all
  # low-volume official AI/game announcements before the user can read them.
  $retained = @{}; $counts = @{}
  $sourceCount = @($ordered | Group-Object sourceId).Count
  $reserved = if ($sourceCount) { [Math]::Min(10, [Math]::Max(1, [Math]::Floor(100 / $sourceCount))) } else { 10 }
  foreach ($item in $ordered) {
    $sourceId = [string]$item.sourceId
    if ([int]$counts[$sourceId] -lt $reserved) { $retained[[string]$item.id] = $true; $counts[$sourceId] = [int]$counts[$sourceId] + 1 }
  }
  foreach ($item in $ordered) { if ($retained.Count -ge 100) { break }; $retained[[string]$item.id] = $true }
  return @($ordered | Where-Object { $retained.ContainsKey([string]$_.id) } | Select-Object -First 100)
}

function Get-WhaleNewsFailureCode($ErrorRecord) {
  $exception = $ErrorRecord.Exception
  for ($level = 0; $level -lt 8 -and $exception -and $exception -isnot [Net.WebException] -and $exception -isnot [Xml.XmlException] -and $exception.InnerException; $level++) { $exception = $exception.InnerException }
  if ($exception -is [Net.WebException]) {
    if ($exception.Status -in @([Net.WebExceptionStatus]::Timeout, [Net.WebExceptionStatus]::RequestCanceled)) { return 'timeout' }
    if ($exception.Response) { return 'http-error' }
    return 'network-error'
  }
  if ($exception -is [Xml.XmlException] -or $exception.Message -match 'not an RSS|no usable news|RSS document|RSS response|RSS redirect') { return 'invalid-feed' }
  if ($exception.Message -match 'timed out') { return 'timeout' }
  return 'source-unavailable'
}
function Get-WhaleNewsHttpStatus($ErrorRecord) {
  $cause = $ErrorRecord.Exception
  for ($level = 0; $level -lt 8 -and $cause -and $cause -isnot [Net.WebException] -and $cause.InnerException; $level++) { $cause = $cause.InnerException }
  if ($cause -is [Net.WebException] -and $cause.Response -is [Net.HttpWebResponse]) { return [int]$cause.Response.StatusCode }
  return 0
}
function Get-WhaleNewsFailureMessage([string]$Code, [int]$HttpStatus = 0) {
  switch ($Code) {
    'timeout' { return '连接超时，已保留缓存' }
    'http-error' { return ('来源返回 HTTP ' + $HttpStatus + '，已保留缓存') }
    'network-error' { return '网络或 TLS 连接失败，已保留缓存' }
    'invalid-feed' { return '订阅格式或来源链接已变化，已保留缓存' }
    'refresh-budget' { return '本轮等待已达上限，稍后再试' }
    default { return '来源暂时不可用，已保留缓存' }
  }
}
function Get-WhaleNewsFetchedFeeds {
  param([object[]]$Sources, [int]$BudgetMs = 40000, [scriptblock]$SourceFetcher)
  if (-not $Sources.Count) { return @() }
  $fetchCode = if ($SourceFetcher) { $SourceFetcher.ToString() } else { 'param($source) Get-WhaleNewsFeedXml $source' }
  $worker = {
    param($module, $source, $fetchCode)
    . $module
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
      $xml = & ([scriptblock]::Create($fetchCode)) $source
      return @{ id = [string]$source.id; ok = $true; xml = [string]$xml; durationMs = $timer.ElapsedMilliseconds }
    } catch { return @{ id = [string]$source.id; ok = $false; code = (Get-WhaleNewsFailureCode $_); httpStatus = (Get-WhaleNewsHttpStatus $_); durationMs = $timer.ElapsedMilliseconds } }
  }
  $pool = $null; $jobs = @(); $results = @{}; $watch = [Diagnostics.Stopwatch]::StartNew()
  try {
    $pool = [RunspaceFactory]::CreateRunspacePool(1, 3); $pool.Open()
    foreach ($source in $Sources) {
      $pipe = [PowerShell]::Create(); $pipe.RunspacePool = $pool
      try {
        [void]$pipe.AddScript($worker.ToString()).AddArgument((Join-Path $script:WhaleNewsModuleHome 'whale-news.ps1')).AddArgument($source).AddArgument($fetchCode)
        $jobs += @{ id = [string]$source.id; pipe = $pipe; handle = $pipe.BeginInvoke(); done = $false }
      } catch { $pipe.Dispose(); $results[[string]$source.id] = @{ id = [string]$source.id; ok = $false; code = 'source-unavailable'; durationMs = 0 } }
    }
    while ($watch.ElapsedMilliseconds -lt $BudgetMs) {
      $pending = 0
      foreach ($job in $jobs) {
        if ($job.done) { continue }
        if (-not $job.handle.IsCompleted) { $pending++; continue }
        $job.done = $true
        try {
          $values = @($job.pipe.EndInvoke($job.handle))
          if ($values.Count) { $results[$job.id] = $values[-1] }
          else { $results[$job.id] = @{ id = $job.id; ok = $false; code = 'source-unavailable'; durationMs = $watch.ElapsedMilliseconds } }
        } catch { $results[$job.id] = @{ id = $job.id; ok = $false; code = 'source-unavailable'; durationMs = $watch.ElapsedMilliseconds } }
      }
      if (-not $pending) { break }
      Start-Sleep -Milliseconds 40
    }
  } finally {
    # Only this short-lived worker owns the three runspaces. No permanent pool,
    # job process or timer survives a refresh, including timeout and parse failure.
    foreach ($job in $jobs) {
      if (-not $job.done) {
        try { $job.pipe.Stop() } catch {}
        $results[$job.id] = @{ id = $job.id; ok = $false; code = 'refresh-budget'; durationMs = $watch.ElapsedMilliseconds }
      }
      $job.pipe.Dispose()
    }
    if ($pool) { $pool.Close(); $pool.Dispose() }
  }
  foreach ($source in $Sources) { if ($results.ContainsKey([string]$source.id)) { $results[[string]$source.id] } }
}
function Set-WhaleNewsRefreshStatus {
  param([string]$PetHome, [string]$State, [string]$Code = '', [string]$Message = '', [string]$CacheStatus = '', [long]$DurationMs = 0)
  Write-PetJson (Join-Path $PetHome 'news-refresh-status.json') @{ version = 1; state = $State; code = $Code; message = $Message; cacheStatus = $CacheStatus; at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); durationMs = $DurationMs }
}

function Update-WhaleNewsCache {
  param([string]$PetHome, $Preferences, [DateTimeOffset]$Now = [DateTimeOffset]::Now, [scriptblock]$Fetcher)
  $cachePath = Join-Path $PetHome 'news.json'; $previous = Read-PetJson $cachePath
  $topics = @(Get-WhaleNewsTopics $Preferences)
  $fresh = @(); $statuses = @(); $success = 0; $previousSources = @{}; $fetchedFeeds = @{}
  foreach ($status in @($previous.sources)) { if ($status -and $status.id) { $previousSources[[string]$status.id] = $status } }
  $sources = @(Get-WhaleNewsSources | Where-Object { Test-WhaleNewsSourceTopics $_ $topics })
  if (-not $Fetcher) { foreach ($feed in @(Get-WhaleNewsFetchedFeeds -Sources $sources)) { $fetchedFeeds[[string]$feed.id] = $feed } }
  foreach ($source in $sources) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $oldStatus = $previousSources[[string]$source.id]
    $status = @{ id = $source.id; name = $source.name; ok = $false; state = 'failed'; count = 0; lastCheckedAt = $Now.ToUniversalTime().ToString('o'); lastSuccessAt = [string]$oldStatus.lastSuccessAt; newestPublishedAt = [string]$oldStatus.newestPublishedAt }
    try {
      if ($Fetcher) { $xml = & $Fetcher $source }
      else {
        $feed = $fetchedFeeds[[string]$source.id]
        if (-not $feed -or -not $feed.ok) {
          $status.code = if ($feed.code) { [string]$feed.code } else { 'source-unavailable' }
          $status.httpStatus = [int]$feed.httpStatus; $status.durationMs = [long]$feed.durationMs
          $status.message = Get-WhaleNewsFailureMessage $status.code $status.httpStatus
          $statuses += $status; continue
        }
        $xml = $feed.xml
      }
      $entries = @(ConvertFrom-WhaleNewsFeed -Xml $xml -Source $source -Now $Now)
      if (-not $entries.Count -and $xml -match '(?i)<(?:[\w.-]+:)?(?:item|entry)\b') { throw 'RSS contained no usable news entries.' }
      $matching = @($entries | Where-Object { @($_.topics | Where-Object { $topics -contains $_ }).Count })
      $fresh += $matching; $success++
      $newest = @($entries | Where-Object { $_.publishedAt } | Sort-Object publishedAt -Descending | Select-Object -First 1)
      $status.newestPublishedAt = if ($newest.Count) { [string]$newest[0].publishedAt } else { '' }
      $status.ok = $true; $status.state = if (-not $matching.Count) { 'empty' } elseif (-not $newest.Count) { 'undated' } elseif ([DateTimeOffset]::Parse($newest[0].publishedAt) -lt $Now.AddDays(-14)) { 'stale' } else { 'ok' }
      $status.count = $matching.Count; $status.lastSuccessAt = $Now.ToUniversalTime().ToString('o')
      $status.durationMs = if ($Fetcher) { $watch.ElapsedMilliseconds } else { [long]$feed.durationMs + $watch.ElapsedMilliseconds }
      $statuses += $status
    } catch {
      # A human-readable fixed message avoids storing remote HTML, internal paths or secrets.
      $status.code = Get-WhaleNewsFailureCode $_; $status.httpStatus = Get-WhaleNewsHttpStatus $_
      $status.message = Get-WhaleNewsFailureMessage $status.code $status.httpStatus; $status.durationMs = $watch.ElapsedMilliseconds
      $statuses += $status
    }
  }
  $items = @(Merge-WhaleNewsItems $fresh @($previous.items) $Now)
  $fetchedAt = if ($success -gt 0) { $Now.ToUniversalTime().ToString('o') } elseif ($previous.lastFetchedAt) { $previous.lastFetchedAt } else { '' }
  $cache = @{ version = 1; lastAttemptAt = $Now.ToUniversalTime().ToString('o'); lastFetchedAt = $fetchedAt; status = $(if (-not $statuses.Count) { 'disabled' } elseif ($success -eq 0) { 'offline' } elseif (@($statuses | Where-Object { -not $_.ok -or $_.state -in @('stale','undated') }).Count) { 'partial' } else { 'ok' }); topics = $topics; sources = $statuses; items = $items }
  Write-PetJson $cachePath $cache
  return $cache
}

function Test-WhaleNewsRefreshing {
  param([Parameter(Mandatory=$true)][string]$PetHome)
  $lockPath = Join-Path $PetHome 'news-refresh.lock'
  if (-not [IO.File]::Exists($lockPath)) { return $false }
  if (([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($lockPath)).TotalMinutes -ge 4) { return $false }
  $record = Read-PetJson $lockPath
  $workerId = 0; $workerTicks = [long]0
  # Empty legacy locks and a newly queued launch keep the four-minute grace period.
  if (-not $record -or -not [int]::TryParse([string]$record.pid, [ref]$workerId) -or $workerId -le 0) { return $true }
  $process = $null
  try {
    $process = [Diagnostics.Process]::GetProcessById($workerId)
    if ($process.HasExited) { return $false }
    if ([long]::TryParse([string]$record.startedAtTicks, [ref]$workerTicks) -and $workerTicks -gt 0) { return ($process.StartTime.ToUniversalTime().Ticks -eq $workerTicks) }
    return $true
  } catch { return $false }
  finally { if ($process) { $process.Dispose() } }
}
function Start-WhaleNewsRefresh {
  param([Parameter(Mandatory=$true)][string]$PetHome)
  $lockPath = Join-Path $PetHome 'news-refresh.lock'
  $lock = $null; $ownsLock = $false
  try {
    [void][IO.Directory]::CreateDirectory($PetHome)
    if ([IO.File]::Exists($lockPath)) {
      if (Test-WhaleNewsRefreshing -PetHome $PetHome) { return $false }
      [IO.File]::Delete($lockPath)
    }
    # CreateNew makes concurrent manual/timed refreshes exclusive. Worker deletes it on exit.
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $ownsLock = $true
    $lock.Dispose(); $lock = $null
    Set-WhaleNewsRefreshStatus -PetHome $PetHome -State 'queued'
    $workerPath = Join-Path $script:WhaleNewsModuleHome 'whale-news-worker.ps1'
    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $workerPath + '" -PetHome "' + [IO.Path]::GetFullPath($PetHome) + '"'
    # The worker is neither a pet launcher nor a recovery service: it never starts/shows UI.
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powerShellPath; $startInfo.Arguments = $args
    $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true; $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $process = [Diagnostics.Process]::Start($startInfo)
    if (-not $process) { throw 'News worker did not start.' }
    try {
      # Worker also records this on startup. Either writer describes the same process.
      if (-not $process.HasExited -and [IO.File]::Exists($lockPath)) { Write-PetJson $lockPath @{ pid = $process.Id; startedAtTicks = $process.StartTime.ToUniversalTime().Ticks } }
    } catch {} finally { $process.Dispose() }
    return $true
  } catch {
    if ($lock) { $lock.Dispose() }
    if ($ownsLock) {
      try { [IO.File]::Delete($lockPath) } catch {}
      try { Set-WhaleNewsRefreshStatus -PetHome $PetHome -State 'failed' -Code 'worker-start-failed' -Message '新闻更新未能启动，请稍后重试。' } catch {}
    }
    return $false
  }
}
function Get-WhaleNewsItems {
  param([string]$PetHome)
  $cache = Read-PetJson (Join-Path $PetHome 'news.json')
  if (-not $cache) { return @() }
  # Revalidate local cache before opening a link; cache is data, never executable code.
  return @(Merge-WhaleNewsItems @() @($cache.items) ([DateTimeOffset]::Now))
}
function Get-WhaleNewsDelaySeconds($Preferences) {
  $min = 60; $max = 180; $candidate = 0
  if ([int]::TryParse([string](Get-WhaleNewsSetting $Preferences 'newsMinMinutes' 60), [ref]$candidate)) { $min = [Math]::Min(720, [Math]::Max(60, $candidate)) }
  if ([int]::TryParse([string](Get-WhaleNewsSetting $Preferences 'newsMaxMinutes' 180), [ref]$candidate)) { $max = [Math]::Min(720, [Math]::Max($min, $candidate)) }
  if ($max -lt $min) { $max = $min }
  return (Get-Random -Minimum ($min * 60) -Maximum ($max * 60 + 1))
}
function Select-WhaleNewsForShare {
  param([object[]]$Items, $Preferences, [string[]]$Seen = @(), [DateTimeOffset]$Now = [DateTimeOffset]::Now)
  $topics = @(Get-WhaleNewsTopics $Preferences); $candidates = @()
  foreach ($item in $Items) {
    if (-not $item -or $Seen -contains [string]$item.id -or -not @($item.topics | Where-Object { $topics -contains $_ }).Count) { continue }
    $source = @(Get-WhaleNewsSources | Where-Object { $_.id -eq $item.sourceId } | Select-Object -First 1)
    if (-not $source.Count -or -not (Test-WhaleNewsUrl ([string]$item.url) $source[0].articleHosts)) { continue }
    $published = [DateTimeOffset]::MinValue
    if (-not $item.publishedAt -or -not [DateTimeOffset]::TryParse([string]$item.publishedAt, [ref]$published)) { continue }
    if ($published -gt $Now.AddMinutes(10) -or $published -lt $Now.AddHours(-24)) { continue }
    $candidates += $item
  }
  # Prefer Chinese-language news when available; English originals remain clearly labelled.
  $chinese = @($candidates | Where-Object { $_.language -eq 'zh' })
  if ($chinese.Count) { $candidates = $chinese }
  if ($candidates.Count) { return $candidates[(Get-Random -Minimum 0 -Maximum $candidates.Count)] }
  return $null
}
function Invoke-WhaleNewsTickCore {
  param([string]$PetHome, $Preferences, $Now, [bool]$IsHidden = $false, [bool]$IsAway = $false, [bool]$IsBusy = $false)
  if (-not (Get-WhaleNewsSetting $Preferences 'newsEnabled' $true)) { return $null }
  $time = Get-WhaleNewsTime $Now; $nowMs = $time.ToUnixTimeMilliseconds()
  $schedulePath = Join-Path $PetHome 'news-schedule.json'
  $schedule = ConvertTo-WhaleNewsRecord (Read-PetJson $schedulePath) @{ version = 1; day = ''; sharedToday = 0; seen = @(); nextShareAt = 0; nextRefreshAt = 0; lastRefreshResultAt = 0 }
  $changed = $false
  # A partially edited/old JSON record must not break the UI's per-second timer.
  foreach ($key in @('sharedToday','nextShareAt','nextRefreshAt','lastRefreshResultAt')) {
    $number = [long]0
    if (-not [long]::TryParse([string]$schedule[$key], [ref]$number) -or $number -lt 0) { $schedule[$key] = 0; $changed = $true }
    else { $schedule[$key] = $number }
  }
  $schedule.seen = @(@($schedule.seen) | Where-Object { $_ -is [string] -and $_.Length -le 80 } | Select-Object -Last 200)
  if ($schedule.nextRefreshAt -gt $nowMs + 43200000) { $schedule.nextRefreshAt = 0; $changed = $true }
  if ($schedule.lastRefreshResultAt -gt $nowMs + 600000) { $schedule.lastRefreshResultAt = 0; $changed = $true }
  $refresh = Read-PetJson (Join-Path $PetHome 'news-refresh-status.json')
  $finishedAt = [long]0
  if ($refresh -and $refresh.state -in @('completed','failed') -and [long]::TryParse([string]$refresh.at, [ref]$finishedAt) -and $finishedAt -gt [long]$schedule.lastRefreshResultAt -and $finishedAt -le $nowMs + 600000) {
    # A failed attempt retries in five minutes; partial feeds retry in fifteen.
    # Manual refreshes share this schedule and postpone redundant automatic work.
    $retryMs = if ($refresh.state -eq 'failed' -or $refresh.cacheStatus -eq 'offline') { 300000 } elseif ($refresh.cacheStatus -eq 'partial') { 900000 } else { 3600000 }
    $schedule.nextRefreshAt = $finishedAt + $retryMs
    $schedule.lastRefreshResultAt = $finishedAt; $changed = $true
  }
  # Time/date follows Windows local time (the desktop user's timezone).
  $local = $time.LocalDateTime; $day = $local.ToString('yyyy-MM-dd')
  if ($schedule.day -ne $day) { $schedule.day = $day; $schedule.sharedToday = 0; $changed = $true }
  if (-not $schedule.nextShareAt -or [long]$schedule.nextShareAt -gt $nowMs + 43200000) {
    $schedule.nextShareAt = $nowMs + ((Get-WhaleNewsDelaySeconds $Preferences) * 1000); $changed = $true
  }
  $blocked = ($local.Hour -ge 23 -or $local.Hour -lt 8 -or $IsHidden -or $IsAway -or $IsBusy)
  if ($blocked) { if ($changed) { Write-PetJson $schedulePath $schedule }; return $null }
  if ($nowMs -ge [long]$schedule.nextRefreshAt) {
    $started = Start-WhaleNewsRefresh -PetHome $PetHome
    $schedule.nextRefreshAt = $nowMs + $(if ($started) { 3600000 } else { 60000 }); $changed = $true
  }
  $limit = 3; $parsed = 0
  if ([int]::TryParse([string](Get-WhaleNewsSetting $Preferences 'newsDailyLimit' 3), [ref]$parsed)) { $limit = [Math]::Min(6, [Math]::Max(1, $parsed)) }
  if ($schedule.sharedToday -ge $limit -or $nowMs -lt [long]$schedule.nextShareAt) { if ($changed) { Write-PetJson $schedulePath $schedule }; return $null }
  $cache = Read-PetJson (Join-Path $PetHome 'news.json')
  # Old offline cache can be read manually, but is never pushed as fresh news.
  $fetched = [DateTimeOffset]::MinValue
  $freshCache = ($cache -and $cache.lastFetchedAt -and [DateTimeOffset]::TryParse([string]$cache.lastFetchedAt, [ref]$fetched) -and $fetched -ge $time.AddHours(-24) -and $fetched -le $time.AddMinutes(10))
  $item = if ($freshCache) { Select-WhaleNewsForShare -Items @($cache.items) -Preferences $Preferences -Seen @($schedule.seen) -Now $time } else { $null }
  if (-not $item) {
    # Give an in-flight refresh time to finish; no repeated bubbles or rapid relaunch loops.
    $schedule.nextShareAt = $nowMs + 900000
  } else {
    $schedule.sharedToday = [int]$schedule.sharedToday + 1
    $schedule.seen = @(@($schedule.seen) + [string]$item.id | Select-Object -Last 200)
    $schedule.nextShareAt = $nowMs + ((Get-WhaleNewsDelaySeconds $Preferences) * 1000)
  }
  Write-PetJson $schedulePath $schedule
  return $item
}
function Invoke-WhaleNewsTick {
  param([string]$PetHome, $Preferences, $Now, [bool]$IsHidden = $false, [bool]$IsAway = $false, [bool]$IsBusy = $false)
  if (-not (Get-WhaleNewsSetting $Preferences 'newsEnabled' $true)) { return $null }
  $mutex = New-Object Threading.Mutex($false, (Get-PetMutexName 'NewsSchedule' $PetHome))
  $ownsMutex = $false
  try {
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { return $null }
    return (Invoke-WhaleNewsTickCore -PetHome $PetHome -Preferences $Preferences -Now $Now -IsHidden:$IsHidden -IsAway:$IsAway -IsBusy:$IsBusy)
  } finally { if ($ownsMutex) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
