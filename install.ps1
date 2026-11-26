# dsh-tray-launcher 一键安装器
# 用法（克隆仓库后）:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
# 参数:
#   -DshPath <path>    手动指定 dsh CLI 入口（@deepseek-ai/dsh/lib/bin.js）
#   -Icon <path.ico>   自定义托盘图标（可选；默认「自动适配 Windows 深浅主题」）
#   -ShortcutName <名> 桌面快捷方式名称（默认 DeepSeek Harness）
#   -Autostart         同时注册开机自启
#   -Yes               跳过安装前确认提示（自动化场景）
#   -DryRun            只检测与打印，不写入任何文件
#   -Cwd <dir>         harness 的工作目录（默认 %USERPROFILE%）
param(
    [string]$DshPath = "",
    [string]$Icon = "",
    [string]$ShortcutName = "DeepSeek Harness",
    [string]$Cwd = "",
    [switch]$Autostart,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$RepoOwner = 'fancr-code'
$RepoName  = 'dsh-tray-launcher'
$Branch    = 'main'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\DSHTray'

function Resolve-DshBin {
    if ($DshPath -and (Test-Path $DshPath)) { return $DshPath }
    $candidates = @()
    # 1) dsh 命令在 PATH 上：从 .bin shim 反推真实 bin.js
    $cmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($cmd) {
        $binDir = Split-Path $cmd.Source -Parent
        # 全局安装时 $binDir 是 npm 前缀（如 %APPDATA%\npm），包体在其 node_modules 下
        $candidates += (Join-Path $binDir 'node_modules\@deepseek-ai\dsh\lib\bin.js')
    }
    # 2) 当前 npm 的缓存目录（权威来源，兼容自定义/重定向的缓存路径）
    try {
        $cache = & npm config get cache 2>$null
        if ($cache) {
            $npxDir = Join-Path $cache '_npx'
            if (Test-Path $npxDir) {
                $candidates += Get-ChildItem $npxDir -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js' }
            }
        }
    } catch {}
    # 3) npm 全局安装
    try {
        $g = & npm root -g 2>$null
        if ($g) { $candidates += (Join-Path $g '@deepseek-ai\dsh\lib\bin.js') }
    } catch {}
    # 4) 常见兜底位置
    $candidates += (Join-Path $env:APPDATA 'npm\node_modules\@deepseek-ai\dsh\lib\bin.js')
    $localNpx = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
    if (Test-Path $localNpx) {
        $candidates += Get-ChildItem $localNpx -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js' }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
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
if (-not $nodePath -and (Test-Path 'C:\Program Files\nodejs\node.exe')) { $nodePath = 'C:\Program Files\nodejs\node.exe' }

Write-Output "dsh bin : $dshBin"
Write-Output "node    : $nodePath"
Write-Output "install : $InstallDir"
Write-Output "shortcut: $(Join-Path ([Environment]::GetFolderPath('Desktop')) ($ShortcutName + '.lnk'))"
Write-Output ("cwd     : " + $(if ($Cwd -and (Test-Path $Cwd)) { $Cwd } else { $env:USERPROFILE }))
Write-Output "autostart: $Autostart"

if (-not $nodePath) { Write-Error '未找到 node.exe，请先安装 Node.js。' ; exit 1 }
if (-not $dshBin) {
    Write-Host ''
    Write-Host '未能自动找到 dsh CLI。' -ForegroundColor Yellow
    Write-Host '  方式一：重新运行并指定路径：'
    Write-Host '    dsh-tray-install -DshPath "<路径>\node_modules\@deepseek-ai\dsh\lib\bin.js"'
    Write-Host '  方式二：现在直接粘贴完整路径并回车（跳过则回车）：'
    $manual = Read-Host '  bin.js 路径'
    if ($manual -and (Test-Path $manual)) { $dshBin = $manual }
    if (-not $dshBin) { Write-Error '未找到 dsh CLI，安装中止。' ; exit 1 }
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

# 托盘图标：形状源只保留 DeepSeek 鲸鱼，颜色由 tray.ps1 按系统主题在运行时生成
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

# 图标模式：默认 auto 跟随系统主题；-Icon 传入时复制到安装目录并写绝对路径
$iconSetting = 'auto'
if ($Icon -and (Test-Path $Icon)) {
    $iconCopy = Join-Path $InstallDir 'custom.ico'
    Copy-Item $Icon $iconCopy -Force
    $iconSetting = $iconCopy
}

# 桌面快捷方式
$ws = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop ($ShortcutName + '.lnk')
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = (Join-Path $env:SystemRoot 'System32\wscript.exe')
$lnk.Arguments = '"' + $launcherDest + '"'
$lnk.WorkingDirectory = $InstallDir
# 快捷方式图标：自动模式按当前主题先生成一份，托盘启动后还会随主题刷新
$shortcutIcon = $null
if ($iconSetting -eq 'auto') {
    try {
        Add-Type -AssemblyName System.Drawing
        Add-Type -Path $themeCsDest -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll')
        $light = [TrayTheme]::IsLightTheme()
        $autoName = if ($light) { 'auto-light.ico' } else { 'auto-dark.ico' }
        $autoIco = Join-Path $InstallDir $autoName
        if ([TrayIconFactory]::Build((Join-Path $iconDir 'deepseek.ico'), [TrayTheme]::IconColor($light), $autoIco)) {
            $shortcutIcon = $autoIco
        }
    } catch {}
} else {
    $shortcutIcon = $iconSetting
}
if (-not $shortcutIcon) { $shortcutIcon = Join-Path $iconDir 'deepseek.ico' }
$lnk.IconLocation = $shortcutIcon + ',0'
$lnk.Description = 'DeepSeek Harness 系统托盘启动器'
$lnk.WindowStyle = 1
$lnk.Save()

# 配置文件
$cwdSetting = if ($Cwd -and (Test-Path $Cwd)) { $Cwd } else { $env:USERPROFILE }
$cfg = @{
    dshBin        = $dshBin
    node          = $nodePath
    url           = 'http://127.0.0.1:3080'
    cwd           = $cwdSetting
    icon          = $iconSetting
    shortcut      = $lnkPath
}
$cfg | ConvertTo-Json | Set-Content -Path (Join-Path $InstallDir 'dsh-tray.config.json') -Encoding UTF8

# 开机自启
if ($Autostart) {
    $startup = [Environment]::GetFolderPath('Startup')
    Copy-Item $lnkPath (Join-Path $startup ($ShortcutName + '.lnk')) -Force
}

Write-Output ''
Write-Output '安装完成。双击桌面快捷方式启动（无窗口，托盘图标）。'
Write-Output ("安装目录: " + $InstallDir)
Write-Output ("日志目录: " + (Join-Path $InstallDir 'logs'))
