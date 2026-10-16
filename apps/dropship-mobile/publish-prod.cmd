@echo off
setlocal
cd /d "%~dp0..\.."
powershell -ExecutionPolicy Bypass -File "%CD%\scripts\publish-update.ps1" -Channel prod -ConfigFile "%CD%\config\dropship-mobile.env" -InboxDir "%CD%\inbox\dropship-mobile" %*
pause