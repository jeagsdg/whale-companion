param([string]$PetHome = $PSScriptRoot, [switch]$Auto, [switch]$Show, [switch]$HostOpen,
  [switch]$SupportOnly, [ValidateSet('','tasks','focus','settings','news','diagnostics')][string]$OpenPanel = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'whale-pet-common.ps1')
$PetHome = [IO.Path]::GetFullPath($PetHome)
[void][IO.Directory]::CreateDirectory($PetHome)
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'whale-startup.ps1')){
  . (Join-Path $PSScriptRoot 'whale-startup.ps1')
  $PetHome=Resolve-PetPhysicalHome $PetHome
}
$created = $false
$startMutex = New-Object Threading.Mutex($true, (Get-PetMutexName 'Start' $PetHome), [ref]$created)
if (-not $created) {
  # Background probes can leave immediately; an explicit panel request must not
  # disappear just because another launcher is still bringing up the service.
  if (-not $OpenPanel) { $startMutex.Dispose(); exit 0 }
  $acquired = $false
  try { $acquired = $startMutex.WaitOne(10000) }
  catch [Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { $startMutex.Dispose(); throw 'Another companion launch is still running. Please try opening the panel again.' }
}
try {
  if($SupportOnly -and $Show){throw 'Choose either the hidden service or the visible pet.'}
  $controlFile = Join-Path $PetHome 'control.json'
  $control = Read-PetJson $controlFile
  $prefs = Read-PetJson (Join-Path $PetHome 'pet-preferences.json')
  if ($HostOpen -and ($prefs.host -eq 'dsh' -or $prefs.autoWakeOnHostStart -eq $false -or [string]$prefs.autoWakeOnHostStart -ceq 'false')) { exit 0 }
  if ($Auto -and -not $HostOpen -and $control -and $control.stopped) { exit 0 }
  $pendingPath=Join-Path $PetHome 'launch-pending.json'
  $script:launchPending=@{}
  $savedPending=Read-PetJson $pendingPath
  if($savedPending){foreach($property in $savedPending.PSObject.Properties){$script:launchPending[$property.Name]=$property.Value}}
  function Start-PetPart([string]$Script) {
    $pending=$script:launchPending[$Script]
    if($pending){
      $age=(Get-PetUtcMs)-[double]$pending.at
      if($age -ge 0 -and $age -lt 20000 -and (-not $pending.pid -or (Get-Process -Id ([int]$pending.pid) -ErrorAction SilentlyContinue))){return}
    }
    $path = Join-Path $PetHome $Script
    if (-not (Test-Path -LiteralPath $path)) { throw ('Missing pet component: ' + $path) }
    $args = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $path + '" -PetHome "' + $PetHome + '"'
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
    $script:launchPending[$Script]=@{at=Get-PetUtcMs;pid=$(if($process){$process.Id}else{0})}
    Write-PetJson $pendingPath $script:launchPending
  }
  $uiExists = $false; $uiMutex = $null
  try { $uiMutex = [Threading.Mutex]::OpenExisting((Get-PetMutexName 'UI' $PetHome)); $uiExists = $true } catch { }
  finally { if ($uiMutex) { $uiMutex.Dispose() } }
  $bridgeExists = $false; $bridgeMutex = $null
  try { $bridgeMutex = [Threading.Mutex]::OpenExisting('Local\DshWhalePet.Bridge.19390'); $bridgeExists = $true } catch { }
  finally { if ($bridgeMutex) { $bridgeMutex.Dispose() } }
  if ($bridgeExists) {
    $health = $null
    try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:19390/ping' -TimeoutSec 2 -ErrorAction Stop } catch { }
    $homeKey = Get-PetKey ($PetHome.TrimEnd('\').ToLowerInvariant())
    if (-not $health -or $health.homeKey -cne $homeKey) {
      throw '桌宠端口被另一份安装占用。请先退出旧桌宠，再启动这一份；不会替你打开另一份程序。'
    }
  }
  if (-not $Auto -or $HostOpen) { Write-PetJson $controlFile @{ stopped = $false; at = Get-PetUtcMs } }
  $hidden = Join-Path $PetHome 'hidden.json'
  $hiddenRecord=Read-PetJson $hidden
  $nativeMode=($prefs.displayMode -eq 'native')
  $showRequested=(-not $SupportOnly -and (($Show -and -not $Auto) -or ($HostOpen -and -not $nativeMode -and -not $hiddenRecord.supportOnly)))
  if($SupportOnly){Write-PetJson $hidden @{at=Get-PetUtcMs;supportOnly=$true}}
  if ($showRequested) {
    if ([IO.File]::Exists($hidden)) { [IO.File]::Delete($hidden) }
  }
  if($OpenPanel){
    $commandId=[Guid]::NewGuid().ToString('D')
    Write-PetJson (Join-Path (Join-Path $PetHome 'commands') ($commandId+'.json')) @{id=$commandId;at=Get-PetUtcMs;action='open_panel';panel=$OpenPanel}
  }
  if (-not $bridgeExists) { Start-PetPart 'whale-pet-http.ps1' }
  if (-not $uiExists) { Start-PetPart 'whale-pet.ps1' }
  elseif ($showRequested) { Write-PetJson (Join-Path $PetHome 'show.json') @{ at = Get-PetUtcMs; explicit = $true } }
  if (($prefs.host -eq 'codex' -or -not $prefs.host) -and -not (Test-Path -LiteralPath (Join-Path $PetHome 'whale-codex-core.ps1')) -and (Test-Path -LiteralPath (Join-Path $PetHome 'whale-codex.ps1'))) {
    $codexExists=$false;$codexMutex=$null
    try {$codexMutex=[Threading.Mutex]::OpenExisting((Get-PetMutexName 'Codex' $PetHome));$codexExists=$true} catch {}
    finally {if($codexMutex){$codexMutex.Dispose()}}
    if(-not $codexExists){Start-PetPart 'whale-codex.ps1'}
  }
  if (($prefs.host -eq 'codex' -or -not $prefs.host) -and (Test-Path -LiteralPath (Join-Path $PetHome 'whale-host-watch.ps1'))) {
    $watchExists=$false;$watchMutex=$null
    try{$watchMutex=[Threading.Mutex]::OpenExisting((Get-PetMutexName 'HostWatch' $PetHome));$watchExists=$true}catch{}
    finally{if($watchMutex){$watchMutex.Dispose()}}
    if(-not $watchExists){Start-PetPart 'whale-host-watch.ps1'}
  }
} finally {
  try { $startMutex.ReleaseMutex() } catch { }
  $startMutex.Dispose()
}
