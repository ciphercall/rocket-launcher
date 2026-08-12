@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo ========================================
echo  Rocket Launcher - Publish APKs Only
echo ========================================
echo.
echo Expects both APKs in inbox\:
echo   - app-arm64-v8a-release.apk
echo   - app-armeabi-v7a-release.apk
echo.

set "RELEASE_NOTES="
set /p RELEASE_NOTES="Release notes (optional, press Enter for default): "
if "!RELEASE_NOTES!"=="" set "RELEASE_NOTES=App update"

echo.
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\publish-update.ps1" -ReleaseNotes "!RELEASE_NOTES!"
if errorlevel 1 (
    echo.
    echo PUBLISH FAILED.
    pause
    exit /b 1
)

echo.
pause
exit /b 0
