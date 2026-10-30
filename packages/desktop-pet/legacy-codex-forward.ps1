param([string]$PetHome=$PSScriptRoot,[switch]$Auto,[switch]$Show)
# Old background callers remain stopped. Old manual shortcuts open the migrated pet.
if($Auto){exit 0}
$preferred=Join-Path $env:LOCALAPPDATA 'CodexWhalePet'
try{
  $record=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'codex-preferred.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($record.petHome){$preferred=[IO.Path]::GetFullPath([string]$record.petHome)}
}catch{}
$launcher=Join-Path $preferred 'whale-pet-start.ps1'
if(-not (Test-Path -LiteralPath $launcher)){throw 'Codex 桌宠安装不存在，请重新运行 install-codex.ps1。'}
& $launcher -PetHome $preferred -Show:$Show
