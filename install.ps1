# dsh-tray-launcher 一键安装器
# 用法（克隆或解压仓库后）:
#   双击 安装.bat（最简单），或运行:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
# 参数:
#   -DshPath <path>    手动指定 dsh 入口（支持 bin.js、dsh.cmd 或所在目录），自动检测失败时使用
#   -ShortcutName <名> 桌面快捷方式名称（默认 DeepSeek Harness）
#   -Autostart         同时注册开机自启
#   -Launch            安装完成后立即启动托盘（安装.bat 默认启用）
#   -Yes               跳过安装前确认提示（自动化场景）
#   -DryRun            只检测与打印，不写入任何文件
#   -Cwd <dir>         harness 的工作目录（默认 %USERPROFILE%）
param(
    [string]$DshPath = "",
    [string]$ShortcutName = "DeepSeek Harness",
    [string]$Cwd = "",
    [switch]$Autostart,
    [switch]$Launch,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$RepoOwner = 'cpf505213159'
$RepoName  = 'dsh-tray-launcher'
$Branch    = 'main'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\DSHTray'

function Resolve-DshFromShim([string]$shimPath) {
    if (-not $shimPath -or -not (Test-Path $shimPath -PathType Leaf)) { return $null }
    $binDir = Split-Path $shimPath -Parent
    # 快路径：标准 npm / nvm / fnm 全局目录结构
    $direct = Join-Path $binDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
    if (Test-Path $direct -PathType Leaf) { return (Resolve-Path $direct).Path }

    # 解析 shim 内容（覆盖 pnpm / yarn / npm / 自定义前缀）
    try {
        $content = Get-Content $shimPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $content) { return $null }
        $ms = [regex]::Matches($content, '(?i)([^\s"''`]+@deepseek-ai[\\/]+dsh[\\/]+lib[\\/]+bin\.js)')
        foreach ($m in $ms) {
            $raw = $m.Groups[1].Value
            $prefix = $binDir.TrimEnd('\').Replace('$', '$$') + '\'
            $expanded = $raw -replace '(?i)(%~?dp0%?[\\/]?|\$basedir[\\/]?|\$\{basedir\}[\\/]?)', $prefix
            $expanded = [Environment]::ExpandEnvironmentVariables($expanded)
            $expanded = $expanded -replace '/', '\'
            try {
                if (-not [System.IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $binDir $expanded }
                $full = [System.IO.Path]::GetFullPath($expanded)
                if (Test-Path $full -PathType Leaf) { return $full }
            } catch {}
        }
    } catch {}
    return $null
}

function Resolve-DshFromPath([string]$candidate) {
    if (-not $candidate) { return $null }
    $p = $candidate.Trim().Trim('"').Trim("'")
    if (-not $p -or -not (Test-Path $p)) { return $null }
    if ((Test-Path $p -PathType Leaf) -and $p -match '(?i)bin\.js$') { return (Resolve-Path $p).Path }
    if (Test-Path $p -PathType Container) {
        foreach ($rel in @('lib\bin.js', 'node_modules\@deepseek-ai\dsh\lib\bin.js', '@deepseek-ai\dsh\lib\bin.js')) {
            $try = Join-Path $p $rel
            if (Test-Path $try -PathType Leaf) { return (Resolve-Path $try).Path }
        }
        foreach ($shimName in @('dsh.cmd', 'dsh.ps1', 'dsh')) {
            $r = Resolve-DshFromShim (Join-Path $p $shimName)
            if ($r) { return $r }
        }
        return $null
    }
    return (Resolve-DshFromShim $p)
}

function Resolve-DshBin {
    $manual = Resolve-DshFromPath $DshPath
    if ($manual) { return $manual }
    $candidates = @()

    # 1) PATH 上的所有 dsh 命令（通过 shim 反推真实 bin.js：兼容 npm / pnpm / yarn / nvm / fnm）
    $cmds = @(Get-Command dsh -All -ErrorAction SilentlyContinue)
    foreach ($cmd in $cmds) {
        if ($cmd.Source) {
            $resolved = Resolve-DshFromShim $cmd.Source
            if ($resolved) { return $resolved }
        }
    }

    # 2) 包管理器全局根目录（npm / pnpm / yarn）
    try {
        $g = (& npm root -g 2>$null | Select-Object -First 1)
        if ($g) { $candidates += (Join-Path $g.Trim() '@deepseek-ai\dsh\lib\bin.js') }
    } catch {}
    try {
        if (Get-Command pnpm -ErrorAction SilentlyContinue) {
            $pg = (& pnpm root -g 2>$null | Select-Object -First 1)
            if ($pg) { $candidates += (Join-Path $pg.Trim() '@deepseek-ai\dsh\lib\bin.js') }
        }
    } catch {}
    try {
        if (Get-Command yarn -ErrorAction SilentlyContinue) {
            $yg = (& yarn global dir 2>$null | Select-Object -First 1)
            if ($yg) { $candidates += (Join-Path $yg.Trim() 'node_modules\@deepseek-ai\dsh\lib\bin.js') }
        }
    } catch {}

    # 3) 当前 npm 的 npx 缓存（按修改时间倒序，优先最新缓存）
    try {
        $cache = (& npm config get cache 2>$null | Select-Object -First 1)
        if ($cache) {
            $npxDir = Join-Path $cache.Trim() '_npx'
            if (Test-Path $npxDir) {
                $candidates += Get-ChildItem $npxDir -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    ForEach-Object { Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js' }
            }
        }
    } catch {}

    # 4) 各包管理器常见默认路径兜底（npm / pnpm / yarn / bun / volta / npx）
    $candidates += (Join-Path $env:APPDATA 'npm\node_modules\@deepseek-ai\dsh\lib\bin.js')
    $pnpmGlobal = Join-Path $env:LOCALAPPDATA 'pnpm\global'
    if (Test-Path $pnpmGlobal) {
        $candidates += Get-ChildItem $pnpmGlobal -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js' }
    }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Yarn\Data\global\node_modules\@deepseek-ai\dsh\lib\bin.js')
    $candidates += (Join-Path $env:USERPROFILE '.bun\install\global\node_modules\@deepseek-ai\dsh\lib\bin.js')
    $candidates += (Join-Path $env:LOCALAPPDATA 'Volta\tools\image\packages\@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh\lib\bin.js')
    $candidates += (Join-Path $env:LOCALAPPDATA 'Volta\tools\image\packages\@deepseek-ai\dsh\lib\bin.js')
    $localNpx = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
    if (Test-Path $localNpx) {
        $candidates += Get-ChildItem $localNpx -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js' }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c -PathType Leaf)) { return (Resolve-Path $c).Path }
    }
    return $null
}

# 防粘贴事故：把从 README 粘进来的注释垃圾当参数时，恢复默认快捷方式名
if ([string]::IsNullOrWhiteSpace($ShortcutName) -or $ShortcutName.Trim() -in @('+', '#', '-', '.', '/')) {
    $ShortcutName = 'DeepSeek Harness'
}

$dshBin = Resolve-DshBin
# 优先系统正式 node（codex 等工具链 node 可能是转发桩，会导致黑窗）
$nodePath = ''
$cmdNode = Get-Command node.exe -ErrorAction SilentlyContinue
if ($cmdNode -and $cmdNode.Source -notmatch 'codex') { $nodePath = $cmdNode.Source }
if (-not $nodePath -and (Test-Path 'C:\Program Files\nodejs\node.exe')) { $nodePath = 'C:\Program Files\nodejs\node.exe' }
if (-not $nodePath -and $cmdNode) { $nodePath = $cmdNode.Source }
if ($cmdNode -and $cmdNode.Source -match 'codex' -and $nodePath -ne $cmdNode.Source) {
    Write-Output "注意: 检测到工具链 node ($($cmdNode.Source))，已改用系统 node ($nodePath) 以避免黑窗。"
}

Write-Output "dsh bin : $dshBin"
Write-Output "node    : $nodePath"
Write-Output "install : $InstallDir"
Write-Output "shortcut: $(Join-Path ([Environment]::GetFolderPath('Desktop')) ($ShortcutName + '.lnk'))"
Write-Output ("cwd     : " + $(if ($Cwd -and (Test-Path $Cwd)) { $Cwd } else { $env:USERPROFILE }))
Write-Output "autostart: $Autostart"

if (-not $nodePath) {
    Write-Host ''
    Write-Host '未找到 Node.js (node.exe)。' -ForegroundColor Red
    Write-Host '请先安装 Node.js（推荐 LTS 版本，下载地址: https://nodejs.org/ ），安装完成后重新双击「安装.bat」。'
    exit 1
}
if (-not $dshBin) {
    if ($DryRun) {
        # DryRun 面向自动化：不阻塞等待输入，只报告检测结果
        Write-Output 'DryRun: 未找到 dsh CLI（正式安装会提示自动安装或手动指定路径）。'
    } else {
        Write-Host ''
        Write-Host '未能自动找到你电脑上的 DeepSeek Harness (dsh)。' -ForegroundColor Yellow
        $hasNpm = [bool](Get-Command npm -ErrorAction SilentlyContinue)
        if ($hasNpm) {
            Write-Host '  直接输入 1 并回车 ：自动执行 npm install -g @deepseek-ai/dsh 安装 dsh 并继续'
        }
        Write-Host '  或者直接拖入/粘贴 ：bin.js / dsh.cmd 文件（或 dsh 所在目录）路径后回车'
        Write-Host '  直接回车          ：取消安装'
        $manual = Read-Host '请选择或粘贴路径'
        if ($hasNpm -and $manual -and $manual.Trim() -eq '1') {
            Write-Host '正在通过 npm 安装 @deepseek-ai/dsh ...' -ForegroundColor Cyan
            & npm install -g @deepseek-ai/dsh
            $dshBin = Resolve-DshBin
        } elseif ($manual) {
            $dshBin = Resolve-DshFromPath $manual
        }
        if (-not $dshBin) { Write-Error '未找到 dsh CLI，安装中止。' ; exit 1 }
    }
}

if ($DryRun) { Write-Output 'DryRun: 检测完成，未写入任何文件。'; exit 0 }

# ---- 安装前确认 ----
if (-not $Yes) {
    Write-Host ''
    Write-Host '即将执行以下操作：' -ForegroundColor Cyan
    Write-Host ("  1. 复制脚本与图标到: " + $InstallDir)
    Write-Host ("  2. 创建桌面快捷方式: " + (Join-Path ([Environment]::GetFolderPath('Desktop')) ($ShortcutName + '.lnk')))
    if ($Autostart) { Write-Host '  3. 注册开机自启' }
    $answer = Read-Host '是否继续安装? [Y/n]'
    if ($answer -and $answer.Trim().ToLower() -notin @('y', 'yes', '是')) {
        Write-Host '已取消，未写入任何文件。'
        exit 0
    }
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# 若已装过旧版本且托盘仍在运行，先停止旧托盘以便覆盖更新并立即生效
try {
    $oldProcs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -match '(?i)DSHTray[\\/]+tray\.ps1'
        }
    if ($oldProcs) {
        Write-Output '检测到旧版托盘正在运行，先停止旧进程再更新...'
        foreach ($p in $oldProcs) { & "$env:SystemRoot\System32\taskkill.exe" /PID $p.ProcessId /T /F 2>$null | Out-Null }
        Start-Sleep -Milliseconds 400
    }
} catch {}

# tray.ps1：优先用同目录副本（克隆安装），否则从 GitHub 下载（远程一行命令安装）
$remoteMode = -not (Test-Path (Join-Path $PSScriptRoot 'tray.ps1'))
$traySource = Join-Path $PSScriptRoot 'tray.ps1'
if ($remoteMode) {
    $traySource = Join-Path $env:TEMP 'dsh-tray.ps1'
    $rawUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/tray.ps1"
    Invoke-WebRequest -Uri $rawUrl -OutFile $traySource -UseBasicParsing
}
Copy-Item $traySource (Join-Path $InstallDir 'tray.ps1') -Force

# 版本文件：让安装目录里的 tray.ps1 知道自己真实版本（缺 package.json 时回退默认会误报“有新版本”）
$installVersion = ''
$pkgLocal = Join-Path $PSScriptRoot 'package.json'
if (Test-Path $pkgLocal) {
    # 显式 UTF8：PowerShell 5.1 对无 BOM 的 UTF-8 按 ANSI(GBK) 解码，中文 description 会让 JSON 解析失败
    try { $installVersion = (Get-Content $pkgLocal -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch {}
}
if (-not $installVersion -and $remoteMode) {
    try {
        $verJson = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/package.json" -UseBasicParsing | Select-Object -ExpandProperty Content
        $installVersion = ($verJson | ConvertFrom-Json).version
    } catch {}
}
if ($installVersion) { Set-Content -Path (Join-Path $InstallDir 'VERSION') -Value $installVersion -Encoding ASCII }

# VBS uses the GUI-script host to start PowerShell without attaching a console.
$launcherSource = Join-Path $PSScriptRoot 'launch-hidden.vbs'
$launcherDest = Join-Path $InstallDir 'launch-hidden.vbs'
if (Test-Path $launcherSource) {
    Copy-Item $launcherSource $launcherDest -Force
} else {
    $launcherUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/launch-hidden.vbs"
    Invoke-WebRequest -Uri $launcherUrl -OutFile $launcherDest -UseBasicParsing
}

# 托盘图标：形状源只保留 DeepSeek 鲸鱼，颜色在 tray.ps1 中固定为品牌蓝
$iconDir = Join-Path $InstallDir 'icons'
New-Item -ItemType Directory -Path $iconDir -Force | Out-Null
$iconSrc = Join-Path $PSScriptRoot 'icons\deepseek.ico'
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc (Join-Path $iconDir 'deepseek.ico') -Force
} else {
    $iconUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/icons/deepseek.ico"
    Invoke-WebRequest -Uri $iconUrl -OutFile (Join-Path $iconDir 'deepseek.ico') -UseBasicParsing
}

# 主题支持库（图标着色 + 菜单渲染器）；缺失时托盘会降级为系统默认图标
$libDir = Join-Path $InstallDir 'lib'
New-Item -ItemType Directory -Path $libDir -Force | Out-Null
$themeCsDest = Join-Path $libDir 'TrayTheme.cs'
$themeCsSrc = Join-Path $PSScriptRoot 'lib\TrayTheme.cs'
if (Test-Path $themeCsSrc) {
    Copy-Item $themeCsSrc $themeCsDest -Force
} else {
    $csUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/lib/TrayTheme.cs"
    Invoke-WebRequest -Uri $csUrl -OutFile $themeCsDest -UseBasicParsing
}

# 清理旧版遗留的图标文件（新版本只用 icons\deepseek.ico 作为形状源）
foreach ($legacy in @('icons\liangzu.ico', 'icons\whale-girl.ico', 'icon.ico', 'custom.ico', 'auto-light.ico', 'auto-dark.ico')) {
    $legacyPath = Join-Path $InstallDir $legacy
    if (Test-Path $legacyPath -PathType Leaf) { Remove-Item $legacyPath -Force -ErrorAction SilentlyContinue }
}

# 解除从 GitHub 下载 ZIP 带来的 Mark-of-the-Web 标记，避免双击快捷方式时弹 Windows 安全警告
foreach ($unblockTarget in @((Join-Path $InstallDir 'tray.ps1'), $launcherDest, (Join-Path $iconDir 'deepseek.ico'), $themeCsDest)) {
    try { if (Test-Path $unblockTarget) { Unblock-File -Path $unblockTarget -ErrorAction SilentlyContinue } } catch {}
}

# 桌面快捷方式
$ws = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop ($ShortcutName + '.lnk')
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = (Join-Path $env:SystemRoot 'System32\wscript.exe')
$lnk.Arguments = '"' + $launcherDest + '"'
$lnk.WorkingDirectory = $InstallDir
# 快捷方式图标：生成 DeepSeek 官方品牌蓝鲸鱼
$shortcutIcon = $null
try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -Path $themeCsDest -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll')
    $brandIco = Join-Path $InstallDir 'brand.ico'
    if ([TrayIconFactory]::Build((Join-Path $iconDir 'deepseek.ico'), '#4D6BFE', $brandIco)) {
        $shortcutIcon = $brandIco
    }
} catch {}
if (-not $shortcutIcon) { $shortcutIcon = Join-Path $iconDir 'deepseek.ico' }
$lnk.IconLocation = $shortcutIcon + ',0'
$lnk.Description = 'DeepSeek Harness 系统托盘启动器'
$lnk.WindowStyle = 1
$lnk.Save()

# 配置文件（重装时保留已有自定义 url 与未显式覆盖的 cwd）
$cfgPath = Join-Path $InstallDir 'dsh-tray.config.json'
$existingCfg = $null
if (Test-Path $cfgPath) {
    try { $existingCfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}
$urlSetting = 'http://127.0.0.1:3080'
if ($existingCfg -and $existingCfg.PSObject.Properties.Name -contains 'url' -and "$($existingCfg.url)".Trim()) {
    $urlSetting = "$($existingCfg.url)".Trim()
}
$cwdSetting = $env:USERPROFILE
if ($Cwd -and (Test-Path $Cwd)) {
    $cwdSetting = $Cwd
} elseif ($existingCfg -and $existingCfg.PSObject.Properties.Name -contains 'cwd' -and "$($existingCfg.cwd)".Trim() -and (Test-Path "$($existingCfg.cwd)".Trim())) {
    $cwdSetting = "$($existingCfg.cwd)".Trim()
}
$cfg = @{
    dshBin        = $dshBin
    node          = $nodePath
    url           = $urlSetting
    cwd           = $cwdSetting
    shortcut      = $lnkPath
}
$cfg | ConvertTo-Json | Set-Content -Path $cfgPath -Encoding UTF8

# 开机自启
if ($Autostart) {
    $startup = [Environment]::GetFolderPath('Startup')
    Copy-Item $lnkPath (Join-Path $startup ($ShortcutName + '.lnk')) -Force
}

Write-Output ''
Write-Output '安装完成。双击桌面快捷方式即可无窗口启动（托盘图标常驻）。'
Write-Output ("安装目录: " + $InstallDir)
Write-Output ("日志目录: " + (Join-Path $InstallDir 'logs'))

if ($Launch) {
    Write-Output '正在自动启动托盘，就绪后将自动打开浏览器...'
    try {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList ('"' + $launcherDest + '"') -WorkingDirectory $InstallDir
    } catch {
        Write-Warning ('自动启动失败，请手动双击桌面快捷方式: ' + $_.Exception.Message)
    }
}
