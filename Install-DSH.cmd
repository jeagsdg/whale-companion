@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1" %*
if errorlevel 1 (
  echo Installation failed. See the error above. Existing data is backed up.
  pause
  exit /b 1
)
echo Installation complete. Restart DSH to load the plugin.
pause
