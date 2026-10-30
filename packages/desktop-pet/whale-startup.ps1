# Current-user, interactive-session startup. No elevation or recurring process launches.
function Resolve-PetPhysicalHome([string]$PetHome) {
  if(-not ('WhalePetHost.NativeProcess' -as [type])){
    [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'whale-host-native.dll')))
  }
  return [WhalePetHost.NativeProcess]::PhysicalDirectory($PetHome)
}

function Get-PetStartupTaskName([string]$PetHome) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($PetHome).TrimEnd('\').ToLowerInvariant())))).Replace('-','').Substring(0,12)}finally{$sha.Dispose()}
  return 'CodexWhalePet.HostWatch.'+$hash
}
function Get-PetStartupScheduleFolder {
  $service=New-Object -ComObject Schedule.Service
  $service.Connect()
  return $service.GetFolder('\')
}
function Read-PetStartupRecord([string]$Path) {
  $stream=$null;$reader=$null
  try{
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    if($stream.Length -gt 65536){return $null}
    $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8)
    $buffer=New-Object char[] 65537;$count=$reader.ReadBlock($buffer,0,$buffer.Length)
    if($count -gt 65536){return $null}
    $text=New-Object string($buffer,0,$count)
    return ($text|ConvertFrom-Json -ErrorAction Stop)
  }catch{return $null}
  finally{if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}}
}
function Test-PetStartupTaskOwnership([string]$TaskXml,[string]$PetHome,[string]$UserName,[string]$UserSid) {
  try{
    if($TaskXml.Length -gt 65536 -or $TaskXml -match '<!DOCTYPE'){return $false}
    $xml=New-Object Xml.XmlDocument;$xml.XmlResolver=$null;$xml.LoadXml($TaskXml)
    $task=$xml.DocumentElement
    if($task.LocalName -cne 'Task'){return $false}
    $ns=New-Object Xml.XmlNamespaceManager($xml.NameTable);$ns.AddNamespace('t',$task.NamespaceURI)
    $actions=@($task.SelectNodes('t:Actions/*',$ns));$principals=@($task.SelectNodes('t:Principals/*',$ns));$triggers=@($task.SelectNodes('t:Triggers/*',$ns))
    if($actions.Count -ne 1 -or $actions[0].LocalName -cne 'Exec' -or $principals.Count -ne 1 -or $triggers.Count -ne 1 -or $triggers[0].LocalName -cne 'LogonTrigger'){return $false}
    $startupHome=[IO.Path]::GetFullPath($PetHome).TrimEnd('\')
    $exe=[IO.Path]::GetFullPath([string]$actions[0].Command)
    $directory=[IO.Path]::GetFullPath([string]$actions[0].WorkingDirectory).TrimEnd('\')
    if(-not $exe.Equals((Join-Path $startupHome 'whale-host-watch.exe'),[StringComparison]::OrdinalIgnoreCase) -or -not $directory.Equals($startupHome,[StringComparison]::OrdinalIgnoreCase) -or [string]$actions[0].Arguments -cne ('--pet-home "'+$startupHome+'"')){return $false}
    $allowedUsers=@($UserName,$UserSid)|Where-Object{$_}
    # Task Scheduler omits its default LeastPrivilege value when serializing a
    # registered task. An explicit elevation request must still be rejected.
    $runLevel=[string]$principals[0].RunLevel
    if([string]$principals[0].UserId -notin $allowedUsers -or [string]$triggers[0].UserId -notin $allowedUsers -or [string]$principals[0].LogonType -cne 'InteractiveToken' -or ($runLevel -and $runLevel -cne 'LeastPrivilege')){return $false}
    return $true
  }catch{return $false}
}
function Test-PetStartupMonitorReady([string]$PetHome) {
  $alive=Read-PetStartupRecord (Join-Path $PetHome 'host-watch-alive.json');$stamp=0.0;$processId=0;$process=$null
  if(-not $alive -or -not [double]::TryParse([string]$alive.at,[ref]$stamp) -or [double]::IsNaN($stamp) -or [double]::IsInfinity($stamp) -or -not [int]::TryParse([string]$alive.pid,[ref]$processId) -or $processId -le 0){return $false}
  $age=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$stamp
  if($age -lt -30000 -or $age -ge 45000){return $false}
  try{
    $process=[Diagnostics.Process]::GetProcessById($processId)
    $expected=[IO.Path]::GetFullPath((Join-Path $PetHome 'whale-host-watch.exe'))
    return (-not $process.HasExited -and $process.MainModule.FileName.Equals($expected,[StringComparison]::OrdinalIgnoreCase))
  }catch{return $false}
  finally{if($process){$process.Dispose()}}
}
function Wait-PetStartupTaskReady($Task,[string]$PetHome,[int]$TimeoutMilliseconds=10000) {
  $watch=[Diagnostics.Stopwatch]::StartNew();$stableSince=-1L
  do{
    if([int]$Task.State -eq 4 -and (Test-PetStartupMonitorReady $PetHome)){
      if($stableSince -lt 0){$stableSince=$watch.ElapsedMilliseconds}
      elseif($watch.ElapsedMilliseconds-$stableSince -ge 750){
        # A competing client-owned monitor can briefly make the task appear to
        # run before its mutex check exits. Require sustained task ownership.
        if([int]$Task.State -eq 4 -and (Test-PetStartupMonitorReady $PetHome)){return}
        $stableSince=-1L
      }
    }else{$stableSince=-1L}
    if($watch.ElapsedMilliseconds -ge $TimeoutMilliseconds){throw 'The independent host monitor did not become ready. The companion launcher was not started.'}
    Start-Sleep -Milliseconds 150
  }while($true)
}
function Resume-PetStartupTask([string]$PetHome) {
  $PetHome=Resolve-PetPhysicalHome $PetHome
  $registration=Read-PetStartupRecord (Join-Path $PetHome 'startup-registration.json')
  if(-not $registration){return $false}
  $name=Get-PetStartupTaskName $PetHome
  try{$registeredHome=[IO.Path]::GetFullPath([string]$registration.petHome).TrimEnd('\')}catch{return $false}
  if(-not $registeredHome.Equals($PetHome.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase) -or [string]$registration.taskName -cne $name){return $false}
  # Never run a name supplied by the record without checking its actual action
  # and current-user principal. No task is registered, enabled or modified here.
  try{$folder=Get-PetStartupScheduleFolder;$task=$folder.GetTask($name)}catch{return $false}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  try{$owned=Test-PetStartupTaskOwnership ([string]$task.Xml) $PetHome $identity.Name $identity.User.Value}finally{$identity.Dispose()}
  if(-not $task.Enabled -or -not $owned){return $false}
  if([int]$task.State -eq 3){[void]$task.Run($null)}
  elseif([int]$task.State -notin @(2,4)){return $false}
  Wait-PetStartupTaskReady $task $PetHome
  return $true
}

function New-PetStartupTaskXml([string]$PetHome,[string]$UserId) {
  $fullHome=[IO.Path]::GetFullPath($PetHome).TrimEnd('\')
  if($fullHome.IndexOfAny([char[]]"`"`r`n") -ge 0){throw 'Invalid pet directory'}
  $exe=[Security.SecurityElement]::Escape((Join-Path $fullHome 'whale-host-watch.exe'))
  $arguments=[Security.SecurityElement]::Escape('--pet-home "'+$fullHome+'"')
  $directory=[Security.SecurityElement]::Escape($fullHome)
  $user=[Security.SecurityElement]::Escape($UserId)
  return @"
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>打开 Codex 时唤醒桌宠；静默监听，不启动 Codex。</Description></RegistrationInfo>
  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>$user</UserId></LogonTrigger></Triggers>
  <Principals><Principal id="PetUser"><UserId>$user</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority><RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure></Settings>
  <Actions Context="PetUser"><Exec><Command>$exe</Command><Arguments>$arguments</Arguments><WorkingDirectory>$directory</WorkingDirectory></Exec></Actions>
</Task>
"@
}

function Install-PetStartupTask([string]$PetHome,[switch]$StartNow) {
  $PetHome=Resolve-PetPhysicalHome $PetHome
  if(-not (Test-Path -LiteralPath (Join-Path $PetHome 'whale-host-watch.exe'))){throw 'Missing native host monitor'}
  $user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
  $name=Get-PetStartupTaskName $PetHome
  $folder=Get-PetStartupScheduleFolder
  $task=$folder.RegisterTask($name,(New-PetStartupTaskXml $PetHome $user),6,$user,$null,3,$null)
  if(-not $task.Enabled){throw 'Host monitor startup task is disabled'}
  if($StartNow){[void]$task.Run($null);Wait-PetStartupTaskReady $task $PetHome}
  return $name
}
