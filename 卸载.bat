@echo off
setlocal
title DeepSeek Harness Tray - Uninstall
cd /d "%~dp0"

if not exist "%~dp0uninstall.ps1" goto remote
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
if errorlevel 1 goto failed
goto done

:remote
echo Uninstaller not found next to this file, downloading from GitHub ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/uninstall.ps1' -OutFile (Join-Path $env:TEMP 'dshtray-uninstall.ps1')"
if errorlevel 1 goto failed
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\dshtray-uninstall.ps1" %*
if errorlevel 1 goto failed

:done
echo.
goto end

:failed
echo.
echo [FAILED] Uninstall did not complete. Please read the messages above.

:end
echo.
pause
