<# Add only this companion's MCP server and optional advisory hooks. Never modify hook trust or permissions. #>
param(
  [string]$PetHome = "$env:LOCALAPPDATA\CodexWhalePet",
  [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
  [string]$NodePath = '',
  [switch]$WithHooks
)
$ErrorActionPreference = 'Stop'
$PetHome = [IO.Path]::GetFullPath($PetHome).TrimEnd('\','/')
if(Test-Path -LiteralPath (Join-Path $PetHome 'whale-startup.ps1')){
  . (Join-Path $PetHome 'whale-startup.ps1')
  $PetHome=Resolve-PetPhysicalHome $PetHome
}
$CodexHome = [IO.Path]::GetFullPath($CodexHome).TrimEnd('\','/')
if ($PetHome -match '["\r\n]' -or $CodexHome -match '["\r\n]') { throw 'Unsupported quote or newline in installation path.' }
if (-not $NodePath) { $NodePath = (Get-Command node.exe -ErrorAction Stop).Source }
$NodePath = [IO.Path]::GetFullPath($NodePath)
$server = Join-Path $PetHome 'whale-mcp.mjs'
$hook = Join-Path $PetHome 'codex-hook.ps1'
if (-not (Test-Path -LiteralPath $server -PathType Leaf)) { throw 'Install the companion before registering Codex integration.' }
if (-not (Test-Path -LiteralPath $NodePath -PathType Leaf)) { throw 'Node.js executable was not found.' }
if ($WithHooks -and -not (Test-Path -LiteralPath $hook -PathType Leaf)) { throw 'Missing Codex hook script.' }
[void][IO.Directory]::CreateDirectory($CodexHome)
$configPath = Join-Path $CodexHome 'config.toml'
$hooksPath = Join-Path $CodexHome 'hooks.json'
$config = if (Test-Path -LiteralPath $configPath) { [IO.File]::ReadAllText($configPath) } else { '' }
$start = '# BEGIN CodexWhalePet managed integration'
$end = '# END CodexWhalePet managed integration'
$pattern = '(?ms)^' + [regex]::Escape($start) + '\r?\n.*?^' + [regex]::Escape($end) + '\r?\n?'
if ($config -match '(?m)^\[mcp_servers\.(?:"?whale_companion"?)\]') {
  if ($config -notmatch $pattern) { throw 'An existing whale_companion server is not owned by this installer. It has been preserved.' }
}
$rest = [regex]::Replace($config, $pattern, '')
if ($rest -match '(?m)^[ \t]*(?:\[\s*mcp_servers[^\r\n]*whale_companion|["'']?whale_companion["'']?\s*=|mcp_servers\.[^\r\n]*whale_companion\s*=)') {
  throw 'An existing whale_companion definition is not owned by this installer. It has been preserved.'
}
function Toml-String([string]$Value) { return (ConvertTo-Json -InputObject $Value -Compress) }
$section = @(
  $start,
  '[mcp_servers.whale_companion]',
  ('command = ' + (Toml-String $NodePath)),
  ('args = [' + (Toml-String $server) + ', "--pet-home", ' + (Toml-String $PetHome) + ']'),
  'startup_timeout_sec = 10',
  'tool_timeout_sec = 10',
  $end
) -join "`r`n"
$newConfig = $rest.TrimEnd("`r","`n") + "`r`n`r`n" + $section + "`r`n"
$hookConfig = $null
if ($WithHooks) {
  $hookConfig = if (Test-Path -LiteralPath $hooksPath) { Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{ hooks = [PSCustomObject]@{} } }
  if ($hookConfig -isnot [PSCustomObject]) { throw 'Existing hooks.json is invalid and has been preserved.' }
  if (-not $hookConfig.PSObject.Properties['hooks']) { $hookConfig | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{}) }
  if ($hookConfig.hooks -isnot [PSCustomObject]) { throw 'Existing hook groups are invalid and have been preserved.' }
  $command = 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $hook + '" -PetHome "' + $PetHome + '"'
  foreach ($event in @('SessionStart','UserPromptSubmit','PermissionRequest','Stop','Interrupt','SessionEnd')) {
    $groups = @()
    if ($hookConfig.hooks.PSObject.Properties[$event]) {
      foreach ($group in @($hookConfig.hooks.$event)) {
        # Replace our handler only, preserving every other handler and matcher.
        $remaining = @($group.hooks | Where-Object { $_.statusMessage -cne 'CodexWhalePet companion event' })
        if ($remaining.Count) { $group.hooks = $remaining; $groups += $group }
      }
    }
    $handler = @{ type='command'; command=$command; commandWindows=$command; timeout=3; statusMessage='CodexWhalePet companion event' }
    if ($event -notin @('Interrupt','SessionEnd')) { $handler['async'] = $true }
    $groups += [PSCustomObject]@{ hooks=@([PSCustomObject]$handler) }
    $hookConfig.hooks | Add-Member -NotePropertyName $event -NotePropertyValue $groups -Force
  }
}
$backup = Join-Path $CodexHome ('backups\whale-companion-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6))
[void][IO.Directory]::CreateDirectory($backup)
foreach ($file in @($configPath,$hooksPath)) { if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination (Join-Path $backup ([IO.Path]::GetFileName($file))) } }
function Save-Text([string]$Path,[string]$Text) {
  $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
  try {
    [IO.File]::WriteAllText($temp,$Text,(New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) } else { [IO.File]::Move($temp,$Path) }
  } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
Save-Text $configPath $newConfig
if ($WithHooks) { Save-Text $hooksPath (ConvertTo-Json -InputObject $hookConfig -Depth 30) }
Write-Host 'Codex 桌宠工具已登记，已有通知与其他设置保持原样。新聊天加载后可使用。'
if ($WithHooks) { Write-Host '任务事件钩子已登记，需在 Codex /hooks 中审阅并信任后才生效；没有修改信任或自动授权设置。' }
Write-Host ('配置备份：' + $backup)
