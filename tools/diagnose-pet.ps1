param([string]$PetHome = '', [ValidateSet('text','json')][string]$Format = 'text', [string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
$package = Join-Path $PSScriptRoot '..\packages\desktop-pet'
. (Join-Path $package 'whale-diagnostics.ps1')
if (-not $PetHome) {
  $PetHome = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexWhalePet'
  if ([IO.Directory]::Exists($PetHome)) {
    try { . (Join-Path $package 'whale-startup.ps1'); $PetHome = Resolve-PetPhysicalHome $PetHome } catch { }
  }
}
$report = Get-PetHealthReport $PetHome
$content = if ($Format -eq 'json') { $report | ConvertTo-Json -Depth 10 } else { ConvertTo-PetHealthText $report }
if ($OutputPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $content, (New-Object Text.UTF8Encoding($true))) }
else { Write-Output $content }
