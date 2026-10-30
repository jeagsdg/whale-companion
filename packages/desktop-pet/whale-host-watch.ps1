param([string]$PetHome=$PSScriptRoot,[switch]$Once)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'whale-startup.ps1')){
  . (Join-Path $PSScriptRoot 'whale-startup.ps1')
  $PetHome=Resolve-PetPhysicalHome $PetHome
}
$nativeWatch=Join-Path $PSScriptRoot 'whale-host-watch.exe'
if(-not $Once -and (Test-Path -LiteralPath $nativeWatch)){
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName=$nativeWatch;$start.Arguments='--pet-home "'+$PetHome+'"'
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true
  $nativeProcess=[Diagnostics.Process]::Start($start);$nativeProcess.Dispose()
  exit 0
}
. (Join-Path $PSScriptRoot 'whale-pet-common.ps1')
. (Join-Path $PSScriptRoot 'whale-host-lifecycle.ps1')
$created=$false
$mutex=New-Object Threading.Mutex($true,(Get-PetMutexName 'HostWatch' $PetHome),[ref]$created)
if(-not $created){$mutex.Dispose();exit 0}
$statePath=Join-Path $PetHome 'host-lifecycle.json'
$alivePath=Join-Path $PetHome 'host-watch-alive.json'
$state=Get-PetHostLifecycleState (Read-PetJson $statePath)
$heartbeatAt=0.0
$lastError='';$errorAt=0.0
try {
  do {
    try {
      $now=Get-PetUtcMs
      if($now-$heartbeatAt -ge 10000){Write-PetJson $alivePath @{pid=$PID;at=$now};$heartbeatAt=$now}
      $prefs=Read-PetJson (Join-Path $PetHome 'pet-preferences.json')
      if($prefs.host -eq 'dsh'){break}
      $enabled=($prefs.autoWakeOnHostStart -ne $false -and [string]$prefs.autoWakeOnHostStart -cne 'false')
      $hosts=@(Get-PetDesktopHosts)
      $control=Read-PetJson (Join-Path $PetHome 'control.json')
      $before=ConvertTo-Json -InputObject $state -Compress
      $action=Get-PetHostLifecycleAction $state $hosts $enabled ([bool]$control.stopped) (Test-PetRuntimeHealthy $PetHome) $now
      if($before -cne (ConvertTo-Json -InputObject $state -Compress)){Write-PetJson $statePath $state}
      if($action -ne 'none') {
        $launcher=Join-Path $PetHome 'whale-pet-start.ps1'
        if($action -eq 'wake'){& $launcher -PetHome $PetHome -Auto -HostOpen}
        else{& $launcher -PetHome $PetHome -Auto}
      }
    } catch {
      $message=$_.Exception.Message;$errorNow=Get-PetUtcMs
      if($message -cne $lastError -or $errorNow-$errorAt -ge 60000){
        try{
          $log=Join-Path $PetHome 'host-watch.log'
          if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 65536){[IO.File]::WriteAllText($log,'')}
          [IO.File]::AppendAllText($log,(Get-Date -Format s)+' '+$message+"`n",(New-Object Text.UTF8Encoding($false)))
        }catch{}
        $lastError=$message;$errorAt=$errorNow
      }
    }
    if(-not $Once){Start-Sleep -Milliseconds 2000}
  } while(-not $Once)
} finally {
  try{[IO.File]::Delete($alivePath)}catch{}
  try{$mutex.ReleaseMutex()}catch{};$mutex.Dispose()
}
