param([string]$PetHome = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
try {
  # Codex pipes UTF-8 JSON; Windows PowerShell otherwise uses the console code page.
  [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
  . (Join-Path $PSScriptRoot 'whale-pet-common.ps1')
  . (Join-Path $PSScriptRoot 'whale-host.ps1')
  $raw = [Console]::In.ReadToEnd()
  if ($raw.Length -gt 1048576) { exit 0 }
  $inputEvent = $raw | ConvertFrom-Json
  $event = Convert-PetHookEvent $inputEvent
  if ($event) { Send-PetHostEvent $PetHome $event }
} catch { }
# No stdout, no permission decision, no next turn. This hook cannot grant an approval.
exit 0
