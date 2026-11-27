@echo off
rem dsh-tray-launcher console mode: run dsh web in foreground with logs printed here.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tray.ps1" -ConsoleMode
echo.
pause
