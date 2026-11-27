@echo off
setlocal
title DeepSeek Harness Tray - Uninstall
cd /d "%~dp0"

if not exist "%~dp0uninstall.ps1" goto remote
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
goto done

:remote
echo Uninstaller not found next to this file, downloading from GitHub ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/uninstall.ps1' -OutFile $env:TEMP\dshtray-uninstall.ps1; & $env:TEMP\dshtray-uninstall.ps1"

:done
echo.
echo Press any key to close this window ...
pause >nul
