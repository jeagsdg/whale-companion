$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\packages\desktop-pet\whale-startup.ps1')
$physical=Resolve-PetPhysicalHome $PSScriptRoot
if(-not [IO.Directory]::Exists($physical)){throw 'Physical directory helper returned an invalid path'}
$homePath='C:\Pet & Friends\companion'
$xml=[xml](New-PetStartupTaskXml $homePath 'Computer\Alice & Bob')
if($xml.Task.Principals.Principal.UserId -ne 'Computer\Alice & Bob'){throw 'User XML escaping failed'}
if($xml.Task.Actions.Exec.Command -ne ($homePath+'\whale-host-watch.exe')){throw 'Wrong executable'}
if($xml.Task.Actions.Exec.Arguments -ne ('--pet-home "'+$homePath+'"')){throw 'Unsafe path quoting'}
if($xml.Task.Principals.Principal.LogonType -ne 'InteractiveToken' -or $xml.Task.Principals.Principal.RunLevel -ne 'LeastPrivilege'){throw 'Task must run as interactive current user'}
if($xml.Task.Settings.ExecutionTimeLimit -ne 'PT0S'){throw 'Long-lived monitor must not time out after three days'}
if($xml.Task.Settings.MultipleInstancesPolicy -ne 'IgnoreNew'){throw 'Repeated startup must not create duplicate processes'}
if($xml.Task.Settings.DisallowStartIfOnBatteries -ne 'false' -or $xml.Task.Settings.StopIfGoingOnBatteries -ne 'false'){throw 'Laptop battery use must not stop auto wake'}
if($xml.Task.Settings.RestartOnFailure.Count -ne '3' -or $xml.Task.Settings.RestartOnFailure.Interval -ne 'PT1M'){throw 'Recovery must be bounded'}
if($xml.Task.Triggers.LogonTrigger.UserId -ne 'Computer\Alice & Bob'){throw 'Login trigger must be scoped to the current user'}
$rejected=$false;try{New-PetStartupTaskXml "C:\invalid`"path" 'user'|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Quote injection accepted'}
'STARTUP_TASK_PASSED'
