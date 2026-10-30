param([string]$TestHome)
$ErrorActionPreference='Stop'
$package=Join-Path $PSScriptRoot '..\packages\desktop-pet'
. (Join-Path $package 'whale-pet-common.ps1')
. (Join-Path $package 'whale-host-lifecycle.ps1')
[void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $package 'whale-host-watch.exe')))
$a='codex:10:638000000000000000';$b='codex:10:638000000000000001'
$ps=Get-PetHostLifecycleState $null;$native=New-Object WhalePetHost.LifeState;$passed=0
$cases=@(
  @{hosts=@($a);enabled=$true;stopped=$true;healthy=$false;now=1000},
  @{hosts=@($a);enabled=$true;stopped=$true;healthy=$false;now=20000},
  @{hosts=@();enabled=$true;stopped=$true;healthy=$false;now=21000},
  @{hosts=@($a);enabled=$true;stopped=$true;healthy=$false;now=22000},
  @{hosts=@($a);enabled=$true;stopped=$false;healthy=$false;now=37000},
  @{hosts=@($a);enabled=$true;stopped=$false;healthy=$false;now=67000},
  @{hosts=@($a);enabled=$true;stopped=$false;healthy=$false;now=200000},
  @{hosts=@($a);enabled=$true;stopped=$false;healthy=$true;now=210000},
  @{hosts=@($a);enabled=$true;stopped=$false;healthy=$true;now=241000},
  @{hosts=@($a,$b);enabled=$true;stopped=$false;healthy=$true;now=242000},
  @{hosts=@($b);enabled=$true;stopped=$false;healthy=$true;now=243000},
  @{hosts=@($b);enabled=$false;stopped=$true;healthy=$false;now=244000},
  @{hosts=@($b);enabled=$true;stopped=$true;healthy=$false;now=245000}
)
foreach($case in $cases){
  $expected=Get-PetHostLifecycleAction $ps $case.hosts $case.enabled $case.stopped $case.healthy $case.now
  $actual=[WhalePetHost.Watch]::Next($native,[string[]]$case.hosts,$case.enabled,$case.stopped,$case.healthy,$case.now)
  if($actual -ne $expected -or $native.attempts -ne $ps.attempts -or $native.retryAt -ne $ps.retryAt -or $native.healthySince -ne $ps.healthySince){throw 'Native state machine differs from verified lifecycle model'}
  $passed++
}
Write-Host 'NATIVE_MODEL_OK'
$selfPath=[WhalePetHost.NativeProcess]::ImagePath($PID)
if($selfPath -notmatch '(?i)\bpowershell\.exe$'){throw 'Native executable path helper failed'};$passed++
Write-Host 'NATIVE_PATH_OK'
[void][IO.Directory]::CreateDirectory($TestHome)
if([WhalePetHost.NativeProcess]::PhysicalDirectory($TestHome).TrimEnd('\') -ne [IO.Path]::GetFullPath($TestHome).TrimEnd('\')){throw 'Native runtime path canonicalization failed'}
Write-PetJson (Join-Path $TestHome 'pet-preferences.json') @{host='dsh'}
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=Join-Path $package 'whale-host-watch.exe';$start.Arguments='--pet-home "'+$TestHome+'"'
$start.UseShellExecute=$false;$start.CreateNoWindow=$true
$process=[Diagnostics.Process]::Start($start)
Write-Host 'NATIVE_STARTED'
if(-not $process.WaitForExit(15000)){Stop-Process -Id $process.Id -Force;throw 'Native disabled-host exit timeout'}
if($process.ExitCode -ne 0 -or (Test-Path -LiteralPath (Join-Path $TestHome 'host-watch-alive.json'))){throw 'Native disabled-host cleanup failed'};$passed++
# Reproduce the real login/MCP entry: the PowerShell parent exits, while the
# native child must survive, renew its heartbeat and reject a duplicate start.
Write-PetJson (Join-Path $TestHome 'pet-preferences.json') @{host='codex';autoWakeOnHostStart=$false}
$wrapper=New-Object Diagnostics.ProcessStartInfo
$wrapper.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wrapper.Arguments='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $package 'whale-host-watch.ps1')+'" -PetHome "'+$TestHome+'"'
$wrapper.UseShellExecute=$false;$wrapper.CreateNoWindow=$true
$parent=[Diagnostics.Process]::Start($wrapper)
$child=$null
try{
  if(-not $parent.WaitForExit(15000) -or $parent.ExitCode -ne 0){throw 'Startup wrapper failed'}
  $deadline=[DateTime]::UtcNow.AddSeconds(15);$first=$null
  do{$first=Read-PetJson (Join-Path $TestHome 'host-watch-alive.json');if($first.pid){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
  if(-not $first.pid){throw 'Wrapper exited without a live monitor'}
  $child=Get-Process -Id $first.pid -ErrorAction Stop
  $duplicate=[Diagnostics.Process]::Start($start)
  if(-not $duplicate.WaitForExit(5000) -or $duplicate.ExitCode -ne 0){throw 'Duplicate monitor did not exit'}
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  do{Start-Sleep -Milliseconds 200;$next=Read-PetJson (Join-Path $TestHome 'host-watch-alive.json')}while($next.at -le $first.at -and [DateTime]::UtcNow -lt $deadline)
  if($next.pid -ne $first.pid -or $next.at -le $first.at){throw 'Monitor died with its parent or lost heartbeat after duplicate launch'}
  $passed++
  Write-PetJson (Join-Path $TestHome 'pet-preferences.json') @{host='dsh'}
  if(-not $child.WaitForExit(6000)){throw 'Persistent monitor failed to stop after host change'}
  if(Test-Path -LiteralPath (Join-Path $TestHome 'host-watch-alive.json')){throw 'Persistent monitor left a stale heartbeat'}
  $passed++
}finally{
  if($child -and -not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)}
  if(-not $parent.HasExited){$parent.Kill();[void]$parent.WaitForExit(5000)}
  if($child){$child.Dispose()};$parent.Dispose()
}
'NATIVE_WATCH_PASSED='+$passed
