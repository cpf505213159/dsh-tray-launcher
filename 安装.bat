@echo off
chcp 65001 >nul
setlocal
title DeepSeek Harness 托盘启动器 - 一键安装
cd /d "%~dp0"

echo ==================================================
echo   DeepSeek Harness 桌面托盘启动器 - 一键安装
echo ==================================================
echo.

if not exist "%~dp0install.ps1" goto remote

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Yes -Launch %*
if errorlevel 1 goto failed
goto done

:remote
echo 未在当前目录找到 install.ps1，尝试从 GitHub 下载安装器 ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/install.ps1' -OutFile (Join-Path $env:TEMP 'dshtray-install.ps1')"
if errorlevel 1 goto remote_failed
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\dshtray-install.ps1" -Yes -Launch %*
if errorlevel 1 goto failed

:done
echo.
echo [完成] 安装成功，已自动启动托盘！
echo        桌面已生成「DeepSeek Harness」快捷方式，以后双击它即可启动。
echo        （若看不到托盘图标，点任务栏右下角 ^^ 展开即可找到蓝色鲸鱼图标）
goto end

:remote_failed
echo.
echo [失败] 无法下载安装脚本。
echo        提示：如果你是直接点开压缩包运行，请先右键压缩包选择「全部解压缩」，
echo              再双击解压文件夹里的「安装.bat」（解压后支持离线安装）。
goto end

:failed
echo.
echo [失败] 安装未完成，请查看上方提示信息。

:end
echo.
echo 按任意键关闭此窗口 ...
pause >nul
