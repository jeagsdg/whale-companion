<# dsh-whale-notify - notification channel self-test (does not need DSH running) #>
param([Parameter(Position=0)][string]$Kind = 'completion')
$ErrorActionPreference = 'Stop'
$cands = @(
  (Join-Path $env:USERPROFILE '.dsh\profiles\desktop\node_modules\dsh-whale-notify\lib\toast.ps1'),
  (Join-Path $env:USERPROFILE '.dsh\whale-notify\dsh-whale-notify\lib\toast.ps1')
)
$toast = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $toast) { Write-Host 'toast.ps1 not found - install the plugin first.' -ForegroundColor Red; exit 1 }
$lib = Split-Path -Parent $toast
$art = Join-Path (Split-Path -Parent $lib) 'assets\notify'
$dir = Join-Path ([System.IO.Path]::GetTempPath()) ('whale-selftest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$tf = Join-Path $dir 'title.txt'; $bf = Join-Path $dir 'body.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tf, '鲸鱼娘提醒 · 自检', $utf8)
[System.IO.File]::WriteAllText($bf, ('通道自检：' + $Kind), $utf8)
$args = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$toast,'-TitleFile',$tf,'-BodyFile',$bf,'-Kind',$Kind,'-Sound','1','-Scenario','reminder')
$hero = Join-Path $art ('hero-' + $Kind + '.png')
if (Test-Path -LiteralPath $hero) { $args += @('-Image', $hero) }
$ico = Join-Path $art 'whale-app.png'
if (Test-Path -LiteralPath $ico) { $args += @('-IconPath', $ico) }
$p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
Write-Host ('toast.ps1 exit=' + $p.ExitCode + ' (0/4/5 = ok)') -ForegroundColor Cyan
Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
