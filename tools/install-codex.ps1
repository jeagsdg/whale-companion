<#
  Install the Codex desktop companion without editing Codex configuration or DSH plugins.
  Windows PowerShell 5.1. -NoStart -NoStartup supports isolated installation tests.
  Legacy data is migrated once, from a whitelist; approvals and lifecycle files are excluded.
#>
param(
  [string]$PetHome = "$env:LOCALAPPDATA\CodexWhalePet",
  [string]$LegacyPetHome = "$env:USERPROFILE\.dsh\whale-pet",
  [switch]$NoStart,
  [switch]$NoStartup
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$source = Join-Path $root 'packages\desktop-pet'
$PetHome = [IO.Path]::GetFullPath($PetHome).TrimEnd('\', '/')
$requestedPetHome=$PetHome
$LegacyPetHome = [IO.Path]::GetFullPath($LegacyPetHome).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw ('Missing desktop companion package: ' + $source) }
if ($PetHome.Equals([IO.Path]::GetFullPath($source).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Install into a separate runtime directory.' }
if ($PetHome.Equals($LegacyPetHome, [StringComparison]::OrdinalIgnoreCase)) { throw 'Choose a separate Codex directory so the legacy installation can remain backed up.' }
if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($PetHome))) { throw 'PetHome cannot be a drive root.' }
$launcher = Join-Path $PetHome 'whale-pet-start.ps1'
$userFiles = @('pet-stats.json', 'pet-memory.json', 'position.json', 'lines.json', 'pet-preferences.json', 'companion-data.json', 'pet-notes.json', 'pet-reminders.json', 'pet-news-preferences.json', 'news-schedule.json', 'news.json', 'news-library.json')

function Copy-Tree([string]$From, [string]$To, [string[]]$Exclude = @()) {
  $fullFrom = [IO.Path]::GetFullPath($From).TrimEnd('\', '/')
  $fullTo = [IO.Path]::GetFullPath($To).TrimEnd('\', '/')
  if ($fullTo.Equals($fullFrom, [StringComparison]::OrdinalIgnoreCase) -or
      $fullTo.StartsWith($fullFrom + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw ('Copy destination cannot be inside its source: ' + $To)
  }
  [void][IO.Directory]::CreateDirectory($To)
  $extra = @()
  if ($Exclude.Count -gt 0) { $extra = @('/XF') + $Exclude }
  & robocopy.exe $From $To /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NFL /NDL /NJH /NJS /NP @extra | Out-Null
  if ($LASTEXITCODE -ge 8) { throw ('Copy failed: ' + $From + ' -> ' + $To + ' (code ' + $LASTEXITCODE + ')') }
}
function Write-Record([string]$Path, $Record) {
  $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
  [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Record -Depth 100), (New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

# Validate defaults before touching the installation. User JSON is backed up as-is.
$defaultPreferences = [PSCustomObject]@{ host = 'codex'; quiet = $true; walk = $false; breakReminders = $false }
$preferencesSource = Join-Path $source 'pet-preferences.json'
if (Test-Path -LiteralPath $preferencesSource -PathType Leaf) {
  $defaultPreferences = Get-Content -LiteralPath $preferencesSource -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($defaultPreferences -isnot [PSCustomObject]) { throw 'Default pet-preferences.json must contain an object.' }
}
# MSIX-packaged Codex redirects LocalAppData writes. Persist the resolved physical
# directory so Windows logon tasks outside Codex see the same files and mutex keys.
if(Test-Path -LiteralPath (Join-Path $source 'whale-startup.ps1')){
  . (Join-Path $source 'whale-startup.ps1')
  [void][IO.Directory]::CreateDirectory($PetHome)
  $PetHome=Resolve-PetPhysicalHome $PetHome
  if($PetHome.Equals([IO.Path]::GetFullPath($source).TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Install into a separate runtime directory.'}
  $launcher=Join-Path $PetHome 'whale-pet-start.ps1'
}
$migrationMarker = Join-Path $PetHome 'codex-migration.json'
$migrateLegacy = (-not (Test-Path -LiteralPath $migrationMarker)) -and (Test-Path -LiteralPath $LegacyPetHome -PathType Container)
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
$backups = $PetHome + '.backups'
$backup = Join-Path $backups $stamp
[void][IO.Directory]::CreateDirectory($backup)
Write-Host '[1/4] 备份程序和用户数据'
if (Test-Path -LiteralPath $PetHome -PathType Container) { Copy-Tree $PetHome (Join-Path $backup 'installed') }
if ($migrateLegacy) { Copy-Tree $LegacyPetHome (Join-Path $backup 'legacy') }
Write-Host ('      备份：' + $backup)

# Scope restarts to this exact runtime; an isolated installation never kills a real pet.
if (-not $NoStart) {
  $normalizedHome = $PetHome.Replace('/', '\') + '\'
  $requestedPrefix=$requestedPetHome.Replace('/','\')+'\'
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='whale-host-watch.exe'" | Where-Object {
    $command = [string]$_.CommandLine
    $_.ProcessId -ne $PID -and
      ($command.Replace('/', '\').IndexOf($normalizedHome, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $command.Replace('/', '\').IndexOf($requestedPrefix,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and
      $command -match '(?i)(?:(?:whale-pet(?:-http|-watchdog)?|whale-codex|whale-host-watch)\.ps1|whale-host-watch\.exe)(?:"|\s|$)'
  } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Write-Host '[2/4] 更新桌宠和表情资源'
# Never mirror or delete a runtime directory. Preserve known user files and unknown data.
Copy-Tree $source $PetHome $userFiles
foreach ($name in $userFiles) {
  $destination = Join-Path $PetHome $name
  if (Test-Path -LiteralPath $destination) { continue }
  $legacyFile = Join-Path $LegacyPetHome $name
  $defaultFile = Join-Path $source $name
  if ($migrateLegacy -and (Test-Path -LiteralPath $legacyFile -PathType Leaf)) {
    Copy-Item -LiteralPath $legacyFile -Destination $destination
  } elseif (Test-Path -LiteralPath $defaultFile -PathType Leaf) {
    Copy-Item -LiteralPath $defaultFile -Destination $destination
  }
}

# Add new preference keys while preserving nicknames, companion names and all existing settings.
$preferencesPath = Join-Path $PetHome 'pet-preferences.json'
$preferences = [PSCustomObject]@{}
if (Test-Path -LiteralPath $preferencesPath) {
  try { $preferences = Get-Content -LiteralPath $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw ('Existing pet-preferences.json is invalid. It is preserved; backup: ' + $backup) }
  if ($preferences -isnot [PSCustomObject]) { throw ('Existing pet-preferences.json must contain an object. Backup: ' + $backup) }
}
foreach ($property in $defaultPreferences.PSObject.Properties) {
  if (-not $preferences.PSObject.Properties[$property.Name]) {
    $preferences | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
  }
}
$preferences | Add-Member -NotePropertyName 'host' -NotePropertyValue 'codex' -Force
Write-Record $preferencesPath $preferences
if (-not (Test-Path -LiteralPath $migrationMarker)) {
  Write-Record $migrationMarker ([PSCustomObject]@{ version = 1; migratedAt = [DateTimeOffset]::UtcNow.ToString('o');
    legacyDataCopied = [bool]$migrateLegacy; legacySource = $LegacyPetHome; backup = $backup })
}
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw ('Missing launcher: ' + $launcher) }

Write-Host '[3/4] 整理旧版并准备启动'
if(-not $NoStart -and (Test-Path -LiteralPath $LegacyPetHome -PathType Container)) {
  $legacyControlPath=Join-Path $LegacyPetHome 'control.json'
  $legacyControl=$null
  try{$legacyControl=Get-Content -LiteralPath $legacyControlPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
  # A stopped old pet must not leave its pre-2.0 bridge holding the new port.
  if($legacyControl.stopped -eq $true) {
    $legacyBackup=Join-Path $backup 'retired-legacy';[void][IO.Directory]::CreateDirectory($legacyBackup)
    $legacyLauncher=Join-Path $LegacyPetHome 'whale-pet-start.ps1'
    $legacyBridge=Join-Path $LegacyPetHome 'whale-pet-http.ps1'
    foreach($file in @($legacyLauncher,$legacyBridge,(Join-Path $LegacyPetHome 'codex-preferred.json'))){if(Test-Path -LiteralPath $file){Copy-Item -LiteralPath $file -Destination (Join-Path $legacyBackup ([IO.Path]::GetFileName($file)))}}
    if(Test-Path -LiteralPath $legacyBridge){
      $oldText=[IO.File]::ReadAllText($legacyBridge)
      if(-not $oldText.Contains('# CodexWhalePet: retired legacy bridge')){
        $tokens=$null;$parseErrors=$null;$tree=[Management.Automation.Language.Parser]::ParseInput($oldText,[ref]$tokens,[ref]$parseErrors)
        if($tree.ParamBlock -and -not $parseErrors){
          $guard=@'

# CodexWhalePet: retired legacy bridge exits when stopped.
try {
  $legacyPetQuitRecord=Get-Content -LiteralPath (Join-Path $PetHome 'control.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($legacyPetQuitRecord.stopped -eq $true){exit 0}
} catch { }

'@
          $offset=$tree.ParamBlock.Extent.EndOffset
          [IO.File]::WriteAllText($legacyBridge,$oldText.Insert($offset,$guard),(New-Object Text.UTF8Encoding($true)))
        }
      }
    }
    $forward=Join-Path $PetHome 'legacy-codex-forward.ps1'
    if((Test-Path -LiteralPath $legacyLauncher) -and (Test-Path -LiteralPath $forward)){
      Write-Record (Join-Path $LegacyPetHome 'codex-preferred.json') @{petHome=$PetHome;version=1}
      Copy-Item -LiteralPath $forward -Destination $legacyLauncher -Force
    }
    $legacyPrefix=$LegacyPetHome.Replace('/','\')+'\'
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'"|Where-Object{
      $_.ProcessId -ne $PID -and ([string]$_.CommandLine).Replace('/','\').IndexOf($legacyPrefix,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine -match '(?i)whale-pet-http\.ps1(?:"|\s|$)'
    }|ForEach-Object{Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
  }
}
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launchArgs = '-NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '" -PetHome "' + $PetHome + '"'

Write-Host '[4/4] 开机自启'
if (-not $NoStartup) {
  $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'CodexWhalePet.lnk'
  if (Test-Path -LiteralPath $shortcutPath) { Copy-Item -LiteralPath $shortcutPath -Destination (Join-Path $backup 'CodexWhalePet.lnk') }
  $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $powershell
  $shortcut.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PetHome 'whale-host-watch.ps1') + '" -PetHome "' + $PetHome + '"'
  if(Test-Path -LiteralPath (Join-Path $PetHome 'whale-host-watch.exe')){
    $shortcut.TargetPath=Join-Path $PetHome 'whale-host-watch.exe'
    $shortcut.Arguments='--pet-home "'+$PetHome+'"'
  }
  $shortcut.WorkingDirectory = $PetHome
  $shortcut.WindowStyle = 7
  $shortcut.Description = '打开 Codex 时自动唤醒桌宠，后台静默监听'
  $shortcut.Save()
  # The login task owns the long-lived monitor, independently of the Codex/MCP
  # child-process lifetime. The shortcut remains a mutex-deduplicated fallback.
  . (Join-Path $PetHome 'whale-startup.ps1')
  $startupTask=Install-PetStartupTask $PetHome -StartNow:(-not $NoStart)
  Write-Record (Join-Path $PetHome 'startup-registration.json') @{taskName=$startupTask;petHome=$PetHome;registeredAt=[DateTimeOffset]::UtcNow.ToString('o')}
} elseif(-not $NoStart -and (Test-Path -LiteralPath (Join-Path $PetHome 'whale-startup.ps1'))) {
  # NoStartup skips registration changes, but an existing verified login task
  # can recover ownership of its monitor after the upgrade stopped the old one.
  . (Join-Path $PetHome 'whale-startup.ps1')
  [void](Resume-PetStartupTask $PetHome)
}
# Establish the task-owned monitor and its heartbeat before any UI launcher can
# acquire the monitor mutex as a child of this installer or the Codex process.
if (-not $NoStart) { Start-Process -FilePath $powershell -ArgumentList $launchArgs -WindowStyle Hidden -WorkingDirectory $PetHome | Out-Null }
Write-Host ('完成。桌宠目录：' + $PetHome)
Write-Host ('备份目录：' + $backup)
Write-Host 'Codex 事件接入由独立配置步骤完成；此安装器只更新桌宠。'
