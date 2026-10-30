<#
  Idempotent Windows / PowerShell 5.1 installer.
  -NoStart -NoStartup installs into a test profile without touching processes or Startup.
  Every replaced directory and profile manifest is backed up before updating.
#>
param(
  [string]$DshHome = "$env:USERPROFILE\.dsh",
  [switch]$NoStart,
  [switch]$NoStartup
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$plugin = Join-Path $root 'packages\dsh-whale-notify'
$pet = Join-Path $root 'packages\desktop-pet'
$DshHome = [IO.Path]::GetFullPath($DshHome)
$profile = Join-Path $DshHome 'profiles\desktop'
$pkgPath = Join-Path $profile 'package.json'
if (-not (Test-Path -LiteralPath $plugin -PathType Container)) { throw ('plugin package not found: ' + $plugin) }
if (-not (Test-Path -LiteralPath $pkgPath -PathType Leaf)) { throw ('desktop profile package.json not found: ' + $pkgPath) }
$store = Join-Path $DshHome 'whale-notify\dsh-whale-notify'
$nm = Join-Path $profile 'node_modules\dsh-whale-notify'
$petHome = Join-Path $DshHome 'whale-pet'
$launcher = Join-Path $petHome 'whale-pet-start.ps1'

function Copy-Tree([string]$Source, [string]$Destination, [string[]]$Extra = @()) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NFL /NDL /NJH /NJS /NP @Extra | Out-Null
  $code = $LASTEXITCODE
  if ($code -ge 8) { throw ('robocopy failed (' + $code + '): ' + $Source + ' -> ' + $Destination) }
}
function Set-JsonProperty($Object, [string]$Name, $Value) {
  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}
function Ensure-JsonObject($Object, [string]$Name) {
  $value = $Object.$Name
  if ($null -eq $value -or $value -isnot [PSCustomObject]) {
    $value = [PSCustomObject]@{}
    Set-JsonProperty $Object $Name $value
  }
  return $value
}

# Parse before touching the installation, including profiles with optional fields absent.
$pkg = Get-Content -LiteralPath $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $pkg -or $pkg -isnot [PSCustomObject]) { throw 'profile package.json must be a JSON object' }
$dependencies = Ensure-JsonObject $pkg 'dependencies'
Set-JsonProperty $dependencies 'dsh-whale-notify' 'file:../../whale-notify/dsh-whale-notify'
$dsh = Ensure-JsonObject $pkg 'dsh'
$dshProfile = Ensure-JsonObject $dsh 'profile'
$bundles = @($dshProfile.bundles | Where-Object { $null -ne $_ })
if ($bundles -notcontains 'dsh-whale-notify') { $bundles += 'dsh-whale-notify' }
Set-JsonProperty $dshProfile 'bundles' $bundles

Write-Host '[1/5] 备份已有程序和用户数据'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$bak = Join-Path $DshHome ('backups\whale-notify-' + $stamp + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force -Path $bak | Out-Null
foreach ($f in @('package.json', 'cordis.patch.yml', 'cordis.yml', 'pnpm-lock.yaml')) {
  $sourceFile = Join-Path $profile $f
  if (Test-Path -LiteralPath $sourceFile) { Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $bak $f) -Force }
}
foreach ($entry in @(@($store, 'plugin-store'), @($nm, 'plugin-profile'), @($petHome, 'whale-pet'))) {
  if (Test-Path -LiteralPath $entry[0] -PathType Container) { Copy-Tree $entry[0] (Join-Path $bak $entry[1]) }
}
Write-Host ('      备份 -> ' + $bak)

# Only restart this installation's UI/bridge. Isolation installs must not stop a real pet.
if (-not $NoStart) {
  $normalizedHome = $petHome.Replace('/', '\').TrimEnd('\') + '\'
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" | Where-Object {
    $command = [string]$_.CommandLine
    $_.ProcessId -ne $PID -and
      $command.Replace('/', '\').IndexOf($normalizedHome, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
      $command -match '(?i)whale-pet(?:-http)?\.ps1(?:"|\s|$)'
  } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Write-Host '[2/5] 更新插件'
Copy-Tree $plugin $store
Copy-Tree $plugin $nm
Write-Host '[3/5] 登记到 profile'
# Write a sibling first so interruption cannot truncate the live manifest.
$tempPkg = $pkgPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($tempPkg, ($pkg | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath $tempPkg -Destination $pkgPath -Force

Write-Host '[4/5] 更新桌宠（保留养成、记忆、位置和自定义台词）'
# Never mirror a runtime directory. Existing JSON belongs to the user; seed defaults only once.
Copy-Tree $pet $petHome @('/XF', '*.json')
Get-ChildItem -LiteralPath $pet -Filter '*.json' -File -Recurse | ForEach-Object {
  $relative = $_.FullName.Substring($pet.Length).TrimStart('\', '/')
  $destination = Join-Path $petHome $relative
  if (-not (Test-Path -LiteralPath $destination)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $destination
  }
}
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw ('pet launcher missing: ' + $launcher) }
# This installer explicitly targets DSH; the Codex installer uses its separate home.
$preferencesPath = Join-Path $petHome 'pet-preferences.json'
$preferences = if (Test-Path -LiteralPath $preferencesPath) { Get-Content -LiteralPath $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{} }
if ($preferences -isnot [PSCustomObject]) { throw 'Pet preferences must contain an object; the original is preserved in the backup.' }
Set-JsonProperty $preferences 'host' 'dsh'
$preferencesTemp = $preferencesPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($preferencesTemp, (ConvertTo-Json -InputObject $preferences -Depth 100), (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath $preferencesTemp -Destination $preferencesPath -Force
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launchArgs = '-NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '" -PetHome "' + $petHome + '"'
if (-not $NoStart) {
  Start-Process -FilePath $powershell -ArgumentList $launchArgs -WindowStyle Hidden -WorkingDirectory $petHome | Out-Null
}

Write-Host '[5/5] 开机自启'
if (-not $NoStartup) {
  $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'WhaleMusumePet.lnk'
  if (Test-Path -LiteralPath $lnk) { Copy-Item -LiteralPath $lnk -Destination (Join-Path $bak 'WhaleMusumePet.lnk') -Force }
  $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
  $shortcut.TargetPath = $powershell
  $shortcut.Arguments = $launchArgs + ' -Auto'
  $shortcut.WorkingDirectory = $petHome
  $shortcut.WindowStyle = 7
  $shortcut.Description = 'Whale Musume desktop pet'
  $shortcut.Save()
}
Write-Host ('完成。用户数据已保留，备份位于：' + $bak)
Write-Host '提示：请重启 DSH 以加载宿主更新；客户端可按 Ctrl+R 刷新一次窗口。'
