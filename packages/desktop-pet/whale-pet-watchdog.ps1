# Compatibility entry for old watchdog-loop.cmd installations. Never show or kill a healthy pet.
param([string]$PetHome = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PetHome 'whale-pet-start.ps1'
if (Test-Path -LiteralPath $launcher) { & $launcher -PetHome $PetHome -Auto }