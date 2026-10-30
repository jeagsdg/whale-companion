param([string]$PetHome=$PSScriptRoot,[string]$SessionRoot='',[switch]$Once,[switch]$Replay)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'whale-pet-common.ps1')
. (Join-Path $PSScriptRoot 'whale-host.ps1')
. (Join-Path $PSScriptRoot 'whale-codex-core.ps1')
if(-not (Initialize-PetCodexWatch $PetHome $SessionRoot ([bool]$Replay))){exit 0}
try{
  do{
    if((Read-PetJson (Join-Path $PetHome 'control.json')).stopped){break}
    if((Read-PetJson (Join-Path $PetHome 'pet-preferences.json')).host -eq 'dsh'){break}
    Invoke-PetCodexWatch
    if(-not $Once){Start-Sleep -Milliseconds 1500}
  }while(-not $Once)
}finally{Close-PetCodexWatch}
