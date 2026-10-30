param([string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }))
$ErrorActionPreference = 'Stop'
function Get-NativePetFileHash([string]$Path) {
  $stream = $null; $hash = [Security.Cryptography.SHA256]::Create()
  try {
    $stream = [IO.File]::OpenRead($Path)
    return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-', '')
  } finally { if ($stream) { $stream.Dispose() }; $hash.Dispose() }
}
$petId = 'liangwenfeng-whale'
$source = Join-Path $PSScriptRoot $petId
$manifestPath = Join-Path $source 'pet.json'
$sheetPath = Join-Path $source 'spritesheet.webp'
$validation = Get-Content -LiteralPath (Join-Path $source 'validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.id -cne $petId -or $manifest.spriteVersionNumber -ne 2 -or $manifest.spritesheetPath -cne 'spritesheet.webp') {
  throw 'Invalid native pet manifest.'
}
if ($validation.ok -ne $true -or $validation.spriteVersionNumber -ne 2 -or
    $validation.sha256 -cne (Get-NativePetFileHash $sheetPath).ToLowerInvariant()) {
  throw 'The native pet has not passed validation, or its image has changed.'
}
$petsRoot = [IO.Path]::GetFullPath((Join-Path $CodexHome 'pets'))
$destination = Join-Path $petsRoot $petId
[void][IO.Directory]::CreateDirectory($destination)
# Keep an earlier installed character recoverable; installation never touches companion data.
if (Test-Path -LiteralPath (Join-Path $destination 'pet.json')) {
  $backup = Join-Path ([IO.Path]::GetFullPath($CodexHome)) ('pets-backups\' + $petId + '-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
  [void][IO.Directory]::CreateDirectory($backup)
  foreach ($file in @('pet.json', 'spritesheet.webp')) {
    $old = Join-Path $destination $file
    if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination (Join-Path $backup $file) }
  }
}
foreach ($file in @('spritesheet.webp', 'pet.json')) {
  $target = Join-Path $destination $file
  $temporary = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
  try {
    Copy-Item -LiteralPath (Join-Path $source $file) -Destination $temporary
    if (Test-Path -LiteralPath $target) { [IO.File]::Replace($temporary, $target, [System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temporary, $target) }
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
  }
}
$skillSource = Join-Path $PSScriptRoot 'skill\whale-companion\SKILL.md'
$skillTarget = Join-Path $CodexHome 'skills\whale-companion\SKILL.md'
$skillResult = 'unavailable'
$skillBackup = $null
# Append the SHA256 of each released bundled skill before changing its source.
# Only byte-identical known releases can be upgraded without replacing user edits.
$bundledSkillHashes = @('920BEA508DA99E5903931236F7426EBD54FC730ED967F1924EFCEED8876D864C')
if (Test-Path -LiteralPath $skillSource) {
  $sourceHash = Get-NativePetFileHash $skillSource
  $targetHash = if (Test-Path -LiteralPath $skillTarget) { Get-NativePetFileHash $skillTarget } else { '' }
  if ($targetHash -eq $sourceHash) {
    $skillResult = 'already-installed'
  } elseif ($targetHash -and $bundledSkillHashes -notcontains $targetHash) {
    $skillResult = 'existing-skill-preserved'
  } else {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($skillTarget))
    $temporary = $skillTarget + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
      Copy-Item -LiteralPath $skillSource -Destination $temporary
      if ((Get-NativePetFileHash $temporary) -ne $sourceHash) { throw 'The companion skill changed while preparing its installation.' }
      if ($targetHash) {
        if ((Get-NativePetFileHash $skillTarget) -ne $targetHash) { throw 'The installed companion skill changed during the upgrade; it has been preserved.' }
        $backupFolder = Join-Path ([IO.Path]::GetFullPath($CodexHome)) ('skills-backups\whale-companion-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($backupFolder)
        $skillBackup = Join-Path $backupFolder 'SKILL.md'
        # File.Replace commits the new skill and retains the original bytes in
        # the backup in one operation. A failed replacement keeps the old skill.
        [IO.File]::Replace($temporary, $skillTarget, $skillBackup)
        $skillResult = 'upgraded'
      } else {
        [IO.File]::Move($temporary, $skillTarget)
        $skillResult = 'installed'
      }
    } finally {
      if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
  }
}
[PSCustomObject]@{ installed = $true; path = $destination; displayName = $manifest.displayName; selected = $false; companionSkill = $skillResult; companionSkillBackup = $skillBackup }
