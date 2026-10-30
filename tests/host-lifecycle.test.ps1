param([string]$TestHome)
$ErrorActionPreference='Stop'
$package=Join-Path $PSScriptRoot '..\packages\desktop-pet'
. (Join-Path $package 'whale-pet-common.ps1')
. (Join-Path $package 'whale-host-lifecycle.ps1')
. (Join-Path $package 'whale-companion.ps1')
. (Join-Path $package 'whale-companion-ui.ps1')
$passed=0
function Assert($value,[string]$name){if(-not $value){throw ('FAIL: '+$name)};$script:passed++}
$hostA='codex:10:638000000000000000';$hostB='codex:10:638000000000000001'
$state=Get-PetHostLifecycleState $null
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $true $false 1000) -eq 'wake') 'new app overrides previous-session stop once'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $true $false 20000) -eq 'none') 'same app respects explicit exit'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $true 21000) -eq 'none') 'hidden healthy pet never gets show request'
Assert ((Get-PetHostLifecycleAction $state @() $true $true $false 22000) -eq 'none') 'host closed does not launch anything'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $true $false 23000) -eq 'wake') 'tray close/reopen of same app wakes once'
Assert ((Get-PetHostLifecycleAction $state @($hostB) $true $true $false 24000) -eq 'wake') 'PID reused with different start time is a new host'
$state=Get-PetHostLifecycleState $null
Assert ((Get-PetHostLifecycleAction $state @($hostA) $false $true $false 1000) -eq 'none') 'disabled preference suppresses auto wake'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $true $false 2000) -eq 'wake') 'explicit re-enable works with app already open'
$state=Get-PetHostLifecycleState $null
[void](Get-PetHostLifecycleAction $state @($hostA,$hostB) $true $false $true 1000)
Assert ((Get-PetHostLifecycleAction $state @($hostB) $true $false $true 2000) -eq 'none') 'closing one of several windows is not an opening'
$state=Get-PetHostLifecycleState $null
[void](Get-PetHostLifecycleAction $state @($hostA) $true $false $false 1000)
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $false 15000) -eq 'none') 'slow startup has grace period'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $false 16000) -eq 'recover') 'crash recovery starts after grace'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $false 20000) -eq 'none') 'recovery has backoff'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $false 46000) -eq 'recover') 'second bounded recovery'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $false 250000) -eq 'none') 'failure loop stops after three total starts'
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $true 260000) -eq 'none') 'one healthy tick cannot reset retry budget'
Assert ($state.attempts -eq 3) 'budget still capped after transient health'
[void](Get-PetHostLifecycleAction $state @($hostA) $true $false $true 291000)
Assert ($state.attempts -eq 0) 'sustained health resets budget'
$state=Get-PetHostLifecycleState @{hostKeys=@($hostA);retryAt=90000000;attempts=0}
Assert ((Get-PetHostLifecycleAction $state @($hostA) $true $false $false 1000) -eq 'recover') 'clock adjustment cannot stall recovery'
$state=Get-PetHostLifecycleState @{hostKeys=@('bad',$hostA);retryAt='NaN';attempts=-4}
Assert ($state.hostKeys.Count -eq 1 -and $state.retryAt -eq 0 -and $state.attempts -eq 0) 'corrupt lifecycle record repaired'
Assert (Test-PetDesktopHost 'C:\Program Files\WindowsApps\OpenAI.Codex_26.1007.2314.0_x64__publisher\app\ChatGPT.exe' 123) 'Store Codex with ChatGPT process name detected'
Assert (-not (Test-PetDesktopHost 'C:\Program Files\WindowsApps\OpenAI.ChatGPT-Desktop_1_x64__publisher\app\ChatGPT.exe' 123)) 'separate ChatGPT app ignored'
Assert (-not (Test-PetDesktopHost 'C:\other\ChatGPT.exe' 123)) 'unrelated named process ignored'
Assert (-not (Test-PetDesktopHost 'C:\Program Files\WindowsApps\OpenAI.Codex_1_x64__publisher\app\ChatGPT.exe' 0)) 'Electron children without main window ignored'
$prefs=Repair-PetPreferences @{quiet='false';walk='true';newsEnabled='false';autoWakeOnHostStart='false'}
Assert (-not $prefs.quiet -and $prefs.walk -and -not $prefs.newsEnabled -and -not $prefs.autoWakeOnHostStart) 'boolean strings repaired honestly'

# Actual file-backed display requests, no visible UI.
[void][IO.Directory]::CreateDirectory($TestHome)
$showFile=Join-Path $TestHome 'show.json';$hiddenFile=Join-Path $TestHome 'hidden.json';$shown=0
function Read-Json($path){Read-PetJson $path}
function Show-Pet{$script:shown++}
function petLog($text){}
foreach($request in @(@{at=(Get-PetUtcMs)-60000;explicit=$true},@{at=Get-PetUtcMs;explicit=$false},@{at='NaN';explicit=$true},@{at=(Get-PetUtcMs)+60000;explicit=$true})){
  Write-PetJson $showFile $request;Process-PetShowRequest
  Assert ($shown -eq 0 -and -not (Test-Path -LiteralPath $showFile)) 'bad or stale display request consumed without showing'
}
$stamp=Get-PetUtcMs;Write-PetJson $hiddenFile @{at=$stamp+1};Write-PetJson $showFile @{at=$stamp;explicit=$true};Process-PetShowRequest
Assert ($shown -eq 0) 'newer user hide wins over older host display request'
[IO.File]::Delete($hiddenFile);Write-PetJson $showFile @{at=Get-PetUtcMs;explicit=$true};Process-PetShowRequest
Assert ($shown -eq 1) 'fresh explicit request shows exactly once'
Process-PetShowRequest;Assert ($shown -eq 1) 'consumed request cannot reappear'
'HOST_LIFECYCLE_PASSED='+$passed
