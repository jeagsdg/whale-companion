<# Loopback bridge v2: authenticated writes, independent approvals and acknowledged decisions. #>
param([int]$Port = 19390, [string]$PetHome = $PSScriptRoot,[string]$SessionRoot='')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'whale-pet-common.ps1')
. (Join-Path $PSScriptRoot 'whale-host.ps1')
[void][IO.Directory]::CreateDirectory($PetHome)
$created = $false
$mutex = New-Object Threading.Mutex($true, ('Local\DshWhalePet.Bridge.' + $Port), [ref]$created)
if (-not $created) { $mutex.Dispose(); exit 0 }
$utf8 = New-Object Text.UTF8Encoding($false)
$crlf = "`r`n"
$token = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
$stateFile = Join-Path $PetHome 'state.json'
$bridgeAliveFile = Join-Path $PetHome 'bridge-alive.json'
$queueFile = Join-Path $PetHome 'approvals.json'
$script:approvals = @((Read-PetJson $queueFile) | Where-Object { $_ -and $_.clientId -and $_.id -and $_.expiresAt })
$script:baseState = Read-PetJson $stateFile
if (-not $script:baseState) { $script:baseState = @{ pose = 'idle'; line = ''; sid = ''; note = '' } }
function Save-Queue { Write-PetJson $queueFile @($script:approvals) }
function Publish-State {
  $active = $null
  if ($script:approvals.Count -gt 0) { $active = $script:approvals[0] }
  $sid = if ($active) { [string]$active.sessionId } else { [string]$script:baseState.sid }
  # A restart must not make a cached Codex attention event look newly received.
  $stamp = if ($script:baseState.host -eq 'codex' -and $script:baseState.at) { [double]$script:baseState.at } else { Get-PetUtcMs }
  Write-PetJson $stateFile @{ protocol = 2; host = [string]$script:baseState.host; kind = [string]$script:baseState.kind; activity=[string]$script:baseState.activity; noticeId = [string]$script:baseState.noticeId; pose = [string]$script:baseState.pose; line = [string]$script:baseState.line; note = [string]$script:baseState.note; sid = $sid; approval = $active; approvalCount = $script:approvals.Count; at = $stamp }
}
function Pump-CodexEvents {
  $prefs = Read-PetJson (Join-Path $PetHome 'pet-preferences.json')
  if ($prefs.host -ne 'codex') { return }
  $folder = Join-Path $PetHome 'host-events'
  if (-not (Test-Path -LiteralPath $folder)) { return }
  $now = Get-PetUtcMs
  $changed = $false
  foreach ($file in Get-ChildItem -LiteralPath $folder -File -Filter '*.json' | Sort-Object Name | Select-Object -First 200) {
    try {
      if ($file.Length -gt 16384) { continue }
      $event = Read-PetJson $file.FullName
      $stamp = 0.0
      if (-not $event -or -not [double]::TryParse([string]$event.at,[ref]$stamp) -or [double]::IsNaN($stamp) -or [double]::IsInfinity($stamp)) { continue }
      if ($event.host -eq 'codex' -and $event.kind -in @('running','tool','completion','failure','approval','question','idle','interrupted') -and $stamp -ge $now-120000 -and $stamp -le $now+30000) {
      $sid = [string]$event.sid
      if ((-not $sid -or (Test-PetSessionId $sid)) -and ([string]$event.line).Length -le 500 -and ([string]$event.note).Length -le 160 -and ([string]$event.noticeId).Length -le 80) {
        if (-not $script:lastHostAt -or $stamp -ge $script:lastHostAt) {
          $script:lastHostAt = $stamp
          $activity=if([string]$event.activity -in @('read','edit','test','review','research','build','art','work')){[string]$event.activity}else{''}
          $script:baseState = @{host='codex';kind=[string]$event.kind;activity=$activity;noticeId=[string]$event.noticeId;pose=[string]$event.pose;line=[string]$event.line;note=[string]$event.note;sid=$sid;at=$stamp}
          $changed = $true
        }
      }
      }
    } catch {
      [Console]::Error.WriteLine('bridge: ignored unreadable host event')
    } finally {
      try { [IO.File]::Delete($file.FullName) } catch { }
    }
  }
  if ($changed) { Publish-State }
}
function Remove-Approval([string]$ClientId, [string]$Id) {
  $script:approvals = @($script:approvals | Where-Object { -not ($_.clientId -ceq $ClientId -and $_.id -ceq $Id) })
  $path = Get-PetDecisionPath $PetHome $ClientId $Id
  if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
}
function Prune-Queue {
  $oldCount = $script:approvals.Count
  $now = Get-PetUtcMs
  $expired = @($script:approvals | Where-Object { [double]$_.expiresAt -le $now })
  foreach ($item in $expired) { Remove-Approval ([string]$item.clientId) ([string]$item.id) }
  if ($oldCount -ne $script:approvals.Count) { Save-Queue; Publish-State }
}
function Test-Origin([string]$Origin) {
  if ([string]::IsNullOrWhiteSpace($Origin)) { return $true }
  if ($Origin -ceq 'dsh-app://app' -or $Origin -ceq 'dsh-app://localhost') {
    $prefs = Read-PetJson (Join-Path $PetHome 'pet-preferences.json')
    return ($prefs.host -ne 'codex')
  }
  return ($Origin -match '^https?://(127\.0\.0\.1|localhost)(:[0-9]{1,5})?$')
}
function Send-Response($Stream, [int]$Code, $Data, [string]$Origin) {
  $reason = @{200='OK';204='No Content';400='Bad Request';401='Unauthorized';403='Forbidden';404='Not Found';405='Method Not Allowed';413='Payload Too Large';429='Too Many Requests';500='Internal Server Error'}[$Code]
  $body = if ($Code -eq 204) { '' } else { ConvertTo-Json -InputObject $Data -Depth 12 -Compress }
  $bytes = $utf8.GetBytes($body)
  $head = 'HTTP/1.1 ' + $Code + ' ' + $reason + $crlf + 'Content-Type: application/json; charset=utf-8' + $crlf + 'Content-Length: ' + $bytes.Length + $crlf
  if ($Origin -and (Test-Origin $Origin)) { $head += 'Access-Control-Allow-Origin: ' + $Origin + $crlf + 'Vary: Origin' + $crlf }
  $head += 'Access-Control-Allow-Methods: GET, POST, OPTIONS' + $crlf + 'Access-Control-Allow-Headers: content-type, x-whale-token' + $crlf + 'Access-Control-Allow-Private-Network: true' + $crlf + 'Access-Control-Max-Age: 600' + $crlf + 'Cache-Control: no-store' + $crlf + 'Connection: close' + $crlf + $crlf
  $headerBytes = $utf8.GetBytes($head)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($bytes.Length) { $Stream.Write($bytes, 0, $bytes.Length) }
  $Stream.Flush()
}
function Get-Health {
  $alive = Read-PetJson (Join-Path $PetHome 'alive.json')
  $uiAlive = $false
  $stamp=0.0; $processId=0
  if ($alive -and [double]::TryParse([string]$alive.at,[ref]$stamp) -and [int]::TryParse([string]$alive.pid,[ref]$processId)) {
    $age=(Get-PetUtcMs)-$stamp
    if (-not [double]::IsNaN($age) -and $age -ge -30000 -and $age -lt 45000 -and $processId -gt 0) {
      $uiAlive = $null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)
    }
  }
  return @{ ok = $true; protocol = 2; pid = $PID; uiAlive = $uiAlive; homeKey = (Get-PetKey ([IO.Path]::GetFullPath($PetHome).TrimEnd('\').ToLowerInvariant())); at = Get-PetUtcMs }
}
function Drain-RejectedBody($Stream,$Headers) {
  $remaining = 0
  if (-not [int]::TryParse([string]$Headers['content-length'],[ref]$remaining) -or $remaining -lt 1 -or $remaining -gt 65536) { return }
  $buffer = New-Object byte[] 4096
  try {
    while ($remaining -gt 0) {
      $count = $Stream.Read($buffer,0,[Math]::Min($remaining,$buffer.Length))
      if ($count -le 0) { break }
      $remaining -= $count
    }
  } catch { }
}
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
$codexCore=Join-Path $PSScriptRoot 'whale-codex-core.ps1'
if(Test-Path -LiteralPath $codexCore){. $codexCore}
try {
  $listener.Start()
  Prune-Queue; Save-Queue; Publish-State
  while ($true) {
    if (-not $script:pumpAt -or [DateTime]::Now -ge $script:pumpAt) {
      $control = Read-PetJson (Join-Path $PetHome 'control.json')
      if ($control.stopped) { break }
      if(-not $script:bridgeHeartbeatAt -or (Get-PetUtcMs)-$script:bridgeHeartbeatAt -ge 10000){
        $script:bridgeHeartbeatAt=Get-PetUtcMs
        Write-PetJson $bridgeAliveFile @{pid=$PID;at=$script:bridgeHeartbeatAt}
      }
      if(Get-Command Initialize-PetCodexWatch -ErrorAction SilentlyContinue){
        $prefs=Read-PetJson (Join-Path $PetHome 'pet-preferences.json')
        if($prefs.host -eq 'codex'){
          try{if(Initialize-PetCodexWatch $PetHome $SessionRoot){Invoke-PetCodexWatch}}catch{}
        }else{Close-PetCodexWatch}
      }
      Pump-CodexEvents; Prune-Queue
      $script:pumpAt = [DateTime]::Now.AddSeconds(1)
    }
    if (-not $listener.Pending()) { [void]$listener.Server.Poll(250000,[Net.Sockets.SelectMode]::SelectRead); continue }
    $client = $listener.AcceptTcpClient()
    $stream = $null
    try {
      $client.ReceiveTimeout = 1500; $client.SendTimeout = 1500
      $stream = $client.GetStream()
      # Read bytes until CRLFCRLF. Content-Length is bytes, never decoded characters.
      $header = New-Object Collections.Generic.List[byte]
      $complete = $false
      while ($header.Count -lt 16384) {
        $b = $stream.ReadByte()
        if ($b -lt 0) { break }
        $header.Add([byte]$b)
        $c = $header.Count
        if ($c -ge 4 -and $header[$c-4] -eq 13 -and $header[$c-3] -eq 10 -and $header[$c-2] -eq 13 -and $header[$c-1] -eq 10) { $complete = $true; break }
      }
      if (-not $complete) { Send-Response $stream 400 @{error='invalid headers'} ''; continue }
      $lines = [Text.Encoding]::ASCII.GetString($header.ToArray()) -split "`r`n"
      $parts = $lines[0] -split ' '
      if ($parts.Count -ne 3) { Send-Response $stream 400 @{error='invalid request'} ''; continue }
      $method = $parts[0]; $target = $parts[1]; $headers = @{}
      foreach ($line in $lines | Select-Object -Skip 1) {
        $colon = $line.IndexOf(':')
        if ($colon -gt 0) { $headers[$line.Substring(0,$colon).Trim().ToLowerInvariant()] = $line.Substring($colon+1).Trim() }
      }
      $origin = [string]$headers['origin']
      $validHost = $headers['host'] -in @(('127.0.0.1:' + $Port), ('localhost:' + $Port))
      if (-not $validHost -or -not (Test-Origin $origin)) { Drain-RejectedBody $stream $headers; Send-Response $stream 403 @{error='untrusted caller'} ''; continue }
      $uri = New-Object Uri(('http://127.0.0.1:' + $Port + $target))
      $path = $uri.AbsolutePath
      if ($path -notin @('/ping','/session','/state','/decision','/decision/ack','/approval/cancel','/show')) { Send-Response $stream 404 @{error='not found'} $origin; continue }
      if ($method -eq 'OPTIONS') { Send-Response $stream 204 $null $origin; continue }
      if ($path -eq '/ping' -or $path -eq '/session') {
        if ($method -ne 'GET') { Send-Response $stream 405 @{error='GET required'} $origin; continue }
        $health = Get-Health
        if ($path -eq '/session') { $health.token = $token }
        Send-Response $stream 200 $health $origin; continue
      }
      if ($headers['x-whale-token'] -cne $token) { Send-Response $stream 401 @{error='session required'} $origin; continue }
      if (($path -eq '/decision' -and $method -ne 'GET') -or ($path -ne '/decision' -and $method -ne 'POST')) { Send-Response $stream 405 @{error='method not allowed'} $origin; continue }
      $q = @{}
      foreach ($pair in $uri.Query.TrimStart('?') -split '&') {
        if (-not $pair) { continue }
        $kv = $pair -split '=',2
        $q[[Uri]::UnescapeDataString($kv[0])] = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString(($kv[1] -replace '\+',' ')) } else { '' }
      }
      $payload = $null
      if ($method -eq 'POST') {
        $length = 0
        if (-not [int]::TryParse([string]$headers['content-length'], [ref]$length) -or $length -lt 1) { Send-Response $stream 400 @{error='content-length required'} $origin; continue }
        if ($length -gt 65536) { Send-Response $stream 413 @{error='body too large'} $origin; continue }
        $body = New-Object byte[] $length
        $read = 0
        while ($read -lt $length) { $n = $stream.Read($body,$read,$length-$read); if ($n -le 0) { throw 'incomplete body' }; $read += $n }
        try { $payload = $utf8.GetString($body) | ConvertFrom-Json } catch { Send-Response $stream 400 @{error='invalid JSON'} $origin; continue }
        if (-not $payload -or $payload -is [array] -or $payload -is [string]) { Send-Response $stream 400 @{error='object required'} $origin; continue }
      }
      Prune-Queue
      if ($path -eq '/state') {
        $clientId = [string]$payload.clientId
        if (-not $clientId -or $clientId.Length -gt 160) { Send-Response $stream 400 @{error='clientId required'} $origin; continue }
        if ($payload.approval) {
          $ap = $payload.approval
          if (-not $ap.id -or -not $ap.sessionId -or -not $ap.requestId -or [string]$ap.clientId -cne $clientId -or ([string]$ap.id).Length -gt 200) { Send-Response $stream 400 @{error='approval identity required'} $origin; continue }
          $same = @($script:approvals | Where-Object { $_.clientId -ceq $clientId -and $_.id -ceq [string]$ap.id })
          if ($same.Count -eq 0 -and $script:approvals.Count -ge 24) { Send-Response $stream 429 @{error='approval queue full'} $origin; continue }
          $entry = @{id=[string]$ap.id;clientId=$clientId;sessionId=[string]$ap.sessionId;requestId=[string]$ap.requestId;tool=([string]$ap.tool).Substring(0,[Math]::Min(96,([string]$ap.tool).Length));reason=([string]$ap.reason).Substring(0,[Math]::Min(600,([string]$ap.reason).Length));expiresAt=(Get-PetUtcMs)+120000}
          if ($same.Count) {
            if ($same[0].sessionId -cne $entry.sessionId -or $same[0].requestId -cne $entry.requestId) { Send-Response $stream 400 @{error='approval identity changed'} $origin; continue }
            $script:approvals = @($script:approvals | ForEach-Object { if ($_.clientId -ceq $clientId -and $_.id -ceq $entry.id) { $entry } else { $_ } })
          } else { $script:approvals += $entry }
        }
        if ($payload.clearApprovalId) { Remove-Approval $clientId ([string]$payload.clearApprovalId) }
        $script:baseState = @{ pose = [string]$payload.pose; line = [string]$payload.line; sid = [string]$payload.sid; note = [string]$payload.note }
        Save-Queue; Publish-State
        Send-Response $stream 200 @{ok=$true;approvalCount=$script:approvals.Count} $origin
      } elseif ($path -eq '/decision') {
        $clientId = [string]$q['clientId']
        if (-not $clientId) { Send-Response $stream 400 @{error='clientId required'} $origin; continue }
        $folder = Join-Path (Join-Path $PetHome 'decisions') (Get-PetKey $clientId)
        $result = @{}
        if (Test-Path -LiteralPath $folder) {
          foreach ($f in Get-ChildItem -LiteralPath $folder -Filter '*.json' -File | Sort-Object LastWriteTimeUtc) {
            $d = Read-PetJson $f.FullName
            if ($d -and $d.clientId -ceq $clientId -and $d.id -and $d.outcome -in @('allowed-once','rejected')) { $result = $d; break }
          }
        }
        Send-Response $stream 200 $result $origin
      } elseif ($path -eq '/decision/ack' -or $path -eq '/approval/cancel') {
        if (-not $payload.clientId -or -not $payload.id) { Send-Response $stream 400 @{error='identity required'} $origin; continue }
        Remove-Approval ([string]$payload.clientId) ([string]$payload.id)
        Save-Queue; Publish-State
        Send-Response $stream 200 @{ok=$true} $origin
      } elseif ($path -eq '/show') {
        if ($payload.explicit -ne $true) { Send-Response $stream 400 @{error='explicit action required'} $origin; continue }
        Write-PetJson (Join-Path $PetHome 'show.json') @{at=Get-PetUtcMs;explicit=$true}
        Send-Response $stream 200 @{ok=$true} $origin
      }
    } catch {
      [Console]::Error.WriteLine('bridge: ' + $_.Exception.Message)
      if ($stream) { try { Send-Response $stream 500 @{error='request failed'} '' } catch { } }
    } finally { $client.Close() }
  }
} finally {
  try{[IO.File]::Delete($bridgeAliveFile)}catch{}
  if(Get-Command Close-PetCodexWatch -ErrorAction SilentlyContinue){Close-PetCodexWatch}
  $listener.Stop()
  try { $mutex.ReleaseMutex() } catch { }
  $mutex.Dispose()
}
