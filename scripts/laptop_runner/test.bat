@echo off
REM IMS Patrol Test Runner -- Tera P60
REM
REM Double-click this file. The PowerShell script does everything end to
REM end: dispatch the GitHub Actions build, wait for it, download the
REM Patrol APK pair, install on the device, run the tests, print result.
REM
REM Total wall time: about 7-9 minutes (CI build is the long pole).

setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_tests.ps1"

REM PS script has its own Read-Host pause, but keep this as a safety net
REM in case PowerShell itself fails to launch.
if errorlevel 1 (
    echo.
    echo Test run reported failure. See logs\ folder for details.
    echo.
    pause
)
endlocal
