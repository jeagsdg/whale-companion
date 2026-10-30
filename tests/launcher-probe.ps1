param([string]$PetHome,[string]$Scenario)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'packages\desktop-pet\whale-pet-common.ps1')
[void][IO.Directory]::CreateDirectory($PetHome)
$global:PetTestTrace = Join-Path $PetHome 'trace.json'
Write-PetJson $global:PetTestTrace @()
function global:Start-Process {
  param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru)
  $calls = @((Read-PetJson $global:PetTestTrace) | Where-Object { $_ })
  $calls += @{exe=$FilePath;args=$ArgumentList;style=$WindowStyle}
  Write-PetJson $global:PetTestTrace $calls
}
function global:Invoke-RestMethod {
  param($Uri,$TimeoutSec,$ErrorAction)
  if ($Scenario -eq 'ForeignBridge') { return @{ok=$true;homeKey='another-installation'} }
  return @{ok=$true;homeKey=(Get-PetKey ([IO.Path]::GetFullPath($PetHome).TrimEnd('\').ToLowerInvariant()))}
}
foreach($name in @('whale-pet.ps1','whale-pet-http.ps1')) { [IO.File]::WriteAllText((Join-Path $PetHome $name),'# test placeholder') }
$ui = $null; $bridge = $null; $blocker = $null
try {
  if ($Scenario -eq 'ContendedPanel') {
    $ready = Join-Path $PetHome 'mutex-ready'
    $blocker = Start-Job -ArgumentList (Get-PetMutexName 'Start' $PetHome),$ready -ScriptBlock {
      param($Name,$Ready)
      $lock = New-Object Threading.Mutex($true,$Name)
      try { [IO.File]::WriteAllText($Ready,'ready'); Start-Sleep -Milliseconds 1500 }
      finally { $lock.ReleaseMutex(); $lock.Dispose() }
    }
    $deadline = [DateTime]::Now.AddSeconds(15)
    while (-not [IO.File]::Exists($ready) -and [DateTime]::Now -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if (-not [IO.File]::Exists($ready)) { throw 'Contention fixture did not become ready.' }
  }
  if ($Scenario -in @('Hidden','ManualShow','ForeignBridge','CodexRecovery','HostOpen','HostDisabled','NativeHostOpen','SupportHostOpen','SupportManualShow')) {
    $ui = New-Object Threading.Mutex($true,(Get-PetMutexName 'UI' $PetHome))
    Write-PetJson (Join-Path $PetHome 'hidden.json') @{at=Get-PetUtcMs}
  }
  $bridge = New-Object Threading.Mutex($true,'Local\DshWhalePet.Bridge.19390')
  if ($Scenario -eq 'Stopped') { Write-PetJson (Join-Path $PetHome 'control.json') @{stopped=$true} }
  if ($Scenario -eq 'SupportOnly') { Write-PetJson (Join-Path $PetHome 'control.json') @{stopped=$true} }
  if ($Scenario -eq 'NativeHostOpen') {
    Write-PetJson (Join-Path $PetHome 'control.json') @{stopped=$true}
    Write-PetJson (Join-Path $PetHome 'pet-preferences.json') @{host='codex';autoWakeOnHostStart=$true;displayMode='native'}
  }
  if($Scenario -in @('SupportHostOpen','SupportManualShow')){Write-PetJson (Join-Path $PetHome 'hidden.json') @{at=Get-PetUtcMs;supportOnly=$true}}
  if ($Scenario -in @('HostOpen','HostDisabled')) { Write-PetJson (Join-Path $PetHome 'control.json') @{stopped=$true};Write-PetJson (Join-Path $PetHome 'pet-preferences.json') @{host='codex';autoWakeOnHostStart=($Scenario -ne 'HostDisabled')} }
  if ($Scenario -eq 'CodexRecovery') { Write-PetJson (Join-Path $PetHome 'pet-preferences.json') @{host='codex'}; [IO.File]::WriteAllText((Join-Path $PetHome 'whale-codex.ps1'),'# fixture') }
  $launcher = Join-Path $root 'packages\desktop-pet\whale-pet-start.ps1'
  if ($Scenario -in @('HostOpen','HostDisabled','NativeHostOpen','SupportHostOpen')) { & $launcher -PetHome $PetHome -Auto -HostOpen }
  elseif($Scenario -in @('SupportOnly','ContendedPanel')){ & $launcher -PetHome $PetHome -SupportOnly -OpenPanel tasks }
  elseif ($Scenario -eq 'ColdRepeat') { for($iteration=0;$iteration -lt 10;$iteration++){& $launcher -PetHome $PetHome -Auto} }
  elseif ($Scenario -in @('ManualShow','SupportManualShow')) { & $launcher -PetHome $PetHome -Show }
  else { try { & $launcher -PetHome $PetHome -Auto } catch { if($Scenario -ne 'ForeignBridge'){throw}; Write-PetJson (Join-Path $PetHome 'conflict.json') @{error=$_.Exception.Message} } }
} finally {
  if ($blocker) { $blocker | Wait-Job -Timeout 5 | Out-Null; $blocker | Remove-Job -Force }
  if ($ui) { try {$ui.ReleaseMutex()}catch{}; $ui.Dispose() }
  if ($bridge) { try {$bridge.ReleaseMutex()}catch{}; $bridge.Dispose() }
}
