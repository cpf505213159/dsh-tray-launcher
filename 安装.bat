@echo off
setlocal
title DeepSeek Harness Tray - Install
cd /d "%~dp0"

if not exist "%~dp0install.ps1" goto remote

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Yes -Launch %*
if errorlevel 1 goto failed
goto done

:remote
echo Installer not found next to this file, downloading from GitHub ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/install.ps1' -OutFile (Join-Path $env:TEMP 'dshtray-install.ps1')"
if errorlevel 1 goto remote_failed
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\dshtray-install.ps1" -Yes -Launch %*
if errorlevel 1 goto failed

:done
echo.
goto end

:remote_failed
echo.
echo [FAILED] Could not download install.ps1 from GitHub.
echo          If you opened this inside a ZIP file, please EXTRACT ALL files first,
echo          then double-click the installer inside the extracted folder.
goto end

:failed
echo.
echo [FAILED] Installation did not complete. Please read the messages above.

:end
echo.
pause
