@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0whale-pet-start.ps1" -PetHome "%~dp0." -Show
exit /b %errorlevel%
