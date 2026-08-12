@echo off
cd /d "%~dp0..\Attandance_App"
call "%~dp0..\Attandance_App\PUBLISH-OTA-UPDATE.cmd"
exit /b %ERRORLEVEL%
