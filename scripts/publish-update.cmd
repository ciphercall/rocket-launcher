@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0publish-update.ps1" %*
pause
