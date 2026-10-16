@echo off
setlocal
cd /d "%~dp0..\.."
powershell -ExecutionPolicy Bypass -File "%CD%\scripts\publish-update.ps1" -Channel prod -ConfigFile "%CD%\config\gazi-portfolio.env" -InboxDir "%CD%\inbox\gazi-portfolio" %*
pause