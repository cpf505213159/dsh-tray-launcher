@echo off
setlocal
title DeepSeek Harness Tray - Install
cd /d "%~dp0"

if not exist "%~dp0install.ps1" goto remote

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Yes %*
if errorlevel 1 goto failed
goto done

:remote
echo Installer not found next to this file, downloading from GitHub ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/install.ps1' -OutFile $env:TEMP\dshtray-install.ps1; & $env:TEMP\dshtray-install.ps1 -Yes"
if errorlevel 1 goto failed

:done
echo.
echo [OK] Installation finished. Double-click "DeepSeek Harness" on your desktop to start.
goto end

:failed
echo.
echo [FAILED] Installation did not complete. Please read the messages above.

:end
echo.
echo Press any key to close this window ...
pause >nul
