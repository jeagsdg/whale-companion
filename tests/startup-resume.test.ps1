param([Parameter(Mandatory=$true)][string]$TestHome)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-startup.ps1')
$script:passed=0
function Assert($Value,[string]$Message){if(-not $Value){throw ('FAIL: '+$Message)};$script:passed++}
[void][IO.Directory]::CreateDirectory($TestHome)
$runtimeHome=Resolve-PetPhysicalHome $TestHome
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$validXml=New-PetStartupTaskXml $runtimeHome $identity.Name
$name=Get-PetStartupTaskName $runtimeHome
Assert ($name -match '^CodexWhalePet\.HostWatch\.[A-F0-9]{12}$') 'task name is deterministic for the physical home'
Assert ((Get-PetStartupTaskName ($runtimeHome.ToUpperInvariant()+'\')) -ceq $name) 'case and trailing slash cannot change the task identity'
Assert (Test-PetStartupTaskOwnership $validXml $runtimeHome $identity.Name $identity.User.Value) 'known action and current user accepted'
[xml]$sidXml=$validXml;$sidXml.Task.Principals.Principal.UserId=$identity.User.Value;$sidXml.Task.Triggers.LogonTrigger.UserId=$identity.User.Value
Assert (Test-PetStartupTaskOwnership $sidXml.OuterXml $runtimeHome $identity.Name $identity.User.Value) 'scheduler-normalized current user SID accepted'
[xml]$normalizedXml=$validXml
$normalizedXml.Task.Principals.Principal.UserId=$identity.User.Value
[void]$normalizedXml.Task.Principals.Principal.RemoveChild($normalizedXml.Task.Principals.Principal.SelectSingleNode('*[local-name()="RunLevel"]'))
$enabledNode=$normalizedXml.Task.Triggers.LogonTrigger.SelectSingleNode('*[local-name()="Enabled"]')
if($enabledNode){[void]$normalizedXml.Task.Triggers.LogonTrigger.RemoveChild($enabledNode)}
$enabledNode=$normalizedXml.Task.Settings.SelectSingleNode('*[local-name()="Enabled"]')
if($enabledNode){[void]$normalizedXml.Task.Settings.RemoveChild($enabledNode)}
$triggerUserBefore=[string]$normalizedXml.Task.Triggers.LogonTrigger.UserId
Assert ($triggerUserBefore -ceq $identity.Name) 'normalized logon trigger keeps current user account name'
Assert (Test-PetStartupTaskOwnership $normalizedXml.OuterXml $runtimeHome $identity.Name $identity.User.Value) 'Windows normalization allows principal SID, trigger account name and omitted default RunLevel and Enabled'
foreach($field in @('Command','Arguments','WorkingDirectory')){
  [xml]$changed=$validXml
  $changed.Task.Actions.Exec.$field=if($field -eq 'Arguments'){'--pet-home "C:\another-home"'}else{'C:\another-home'}
  Assert (-not (Test-PetStartupTaskOwnership $changed.OuterXml $runtimeHome $identity.Name $identity.User.Value)) ('wrong '+$field+' rejected')
}
[xml]$changed=$validXml;$changed.Task.Principals.Principal.UserId='another-user'
Assert (-not (Test-PetStartupTaskOwnership $changed.OuterXml $runtimeHome $identity.Name $identity.User.Value)) 'another principal rejected'
[xml]$changed=$validXml;$changed.Task.Principals.Principal.RunLevel='HighestAvailable'
Assert (-not (Test-PetStartupTaskOwnership $changed.OuterXml $runtimeHome $identity.Name $identity.User.Value)) 'unexpected elevation rejected'
[xml]$changed=$validXml;[void]$changed.Task.Actions.AppendChild($changed.Task.Actions.Exec.CloneNode($true))
Assert (-not (Test-PetStartupTaskOwnership $changed.OuterXml $runtimeHome $identity.Name $identity.User.Value)) 'additional action rejected'
Assert (-not (Test-PetStartupTaskOwnership '<broken' $runtimeHome $identity.Name $identity.User.Value)) 'malformed task rejected'
Assert (-not (Test-PetStartupTaskOwnership ('<!DOCTYPE test>'+ $validXml) $runtimeHome $identity.Name $identity.User.Value)) 'DTD rejected'

$registrationPath=Join-Path $runtimeHome 'startup-registration.json'
function Save-Registration($Value){[IO.File]::WriteAllText($registrationPath,($Value|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))}
$script:lookups=0;$script:registrations=0;$script:monitorReady=$false;$script:lookedUpName=''
$script:task=[PSCustomObject]@{Enabled=$true;State=3;Xml=$validXml;runs=0}
$script:task|Add-Member ScriptMethod Run {param($unused);$this.runs++;$this.State=4;$script:monitorReady=$true;return $null}
$script:folder=New-Object PSObject
$script:folder|Add-Member ScriptMethod GetTask {param($taskName);$script:lookups++;$script:lookedUpName=$taskName;return $script:task}
$script:folder|Add-Member ScriptMethod RegisterTask {param($taskName,$xml,$flags,$user,$password,$type,$permissions);$script:registrations++;$script:lookedUpName=$taskName;$script:task.Xml=$xml;return $script:task}
function Get-PetStartupScheduleFolder {return $script:folder}
$actualProbe=(Get-Command Test-PetStartupMonitorReady).ScriptBlock
function Test-PetStartupMonitorReady([string]$PetHome){return $script:monitorReady}
Assert (-not (Resume-PetStartupTask $runtimeHome)) 'missing registration never connects to scheduler'
Assert ($script:lookups -eq 0) 'missing registration performs no task lookup'
Save-Registration @{taskName='Other.Task';petHome=$runtimeHome}
Assert (-not (Resume-PetStartupTask $runtimeHome) -and $script:lookups -eq 0) 'untrusted task name never looked up'
Save-Registration @{taskName=$name;petHome=(Join-Path $runtimeHome 'other')}
Assert (-not (Resume-PetStartupTask $runtimeHome) -and $script:lookups -eq 0) 'another home registration never looked up'
[IO.File]::WriteAllText($registrationPath,('x'*65537))
Assert (-not (Resume-PetStartupTask $runtimeHome)) 'oversized registration ignored'
Save-Registration @{taskName=$name;petHome=$runtimeHome}
$recordBefore=[IO.File]::ReadAllText($registrationPath)
$script:task.Xml=$normalizedXml.OuterXml
Assert (Resume-PetStartupTask $runtimeHome) 'ready owned task restored'
Assert ($script:lookedUpName -ceq $name -and $script:task.runs -eq 1 -and $script:task.State -eq 4) 'only the calculated verified task is run'
Assert ($script:registrations -eq 0 -and [IO.File]::ReadAllText($registrationPath) -ceq $recordBefore) 'resume never registers or rewrites a startup entry'
Assert (Resume-PetStartupTask $runtimeHome) 'already running task remains ready'
Assert ($script:task.runs -eq 1) 'running task is not started twice'
$script:task.Enabled=$false
Assert (-not (Resume-PetStartupTask $runtimeHome) -and $script:task.runs -eq 1) 'disabled task not enabled or run'
$script:task.Enabled=$true;$script:task.Xml=$changed.OuterXml
Assert (-not (Resume-PetStartupTask $runtimeHome) -and $script:task.runs -eq 1) 'tampered actual task never started'
$script:task.Xml=$validXml;$script:task.State=4;$script:monitorReady=$false
$timedOut=$false;try{Wait-PetStartupTaskReady $script:task $runtimeHome 0}catch{$timedOut=$true}
Assert $timedOut 'running state alone cannot let UI race ahead of the native heartbeat'
$script:monitorReady=$true;$script:transientReads=0
$transientTask=New-Object PSObject
$transientTask|Add-Member ScriptProperty State {$script:transientReads++;if($script:transientReads -le 2){return 4}else{return 3}}
$timedOut=$false;try{Wait-PetStartupTaskReady $transientTask $runtimeHome 350}catch{$timedOut=$true}
Assert ($timedOut -and $script:transientReads -ge 3) 'transient Running followed by mutex exit never passes the stability gate'
$script:task.State=3;$script:monitorReady=$false
[IO.File]::WriteAllText((Join-Path $runtimeHome 'whale-host-watch.exe'),'fixture; never executed')
$installedName=Install-PetStartupTask $runtimeHome -StartNow
Assert ($installedName -ceq $name -and $script:registrations -eq 1 -and $script:task.runs -eq 2 -and $script:monitorReady) 'fresh registration waits for task-owned monitor before returning'
$script:task.State=3;$script:monitorReady=$false
[void](Install-PetStartupTask $runtimeHome)
Assert ($script:task.runs -eq 2 -and -not $script:monitorReady) 'registration without StartNow does not start a task'
$alivePath=Join-Path $runtimeHome 'host-watch-alive.json'
foreach($alive in @(@{at='NaN';pid=$PID},@{at=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+60000;pid=$PID},@{at=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();pid=2147483646})){
  [IO.File]::WriteAllText($alivePath,($alive|ConvertTo-Json -Compress))
  Assert (-not (& $actualProbe $runtimeHome)) 'invalid future or ended process cannot satisfy native monitor readiness'
}
'STARTUP_RESUME_PASSED='+$script:passed
