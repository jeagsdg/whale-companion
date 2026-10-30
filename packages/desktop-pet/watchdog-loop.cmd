@echo off
rem Legacy entry point: one silent single-instance check, no endless spawning loop.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0whale-pet-start.ps1" -PetHome "%~dp0." -Auto
exit /b %errorlevel%
