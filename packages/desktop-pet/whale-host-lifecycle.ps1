# Host-open wake and bounded recovery model. Dot sourcing never launches anything.
function Get-PetHostLifecycleState($Saved) {
  $state = @{ hostKeys=@(); enabled=$true; attempts=0; retryAt=0.0; healthySince=0.0 }
  if ($Saved) {
    $state.hostKeys = @($Saved.hostKeys | Where-Object { $_ -match '^codex:[0-9]+:[0-9]+$' } | Select-Object -First 8)
    if ($Saved.enabled -is [bool]) { $state.enabled=$Saved.enabled }
    $attempts=0; if ([int]::TryParse([string]$Saved.attempts,[ref]$attempts)) { $state.attempts=[Math]::Min(3,[Math]::Max(0,$attempts)) }
    foreach($key in @('retryAt','healthySince')) { $value=0.0; if([double]::TryParse([string]$Saved.$key,[ref]$value) -and -not [double]::IsNaN($value) -and -not [double]::IsInfinity($value)){$state[$key]=$value} }
  }
  return $state
}
function Get-PetHostLifecycleAction([hashtable]$State,[string[]]$Hosts,[bool]$Enabled,[bool]$Stopped,[bool]$Healthy,[double]$Now) {
  $keys=@($Hosts | Sort-Object -Unique | Select-Object -First 8)
  $newKeys=@($keys | Where-Object { $_ -notin $State.hostKeys })
  $opened=($keys.Count -gt 0 -and ($newKeys.Count -gt 0 -or -not $State.enabled))
  $State.hostKeys=$keys; $State.enabled=$Enabled
  if(-not $keys.Count -or -not $Enabled){$State.attempts=0;$State.retryAt=0.0;$State.healthySince=0.0;return 'none'}
  if($opened){$State.attempts=1;$State.retryAt=$Now+15000;$State.healthySince=0.0;return 'wake'}
  if($Stopped){$State.healthySince=0.0;return 'none'}
  if($Healthy){
    if(-not $State.healthySince){$State.healthySince=$Now}
    if($Now-$State.healthySince -ge 30000){$State.attempts=0;$State.retryAt=0.0}
    return 'none'
  }
  $State.healthySince=0.0
  # A clock adjustment cannot defer recovery for hours or days.
  if($State.retryAt -gt $Now+120000){$State.retryAt=$Now}
  if($State.attempts -ge 3 -or $Now -lt $State.retryAt){return 'none'}
  $State.attempts++;$State.retryAt=$Now+@(15000,30000,120000)[$State.attempts-1]
  return 'recover'
}
function Test-PetDesktopHost([string]$Path,[long]$WindowHandle) {
  # Codex's Store build is named ChatGPT.exe. Never match the unrelated ChatGPT app.
  return ($WindowHandle -ne 0 -and $Path -match '(?i)\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\(?:ChatGPT|Codex)\.exe$')
}
function Get-PetDesktopHosts {
  if(-not ('WhalePetHost.NativeProcess' -as [type])) {
    # Query the executable with limited rights; MainModule enumerates all modules
    # and can be slow for a large Electron app or an antivirus-scanned process.
    $native=Join-Path $PSScriptRoot 'whale-host-native.dll'
    if(Test-Path -LiteralPath $native){[void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($native))}
    else{Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'WhaleHostNative.cs')))}
  }
  foreach($process in @(Get-Process -Name ChatGPT,Codex -ErrorAction SilentlyContinue)) {
    try {
      $handle=$process.MainWindowHandle.ToInt64()
      if($handle -eq 0){continue}
      if(Test-PetDesktopHost ([WhalePetHost.NativeProcess]::ImagePath($process.Id)) $handle) {
        'codex:'+ $process.Id + ':' + $process.StartTime.ToUniversalTime().Ticks
      }
    } catch { } finally { $process.Dispose() }
  }
}
function Test-PetRuntimeHealthy([string]$PetHome) {
  $alive=Read-PetJson (Join-Path $PetHome 'alive.json');$stamp=0.0
  if(-not [double]::TryParse([string]$alive.at,[ref]$stamp) -or [double]::IsNaN($stamp) -or [double]::IsInfinity($stamp)){return $false}
  $age=(Get-PetUtcMs)-$stamp
  if($stamp -le 0 -or $age -lt -30000 -or $age -gt 45000){return $false}
  foreach($role in @('UI','Codex','Bridge')) {
    $mutex=$null
    $name=if($role -eq 'Bridge'){'Local\DshWhalePet.Bridge.19390'}else{Get-PetMutexName $role $PetHome}
    try{$mutex=[Threading.Mutex]::OpenExisting($name)}catch{return $false}finally{if($mutex){$mutex.Dispose()}}
  }
  return $true
}
