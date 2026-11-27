@echo off
chcp 65001 >nul
setlocal
title DeepSeek Harness 托盘启动器 - 一键卸载
cd /d "%~dp0"

echo ==================================================
echo   DeepSeek Harness 桌面托盘启动器 - 一键卸载
echo ==================================================
echo.

if not exist "%~dp0uninstall.ps1" goto remote
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
if errorlevel 1 goto failed
goto done

:remote
echo 未在当前目录找到 uninstall.ps1，尝试从 GitHub 下载卸载器 ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/uninstall.ps1' -OutFile (Join-Path $env:TEMP 'dshtray-uninstall.ps1')"
if errorlevel 1 goto failed
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\dshtray-uninstall.ps1" %*
if errorlevel 1 goto failed

:done
echo.
echo [完成] 卸载已完成。
goto end

:failed
echo.
echo [失败] 卸载未完成，请查看上方提示信息。

:end
echo.
echo 按任意键关闭此窗口 ...
pause >nul
