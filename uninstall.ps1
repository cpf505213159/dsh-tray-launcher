# dsh-tray-launcher 一键卸载
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
# 远程: powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $f=Join-Path $env:TEMP 'dshtray-uninstall.ps1'; irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/uninstall.ps1' -OutFile $f; & $f"
param(
    [string]$ShortcutName = "DeepSeek Harness"
)

$ErrorActionPreference = 'SilentlyContinue'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\DSHTray'

Write-Host '=================================================='
Write-Host '  DeepSeek Harness 桌面托盘启动器 - 一键卸载'
Write-Host '=================================================='
Write-Host '开始卸载 dsh-tray-launcher ...'

# 0) 读取配置里记录的自定义快捷方式路径（若有），确保非默认 -ShortcutName 也能删干净
$shortcutPaths = @()
$desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) ($ShortcutName + '.lnk')
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) ($ShortcutName + '.lnk')
$shortcutPaths += $desktopLnk
$shortcutPaths += $startupLnk
$cfgPath = Join-Path $InstallDir 'dsh-tray.config.json'
if (Test-Path $cfgPath) {
    try {
        $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg -and $cfg.PSObject.Properties.Name -contains 'shortcut' -and "$($cfg.shortcut)".Trim()) {
            $cfgShortcut = "$($cfg.shortcut)".Trim()
            if ($shortcutPaths -notcontains $cfgShortcut) { $shortcutPaths += $cfgShortcut }
            $cfgStartup = Join-Path ([Environment]::GetFolderPath('Startup')) ([System.IO.Path]::GetFileName($cfgShortcut))
            if ($shortcutPaths -notcontains $cfgStartup) { $shortcutPaths += $cfgStartup }
        }
    } catch {}
}

# 1) 结束托盘进程
# 安装版路径是 %LOCALAPPDATA%\Programs\DSHTray\tray.ps1（不含连字符），插件/仓库版
# 在 dsh-tray-launcher\tray.ps1，所以按 tray.ps1 连同其所在目录匹配，而不是匹配 'dsh-tray'。
# 排除自身与任意 uninstall 进程；用 taskkill /T 连托盘经 cmd 拉起的 harness(node) 一起收。
$trayProcs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -match '(?i)(DSHTray|dsh-tray-launcher)[\\/]+tray\.ps1' -and
        $_.CommandLine -notmatch 'uninstall'
    }
foreach ($p in $trayProcs) { & "$env:SystemRoot\System32\taskkill.exe" /PID $p.ProcessId /T /F 2>$null | Out-Null }
if ($trayProcs) { Start-Sleep -Milliseconds 300 }

# 2) 删除桌面快捷方式 + 开机自启副本
foreach ($lnk in $shortcutPaths) {
    if ($lnk -and (Test-Path $lnk)) {
        Remove-Item $lnk -Force
        if (-not (Test-Path $lnk)) { Write-Host ('已删除: ' + $lnk) }
        else { Write-Warning ('未能删除: ' + $lnk) }
    }
}

# 3) 删除安装目录
if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
    if (-not (Test-Path $InstallDir)) {
        Write-Host ('已删除: ' + $InstallDir)
    } else {
        Write-Warning ('安装目录未能完全删除（可能有文件仍被占用）: ' + $InstallDir)
    }
}

Write-Host ''
Write-Host '卸载完成。'
Write-Host '如果当时是用 npm 装的，再执行: npm uninstall -g dsh-tray-launcher'
