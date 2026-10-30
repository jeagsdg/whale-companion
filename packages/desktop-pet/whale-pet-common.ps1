# Shared, PowerShell 5.1-compatible file and identity helpers. No startup side effects.
function Get-PetKey([string]$Value) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}
function Get-PetMutexName([string]$Role, [string]$PetHome) {
  $path = [IO.Path]::GetFullPath($PetHome).TrimEnd('\').ToLowerInvariant()
  return ('Local\DshWhalePet.' + $Role + '.' + (Get-PetKey $path).Substring(0, 24))
}
function Get-PetDecisionPath([string]$PetHome, [string]$ClientId, [string]$Id) {
  return (Join-Path (Join-Path (Join-Path $PetHome 'decisions') (Get-PetKey $ClientId)) ((Get-PetKey $Id) + '.json'))
}
function Read-PetJson([string]$Path, [long]$MaxBytes = 1048576) {
  $stream = $null; $reader = $null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    if ($stream.Length -gt $MaxBytes) { return $null }
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($raw)) { return ($raw | ConvertFrom-Json) }
  } catch { return $null }
  finally { if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() } }
}
function Read-PetJsonCached([string]$Path, [hashtable]$Cache) {
  try {
    $info=New-Object IO.FileInfo($Path)
    if(-not $info.Exists){[void]$Cache.Remove($Path);return $null}
    $stamp=$info.LastWriteTimeUtc.Ticks.ToString()+':'+$info.Length
    if($Cache.ContainsKey($Path) -and $Cache[$Path].stamp -ceq $stamp){return $Cache[$Path].value}
    $value=Read-PetJson $Path
    # A temporary sharing/parse failure must not suppress the final event until
    # another writer changes the file. Retry on the next bounded state poll.
    if($null -eq $value){[void]$Cache.Remove($Path);return $null}
    $Cache[$Path]=@{stamp=$stamp;value=$value}
    return $value
  } catch {return $null}
}
function Write-PetJson([string]$Path, $Value) {
  $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
  [void][IO.Directory]::CreateDirectory($parent)
  $temp = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $Value -Depth 12 -Compress), (New-Object Text.UTF8Encoding($false)))
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
      try {
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
        return
      } catch { if ($attempt -ge 3) { throw }; Start-Sleep -Milliseconds 15 }
    }
  } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function Get-PetUtcMs { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
