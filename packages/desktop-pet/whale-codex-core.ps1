# Incremental Codex reader shared by the bridge and standalone compatibility entry.
function Get-PetRecentSessionFiles {
  if (-not (Test-Path -LiteralPath $SessionRoot)) { return @() }
  $cutoff=[DateTime]::UtcNow.AddHours(-24)
  $files=New-Object 'Collections.Generic.List[IO.FileInfo]'
  # A resumed chat can live in an old date directory. Stream paths across the tree,
  # creating PowerShell-visible FileInfo objects only for recently modified files.
  try {
    foreach($path in [IO.Directory]::EnumerateFiles($SessionRoot,'*.jsonl',[IO.SearchOption]::AllDirectories)){
      if([IO.File]::GetLastWriteTimeUtc($path) -ge $cutoff){$files.Add((New-Object IO.FileInfo($path)))}
    }
  } catch { }
  return @($files|Where-Object {$_.LastWriteTimeUtc -ge $cutoff}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 160)
}
function Discover-Sessions {
  if (-not (Test-Path -LiteralPath $SessionRoot)) { return }
  $files = @(Get-PetRecentSessionFiles)
  if(-not $script:codexIgnored){$script:codexIgnored=@{}}
  if($script:codexIgnored.Count -gt 512){$script:codexIgnored.Clear()}
  $activePaths = @(); $rootCount = 0
  foreach ($file in $files) {
    if ($rootCount -ge 6) { break }
    if ($tracks.ContainsKey($file.FullName)) { $activePaths += $file.FullName; $rootCount++; continue }
    if ($script:codexIgnored[$file.FullName] -eq $file.CreationTimeUtc.Ticks) { continue }
    if ($file.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddHours(-24)) { continue }
    $stream=$null; $reader=$null
    try {
      $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
      $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8)
      $meta=($reader.ReadLine()|ConvertFrom-Json).payload
      if ($meta.source.subagent) { $script:codexIgnored[$file.FullName]=$file.CreationTimeUtc.Ticks; continue }
      $id=[string]$meta.id
      if (-not (Test-PetSessionId $id)) { continue }
      $activePaths += $file.FullName; $rootCount++
      $project=if ($meta.cwd) {[IO.Path]::GetFileName(([string]$meta.cwd).TrimEnd('\','/'))} else {''}
      $offset=if ($Replay -or ($script:watcherStartedAt -and $file.CreationTimeUtc -ge $script:watcherStartedAt)) {0} else {$file.Length}
      $tracks[$file.FullName]=@{id=$id;project=$project;offset=[long]$offset;buffer='';decoder=[Text.Encoding]::UTF8.GetDecoder();lastKind='';lastSent=0;seen=[DateTime]::UtcNow}
    } catch { } finally { if ($reader) {$reader.Dispose()} elseif ($stream){$stream.Dispose()} }
  }
  foreach ($path in @($tracks.Keys)) { if ($path -notin $activePaths) {$tracks.Remove($path)} }
}
function Read-SessionChanges {
  if(-not $script:codexReadBuffer){$script:codexReadBuffer=New-Object byte[] 262144;$script:codexReadChars=New-Object char[] ([Text.Encoding]::UTF8.GetMaxCharCount(262144))}
  foreach ($path in @($tracks.Keys)) {
    $track=$tracks[$path];$stream=$null
    try {
      $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
      if ($stream.Length -lt $track.offset) {$track.offset=0;$track.buffer='';$track.decoder.Reset()}
      if ($stream.Length -eq $track.offset) { continue }
      [void]$stream.Seek($track.offset,[IO.SeekOrigin]::Begin)
      $buffer=$script:codexReadBuffer
      $count=$stream.Read($buffer,0,$buffer.Length)
      $track.offset += $count
      if ($count -eq 0) {continue}
      $track.seen=[DateTime]::UtcNow
      $chars=$script:codexReadChars
      $n=$track.decoder.GetChars($buffer,0,$count,$chars,0,$false)
      $track.buffer += New-Object string($chars,0,$n)
      $rows=$track.buffer -split "`n"
      $track.buffer=$rows[-1]
      if ($track.buffer.Length -gt 1048576) {$track.buffer=''}
      for ($i=0;$i -lt $rows.Length-1;$i++) {
        if ($rows[$i].Length -gt 1048576 -or -not $rows[$i].Trim()) {continue}
        if($rows[$i] -notmatch '"type"\s*:\s*"(?:task_started|task_complete|turn_aborted|task_failed|function_call|custom_tool_call)"'){continue}
        try {$record=$rows[$i]|ConvertFrom-Json} catch {continue}
        $event=Convert-PetRolloutEvent $record $track.id $track.project
        if (-not $event) {continue}
        $now=Get-PetUtcMs
        if ($event.kind -eq 'tool' -and $track.lastKind -eq 'tool' -and ($now-$track.lastSent -lt 10000 -or ($track.lastActivity -eq $event.activity -and $now-$track.lastSent -lt 45000))) {continue}
        Send-PetHostEvent $PetHome $event
        $track.lastKind=$event.kind;$track.lastSent=$now;$track.lastActivity=[string]$event.activity
      }
    } catch { } finally {if($stream){$stream.Dispose()}}
  }
}
function Initialize-PetCodexWatch([string]$PetDirectory,[string]$Root='', [bool]$ReplayMode=$false){
  if($script:codexReaderMutex){return $true}
  $created=$false
  $mutex=New-Object Threading.Mutex($true,(Get-PetMutexName 'Codex' $PetDirectory),[ref]$created)
  if(-not $created){$mutex.Dispose();return $false}
  $script:codexReaderMutex=$mutex
  $script:PetHome=[IO.Path]::GetFullPath($PetDirectory)
  $script:tracks=@{};$script:codexIgnored=@{};$script:discoverAt=[DateTime]::MinValue;$script:watcherStartedAt=[DateTime]::UtcNow
  $script:Replay=$ReplayMode
  $script:SessionRoot=$Root
  if(-not $script:SessionRoot){$codexDir=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $env:USERPROFILE '.codex'};$script:SessionRoot=Join-Path $codexDir 'sessions'}
  return $true
}
function Invoke-PetCodexWatch {
  if(-not $script:codexReaderMutex){return}
  if([DateTime]::Now -ge $script:discoverAt){Discover-Sessions;$script:discoverAt=[DateTime]::Now.AddSeconds(20)}
  Read-SessionChanges
}
function Close-PetCodexWatch {
  if($script:codexReaderMutex){try{$script:codexReaderMutex.ReleaseMutex()}catch{};$script:codexReaderMutex.Dispose();$script:codexReaderMutex=$null}
  $script:tracks=@{}
  $script:codexIgnored=@{}
  $script:codexReadBuffer=$null;$script:codexReadChars=$null
}
