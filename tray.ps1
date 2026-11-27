# dsh-tray-launcher
# 以系统托盘方式运行 DeepSeek Harness (dsh web)：无窗口、托盘图标管理、端口就绪自动开浏览器。
#
# 托盘模式   : powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File tray.ps1
# 控制台模式 : powershell -NoProfile -ExecutionPolicy Bypass -File tray.ps1 -ConsoleMode
# 测试模式   : 追加 -NoOpen 不自动打开浏览器
# -NoRespawn : 内部参数（无窗口重启自身时使用，防止循环）
param(
    [switch]$ConsoleMode,
    [switch]$NoOpen,
    [switch]$NoRespawn,
    [switch]$AttachOnly,
    [string]$DataDir = ''
)

# 状态目录：默认与脚本同目录（install.ps1 部署方式）；以 dsh 插件方式运行时
# 由 src/plugin.js 传入 -DataDir，避免把配置与日志写进 node_modules。
if ($DataDir.Trim() -ne '') { $script:dataDir = $DataDir.Trim() } else { $script:dataDir = $PSScriptRoot }

$ErrorActionPreference = 'SilentlyContinue'

# ---- 配置（install.ps1 写入；所有字段可选，缺省自动探测）----
$script:cfg = $null
$configPath = Join-Path $script:dataDir 'dsh-tray.config.json'
if (Test-Path $configPath) {
    try { $script:cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

function Get-CfgValue($name, $default) {
    if ($script:cfg) {
        $props = $script:cfg.PSObject.Properties.Name
        if ($props -contains $name) {
            $v = $script:cfg.$name
            if ($v -ne $null -and "$v".Trim() -ne '') { return "$v".Trim() }
        }
    }
    return $default
}

$url = Get-CfgValue 'url' 'http://127.0.0.1:3080'
$cwd = Get-CfgValue 'cwd' $env:USERPROFILE
if (-not (Test-Path $cwd)) { $cwd = $env:USERPROFILE }

# ---- 定位 node.exe ----
# 优先系统正式安装的 node：codex 等工具链的 node 可能是转发桩，
# 无窗标志传不到它重新拉起的真实 node 进程，会出现黑窗。
$script:systemNode = 'C:\Program Files\nodejs\node.exe'
$node = Get-CfgValue 'node' ''
if ($node -and $node -match 'codex' -and (Test-Path $script:systemNode)) { $node = $script:systemNode }
if (-not $node -or -not (Test-Path $node)) {
    $cmdNode = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmdNode) { $node = $cmdNode.Source }
    if ($node -and $node -match 'codex' -and (Test-Path $script:systemNode)) { $node = $script:systemNode }
}
if (-not $node -or -not (Test-Path $node)) {
    if (Test-Path $script:systemNode) { $node = $script:systemNode }
}

# ---- 定位 dsh CLI（lib/bin.js）----
function Find-DshBin {
    $manual = Get-CfgValue 'dshBin' ''
    if ($manual -and (Test-Path $manual)) { return $manual }
    $candidates = @()
    # 1) dsh 命令在 PATH 上：从 .bin shim 反推真实 bin.js
    $cmd = Get-Command dsh -ErrorAction SilentlyContinue
    if ($cmd) {
        $binDir = Split-Path $cmd.Source -Parent
        # .bin/shim 所在目录本身就是 npm 全局前缀，包体在 node_modules 下
        $candidates += (Join-Path $binDir 'node_modules\@deepseek-ai\dsh\lib\bin.js')
    }
    # 2) 当前 npm 的缓存目录（纯 PowerShell 探测，绝不执行外部命令：
    #    无控制台进程执行外部命令会触发 PowerShell 分配可见控制台=黑窗）
    $cacheDirs = @()
    if ($env:NPM_CONFIG_CACHE) { $cacheDirs += $env:NPM_CONFIG_CACHE }
    foreach ($rc in @((Join-Path $env:USERPROFILE '.npmrc'), (Join-Path $env:APPDATA 'npm\etc\npmrc'))) {
        if (Test-Path $rc) {
            $m = Select-String -Path $rc -Pattern '^\s*cache\s*=\s*(.+)\s*$' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($m -and $m.Line) {
                $v = ($m.Line -split '=', 2)[1].Trim().Trim('"').Trim("'")
                if ($v) { $cacheDirs += $v }
            }
        }
    }
    $cacheDirs += (Join-Path $env:LOCALAPPDATA 'npm-cache')
    foreach ($cache in $cacheDirs) {
        $npxDir = Join-Path $cache '_npx'
        if (Test-Path $npxDir) {
            $candidates += Get-ChildItem $npxDir -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js' }
        }
    }
    # 3) npm 全局安装（环境变量 / .npmrc prefix / 默认位置）
    $globalRoots = @()
    if ($env:NPM_CONFIG_PREFIX) { $globalRoots += $env:NPM_CONFIG_PREFIX }
    foreach ($rc in @((Join-Path $env:USERPROFILE '.npmrc'), (Join-Path $env:APPDATA 'npm\etc\npmrc'))) {
        if (Test-Path $rc) {
            $m = Select-String -Path $rc -Pattern '^\s*prefix\s*=\s*(.+)\s*$' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($m -and $m.Line) {
                $v = ($m.Line -split '=', 2)[1].Trim().Trim('"').Trim("'")
                if ($v) { $globalRoots += $v }
            }
        }
    }
    $globalRoots += (Join-Path $env:APPDATA 'npm')
    foreach ($g in $globalRoots) {
        if ($g) { $candidates += (Join-Path $g 'node_modules\@deepseek-ai\dsh\lib\bin.js') }
    }
    # 4) 常见兜底位置
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
$bin = Find-DshBin

# ---- 控制台模式：前台运行，日志直接打到窗口 ----
if ($ConsoleMode) {
    if (-not $node -or -not (Test-Path $node)) { Write-Host 'node.exe 未找到'; exit 1 }
    if (-not $bin) {
        Write-Host '未找到 dsh CLI (lib/bin.js)。请先运行 install.ps1 -DshPath <bin.js 路径>，或手动安装 dsh。'
        exit 1
    }
    & $node $bin web
    exit $LASTEXITCODE
}

# 注意：不在此处提前因找不到 bin 而退出——托盘可能只是"挂载"已运行的外部
# harness（例如作为 dsh 插件随 Harness 启动，harness 已在监听），此时根本不需要
# bin。只有真正要"拉起" harness 的分支才要求 bin（见下方启动分支）。

# ---- 托盘模式 ----
$script:TrayVersion = '1.5.5'
try {
    $pk = Join-Path $PSScriptRoot 'package.json'
    if (Test-Path $pk) {
        # 显式 UTF8：PowerShell 5.1 的 Get-Content 对无 BOM 的 UTF-8 按 ANSI(GBK) 解码，
        # package.json 含中文时 JSON 会解析失败，版本号随之回退默认值而误报“有新版本”
        $pv = (Get-Content $pk -Raw -Encoding UTF8 | ConvertFrom-Json).version
        if ($pv) { $script:TrayVersion = $pv }
    } else {
        # 本地/仓库安装（无 package.json）：读安装器写入的 VERSION，避免回退默认值导致误报“有新版本”
        $vf = Join-Path $PSScriptRoot 'VERSION'
        if (Test-Path $vf) { $vv = (Get-Content $vf -Raw -Encoding UTF8).Trim(); if ($vv) { $script:TrayVersion = $vv } }
    }
} catch {}
# 版本烙印：控制台标题（若有可见控制台，标题会显示实际运行的版本）与日志
try { $Host.UI.RawUI.WindowTitle = 'DSH-Tray v' + $script:TrayVersion } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 快路径：按句柄隐藏（SW_HIDE）并释放控制台（FreeConsole）。
# 不依赖启动标志——部分机器上 -WindowStyle Hidden 会被 Windows Terminal 默认终端机制忽略。
try {
    Add-Type -Name K32Win -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool FreeConsole();
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
    [Win32.K32Win]::ShowWindow([Win32.K32Win]::GetConsoleWindow(), 0) | Out-Null
    [Win32.K32Win]::FreeConsole() | Out-Null
} catch {}

# 工作集回收用的 P/Invoke（与上面分开声明：即使控制台隐藏那段被策略禁用，
# 内存回收仍可用；反之亦然）。
try {
    Add-Type -Name K32Mem -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess);
'@
} catch {}

# 兜底：若仍持有控制台（Add-Type 被策略禁用 / 隐藏失败），用 CreateNoWindow
# 无窗口重启自身后退出——原进程退出即销毁其控制台窗口，无需任何 C# 编译。
if (-not $NoRespawn) {
    try { $cw = [System.Console]::WindowWidth } catch { $cw = -1 }
    if ($cw -gt 0) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'powershell.exe'
            # 所有脚本参数必须放在 -File 之后（powershell.exe 只把 -File 之后的当脚本参数）
            $respawnArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -NoRespawn'
            if ($script:dataDir -ne $PSScriptRoot) { $respawnArgs = $respawnArgs + ' -DataDir "' + $script:dataDir + '"' }
            if ($NoOpen) { $respawnArgs = $respawnArgs + ' -NoOpen' }
            if ($AttachOnly) { $respawnArgs = $respawnArgs + ' -AttachOnly' }
            $psi.Arguments = $respawnArgs
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch {}
        exit 0
    }
}

$logDir = Join-Path $script:dataDir 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$outLog  = Join-Path $logDir 'dsh-out.log'
$errLog  = Join-Path $logDir 'dsh-err.log'
$trayLog = Join-Path $logDir 'dsh-tray.log'
$sessionFile = Join-Path $logDir 'session.json'

function Write-TrayLog($msg) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    # 托盘日志也做轮转，避免长期运行无限增长
    if ((Test-Path $trayLog) -and ((Get-Item $trayLog).Length -gt 10485760)) {
        Move-Item $trayLog ($trayLog + '.1') -Force -ErrorAction SilentlyContinue
    }
    Add-Content -Path $trayLog -Value $line -Encoding UTF8
}

# 日志轮转：单个日志超过阈值就先改名 .1 再继续写，避免无限增长
function Rotate-Log($path, [long]$maxBytes = 10485760) {
    try {
        if ((Test-Path $path) -and ((Get-Item $path).Length -gt $maxBytes)) {
            Move-Item $path ($path + '.1') -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}


# ---- 界面地址解析 ----
# 新版 dsh web（≥0.1.7）给 Web UI 加了鉴权：只有带 `?token=` 的地址能直接打开，
# 用裸地址会被要求“reopen the URL printed by dsh web”。托盘从 harness 的 stdout
# 日志里取最后一次打印的带 token 地址；取不到（旧版 harness）再退回配置里的 url。
$script:harnessUrl = $null
$script:outLogStart = 0
# 记录由本托盘拉起的 harness 进程与日志偏移（不含 token），供二次启动校验日志时效性
function Save-HarnessSession([int]$harnessPid, [long]$offset) {
    try {
        @{ pid = $harnessPid; outLogStart = $offset } | ConvertTo-Json -Compress | Set-Content -Path $sessionFile -Encoding UTF8
    } catch {}
}
function Clear-HarnessSession {
    try {
        if (Test-Path $sessionFile) { Remove-Item $sessionFile -Force -ErrorAction SilentlyContinue }
    } catch {}
}
function Get-LogHarnessUrlFromOffset([long]$offset) {
    # 只从指定偏移之后的新增日志区间找 token，避免把上一次运行的旧 token 当本次地址
    try {
        if (Test-Path $outLog) {
            $fs = [System.IO.File]::Open($outLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                if ($offset -gt 0 -and $offset -le $fs.Length) { $fs.Position = $offset }
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                $text = $sr.ReadToEnd()
                $mm = [regex]::Matches($text, 'dsh web:\s+(https?://\S+)')
                if ($mm.Count -gt 0) {
                    $u = $mm[$mm.Count - 1].Groups[1].Value.Trim()
                    if ($u -match '^https?://') { return $u }
                }
            } finally { $fs.Close() }
        }
    } catch {}
    return $null
}
# 每次都从日志实时取（不缓存），用于"就绪判定 + 取带 token 地址"：
# 避免端口先通、日志后写的竞态导致首开裸地址 401；重启后也能拿到新 token。
function Get-LogHarnessUrl {
    return Get-LogHarnessUrlFromOffset $script:outLogStart
}
function Get-ActiveSessionUrl {
    try {
        if (-not (Test-Path $sessionFile)) { return $null }
        $sess = Get-Content $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $sess -or -not $sess.pid) { return $null }
        $alive = Get-Process -Id ([int]$sess.pid) -ErrorAction SilentlyContinue
        if (-not $alive) { return $null }
        $off = 0L
        if ($null -ne $sess.outLogStart) { $off = [long]$sess.outLogStart }
        return Get-LogHarnessUrlFromOffset $off
    } catch {}
    return $null
}
function Get-ConfiguredPort {
    try { $p = ([uri]$url).Port; if ($p -gt 0) { return $p } } catch {}
    return 3080
}
function Get-HarnessUrl {
    if ($script:harnessUrl) { return $script:harnessUrl }
    $u = Get-LogHarnessUrl
    if ($u) { $script:harnessUrl = $u; return $u }
    return $url
}
function Get-HarnessPort {
    $u = Get-LogHarnessUrl
    if (-not $u) { $u = $url }
    try { $p = ([uri]$u).Port; if ($p -gt 0) { return $p } } catch {}
    return 3080
}

# 单实例保护：托盘只允许一个
$createdNew = $null
$mutex = New-Object System.Threading.Mutex($true, 'Local\dsh-tray-launcher', [ref]$createdNew)
if (-not $createdNew) {
    Write-TrayLog 'another tray instance is running; opening UI and exiting'
    # 只打开当前存活会话日志里带 token 的地址；外部 harness 或过期旧日志宁可不开（避免 401）
    if (-not $NoOpen) {
        $existingUrl = Get-ActiveSessionUrl
        if ($existingUrl) { Start-Process $existingUrl }
        else { Write-TrayLog 'no active session token URL available; skip opening UI (bare or stale URL would 401)' }
    }
    exit 0
}
Write-TrayLog 'tray launcher started'
Write-TrayLog ('dsh-tray-launcher version: ' + $script:TrayVersion)
Write-TrayLog ('node: ' + $node)
Write-TrayLog ('dsh bin: ' + $bin)

# ---- 托盘图标与菜单 ----
# 加载 C# 辅助类型（图案重着色工厂 / 主题检测）；失败时降级为系统默认图标
$themeCs = Join-Path $PSScriptRoot 'lib\TrayTheme.cs'
if (Test-Path $themeCs) {
    try { Add-Type -Path $themeCs -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll') }
    catch { Write-TrayLog ('TrayTheme load failed: ' + $_.Exception.Message) }
}

# 托盘图标固定为 DeepSeek 官方品牌蓝鲸鱼，不支持自定义
$script:brandIconPath = $null

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.SystemIcons]::Application
$tray.Text = 'DeepSeek Harness'
$tray.Visible = $true

# ---- 图标：更新托盘 + 桌面/自启快捷方式 ----
function Update-ShortcutIcon($icoPath) {
    if (-not $icoPath -or -not (Test-Path $icoPath)) { return }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $shortcutPath = Get-CfgValue 'shortcut' ''
        if ($shortcutPath -and (Test-Path $shortcutPath)) {
            $lnk = $ws.CreateShortcut($shortcutPath)
            $lnk.IconLocation = $icoPath + ',0'
            $lnk.Save()
        }
        $name = [System.IO.Path]::GetFileName($shortcutPath)
        if ($name) {
            $autoPath = Join-Path ([Environment]::GetFolderPath('Startup')) $name
            if (Test-Path $autoPath) {
                $lnk2 = $ws.CreateShortcut($autoPath)
                $lnk2.IconLocation = $icoPath + ',0'
                $lnk2.Save()
            }
        }
        Write-TrayLog ('shortcut icon updated: ' + $icoPath)
    } catch {
        Write-TrayLog ('shortcut icon update failed: ' + $_.Exception.Message)
    }
}

# ---- DeepSeek 官方品牌蓝鲸鱼（固定颜色，不随主题变化）----
$script:BrandColor = '#4D6BFE'

function Update-BrandIcon {
    $src = Join-Path $PSScriptRoot 'icons\deepseek.ico'
    $out = Join-Path $script:dataDir 'brand.ico'
    if ((Test-Path $src) -and ('TrayIconFactory' -as [type])) {
        $stale = $true
        if (Test-Path $out) { $stale = ((Get-Item $src).LastWriteTimeUtc -gt (Get-Item $out).LastWriteTimeUtc) }
        if ($stale -and -not [TrayIconFactory]::Build($src, $script:BrandColor, $out)) {
            Write-TrayLog 'brand icon build failed'
            return $false
        }
    }
    if (-not (Test-Path $out)) {
        if (Test-Path $src) { Copy-Item $src $out -Force }
        else { Write-TrayLog 'brand icon source missing'; return $false }
    }
    try {
        $tray.Icon = New-Object System.Drawing.Icon($out)
    } catch {
        Write-TrayLog ('brand icon apply failed: ' + $_.Exception.Message)
        return $false
    }
    $script:brandIconPath = $out
    Update-ShortcutIcon $out
    Write-TrayLog ('brand icon applied: ' + $script:BrandColor)
    return $true
}

# 右下角轻提示。Win11 下未注册通知应用的气泡（ShowBalloonTip）不会显示，
# 这里用自绘小窗保证操作反馈可见；极端情况下再退回系统气泡。
function Show-Toast($text, [int]$ms = 2000) {
    if ('TrayToast' -as [type]) {
        try { [TrayToast]::Popup($text, (Test-SystemUsesLightTheme), $ms); return } catch {}
    }
    try {
        $tray.BalloonTipTitle = 'DeepSeek Harness'
        $tray.BalloonTipText = $text
        $tray.ShowBalloonTip($ms)
    } catch {}
}

# 启动时先落一次图标
[void](Update-BrandIcon)

# ---- 右键菜单 ----
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$menu.ShowImageMargin = $false
$menu.DropShadowEnabled = $true
$menu.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
$script:menuLight = $null

function Add-TrayMenuItem($target, $text) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $item.Padding = New-Object System.Windows.Forms.Padding(4, 3, 14, 3)
    $target.Items.Add($item) | Out-Null
    return $item
}

function Test-SystemUsesLightTheme {
    if ('TrayTheme' -as [type]) {
        try { return [TrayTheme]::IsLightTheme() } catch { return $false }
    }
    return $false
}

# 主题变化时重建渲染器（菜单配色跟随 Windows 深浅色，不重启托盘）
function Update-MenuTheme($force) {
    $light = Test-SystemUsesLightTheme
    if (-not $force -and $null -ne $script:menuLight -and $script:menuLight -eq $light) { return }
    $script:menuLight = $light
    if ('TrayMenuRenderer' -as [type]) { $menu.Renderer = New-Object TrayMenuRenderer($light) }
}

# 勾选状态用文本后缀表示，让选中项一眼可见
function Update-AutostartText {
    if ($script:miAutostart) {
        $script:miAutostart.Text = if ($script:miAutostart.Checked) { '开机自启 ✓' } else { '开机自启' }
    }
}

$miOpen = Add-TrayMenuItem $menu '打开界面'
$miLog  = Add-TrayMenuItem $menu '打开日志'
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 开机自启（勾选 = 启动文件夹里有快捷方式；点击即切换）
function Get-ShortcutPath {
    $p = Get-CfgValue 'shortcut' ''
    if ($p -and (Test-Path $p)) { return $p }
    return $null
}
function Ensure-DesktopShortcut {
    $existing = Get-ShortcutPath
    if ($existing) { return $existing }
    try {
        $name = 'DeepSeek Harness'
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnkPath = Join-Path $desktop ($name + '.lnk')
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($lnkPath)
        $vbs = Join-Path $PSScriptRoot 'launch-hidden.vbs'
        if (Test-Path $vbs) {
            $lnk.TargetPath = (Join-Path $env:SystemRoot 'System32\wscript.exe')
            $lnk.Arguments = '"' + $vbs + '"'
        } else {
            $lnk.TargetPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
            $lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'tray.ps1') + '"'
        }
        $lnk.WorkingDirectory = $PSScriptRoot
        if ($script:brandIconPath -and (Test-Path $script:brandIconPath)) { $lnk.IconLocation = $script:brandIconPath + ',0' }
        $lnk.Description = 'DeepSeek Harness 系统托盘启动器'
        $lnk.WindowStyle = 7
        $lnk.Save()
        Write-TrayLog ('desktop shortcut created: ' + $lnkPath)
        return $lnkPath
    } catch {
        Write-TrayLog ('shortcut creation failed: ' + $_.Exception.Message)
        return $null
    }
}
$script:miAutostart = Add-TrayMenuItem $menu '开机自启'
$script:miAutostart.CheckOnClick = $false
$script:miAutostart.add_Click({
    $shortcutPath = Ensure-DesktopShortcut
    if (-not $shortcutPath) {
        Show-Toast '未找到桌面快捷方式，无法设置开机自启'
        return
    }
    $name = [System.IO.Path]::GetFileName($shortcutPath)
    $startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) $name
    if (Test-Path $startupPath) {
        Remove-Item $startupPath -Force
        $script:miAutostart.Checked = $false
        Update-AutostartText
        Write-TrayLog 'autostart disabled'
        Show-Toast '已关闭开机自启'
    } else {
        Copy-Item $shortcutPath $startupPath -Force
        $script:miAutostart.Checked = $true
        Update-AutostartText
        Write-TrayLog 'autostart enabled'
        Show-Toast '已开启开机自启'
    }
})
# 初始勾选状态：启动文件夹里存在对应快捷方式
$shortcutForCheck = Get-ShortcutPath
if ($shortcutForCheck) {
    $startupCheck = Join-Path ([Environment]::GetFolderPath('Startup')) ([System.IO.Path]::GetFileName($shortcutForCheck))
    $script:miAutostart.Checked = (Test-Path $startupCheck)
}
Update-AutostartText

# 托盘菜单：重启 Harness
$miRestart = Add-TrayMenuItem $menu '重启 Harness'
$miRestart.add_Click({
    Write-TrayLog 'restart requested'
    if (-not $script:spawned) {
        Show-Toast '当前是外部 Harness（非本托盘启动），请在其控制台手动重启'
        return
    }
    $port = Get-HarnessPort
    Stop-Harness
    # 等端口真正释放再拉起，避免 EADDRINUSE
    for ($i = 0; $i -lt 50 -and (Test-PortOpen $port); $i++) { Start-Sleep -Milliseconds 200 }
    $script:harnessUrl = $null
    try {
        Start-HarnessProcess
        # 重启后 token 会更新，旧标签失效：复位 opened，端口就绪后用新 token 打开新页面
        $script:opened = $false
        Show-Toast '正在重启…'
    } catch {
        Write-TrayLog ('restart failed: ' + $_.Exception.Message)
        Show-Toast '重启失败，详见日志'
    }
})
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$miExit = Add-TrayMenuItem $menu '退出'
$tray.ContextMenuStrip = $menu
Update-MenuTheme $true

function Open-HarnessUI {
    if ($script:externalNoToken -and -not $script:harnessUrl) {
        Show-Toast '无法自动获取访问令牌，请在 Harness 原窗口打开它打印的带 ?token= 的地址。'
        return
    }
    Start-Process (Get-HarnessUrl)
}
$miOpen.add_Click({ Open-HarnessUI })
$miLog.add_Click({ Start-Process notepad $outLog })

# ---- 端口探测（纯 .NET，避免加载 NetTCPIP/CIM 模块）----
# 实测：Import-Module NetTCPIP 会让常驻内存 +29MB；托盘每 3 秒轮询一次，
# 用 TcpClient 直连判断端口就绪，既不加载模块也不产生 CIM 对象。
function Test-PortOpen([int]$Port = 3080) {
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(300) -and $client.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}

# ---- 内存回收（GC + 回收工作集）----
# PowerShell 5.1 + WinForms 基线约 75MB，托盘逻辑再叠几十 MB。定期 GC 并把
# 工作集还给系统，让常驻占用回落到实际在用的页（任务管理器读数显著下降）。
function Invoke-MemoryTrim {
    try {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        [void][Win32.K32Mem]::EmptyWorkingSet([Win32.K32Mem]::GetCurrentProcess())
    } catch {}
}

# ---- 停止 Harness ----
# 只停止"本托盘自己拉起"的 harness 进程树；复用外部已运行的 harness 时不动它，
# 避免误杀无关的 dsh 进程（含其它 profile/前端），退出托盘也不影响外部服务。
function Stop-Harness {
    if ($script:spawned -and $script:proc) {
        try {
            if (-not $script:proc.HasExited) {
                & "$env:SystemRoot\System32\taskkill.exe" /PID $script:proc.Id /T /F 2>$null | Out-Null
            }
        } catch {}
        $script:spawned = $false
        Clear-HarnessSession
    } else {
        Write-TrayLog 'external harness is not owned by tray; leaving it running'
    }
    $script:harnessUrl = $null
    Write-TrayLog 'stop requested'
    Invoke-MemoryTrim
}

$miExit.add_Click({
    # 退出 = 全部退出：先停 harness，再关托盘
    Write-TrayLog 'exit requested: stopping harness and closing tray'
    Stop-Harness
    $tray.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})
$tray.add_DoubleClick({ Open-HarnessUI })

# ---- 启动 harness 进程（CreateNoWindow：从 API 层面禁止控制台）----
function Start-HarnessProcess {
    Rotate-Log $outLog
    Rotate-Log $errLog
    # 记录本次启动时输出日志的末尾位置；Get-LogHarnessUrl 只在这之后找新 token
    try { $script:outLogStart = if (Test-Path $outLog) { (Get-Item $outLog).Length } else { 0 } } catch { $script:outLogStart = 0 }
    # 把配置里 url 的端口/主机传给 dsh web，保证监听端口与"就绪判定/打开地址"一致
    $portArg = ''
    $hostArg = ''
    try {
        $u = [uri]$url
        if ($u.Port -gt 0) { $portArg = ' --port ' + $u.Port }
        if ($u.Host) { $hostArg = ' --host ' + $u.Host }
    } catch {}
    # --no-open：dsh web 自己也会打开默认浏览器，若不禁用会与托盘的就绪打开叠加成两个页面
    $cmdLine = '/c ""' + $node + '" "' + $bin + '" web --no-open' + $portArg + $hostArg + ' >> "' + $outLog + '" 2>> "' + $errLog + '" "'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = $cmdLine
    $psi.WorkingDirectory = $cwd
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $script:proc = New-Object System.Diagnostics.Process
    $script:proc.StartInfo = $psi
    [void]$script:proc.Start()
    $script:spawned = $true
    $script:launchTick = $script:tick
    Save-HarnessSession $script:proc.Id $script:outLogStart
    Write-TrayLog ('harness started hidden, pid ' + $script:proc.Id)
}

# ---- 启动 harness（已运行则只挂托盘）----
$script:spawned = $false
$script:proc = $null
$script:externalNoToken = $false
$script:opened = $false
$script:tick = 0
$script:launchTick = 0

if ($AttachOnly) {
    # 插件随 dsh web 启动：绝不二次拉起 harness，仅挂载托盘
    Clear-HarnessSession
    $script:externalNoToken = $true
    Write-TrayLog 'started in AttachOnly mode (hosted by dsh plugin); attached without owning harness'
} else {
    $configuredPort = Get-ConfiguredPort
    $already = Test-PortOpen $configuredPort
    if ($already) {
        $attachUrl = Get-ActiveSessionUrl
        if ($attachUrl) {
            $script:harnessUrl = $attachUrl
            Write-TrayLog ('harness already listening on port ' + $configuredPort + '; tray attached to active session')
            Show-Toast '已在运行'
        } else {
            # 外部已有 harness 在监听，但拿不到它进程内存里的 ?token=，裸地址会 401。
            # 标记 externalNoToken：不自动开浏览器，提示用户用原窗口打印的带 token 地址。
            Clear-HarnessSession
            $script:externalNoToken = $true
            Write-TrayLog ('port ' + $configuredPort + ' already in use but no active session token URL (external harness?); attached without owning it')
            Show-Toast '检测到 Harness 已在运行，但无法自动获取访问令牌。请在其原窗口打开 dsh 打印的带 ?token= 的地址。' 6000
        }
    } else {
        if (-not $node -or -not (Test-Path $node)) {
            [System.Windows.Forms.MessageBox]::Show(
                '未找到 node.exe。' + "`n" +
                '请先安装 Node.js 或重新运行 install.ps1。',
                'DeepSeek Harness') | Out-Null
            $tray.Visible = $false
            $tray.Dispose()
            try { $mutex.ReleaseMutex() } catch {}
            exit 1
        }
        if (-not $bin) {
            [System.Windows.Forms.MessageBox]::Show(
                '未找到 DeepSeek Harness CLI (lib/bin.js)。' + "`n" +
                '请运行 install.ps1 -DshPath <bin.js 路径> 重新安装，或确认已安装 dsh。',
                'DeepSeek Harness') | Out-Null
            $tray.Visible = $false
            $tray.Dispose()
            try { $mutex.ReleaseMutex() } catch {}
            exit 1
        }
        try {
            Start-HarnessProcess
            Show-Toast '正在启动…'
        } catch {
            Write-TrayLog ('start failed: ' + $_.Exception.Message)
            Show-Toast '启动失败，详见日志'
        }
    }
}

# ---- 轮询：端口就绪后打开浏览器；监视退出 ----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({
    $script:tick += 1
    # 主题跟随：每次 tick 比对一次系统深浅色，变化时重建菜单配色（不重启托盘）
    Update-MenuTheme $false
    # 每 20 个 tick（约 1 分钟）回收一次工作集：长跑进程的消息循环 + 轮询会产生
    # 大量短命对象，定期 GC + EmptyWorkingSet 能把常驻读数压回实际在用的量。
    if ($script:tick % 20 -eq 0) { Invoke-MemoryTrim }

    # 就绪判定：优先用日志里带 token 的地址(及其端口)判端口，再打开该地址。
    # 新版 dsh 启动 MCP 后打印 token 可能需要 15s 以上，兜底必须晚于本次启动至少 90s，否则重启/首启会开成裸地址（401）。
    if (-not $NoOpen -and -not $script:opened -and -not $script:externalNoToken) {
        $logUrl = Get-LogHarnessUrl
        $target = $null
        if ($logUrl) {
            $p = 3080
            try { $p = ([uri]$logUrl).Port } catch {}
            if (Test-PortOpen $p) { $target = $logUrl }
        } elseif (($script:tick - $script:launchTick) -ge 30 -and (Test-PortOpen (Get-HarnessPort))) {
            $target = Get-HarnessUrl
        }
        if ($target) {
            $script:opened = $true
            $script:harnessUrl = $target
            Start-Process $target
            # 地址里带 ?token=，属敏感值：日志只记 scheme://host:port
            $shown = $target
            try { $tu = [uri]$target; $shown = $tu.Scheme + '://' + $tu.Host + ':' + $tu.Port } catch {}
            Write-TrayLog ('browser opened: ' + $shown)
        }
    }


    if ($script:spawned -and $script:proc -and $script:proc.HasExited) {
        Write-TrayLog 'harness exited'
        $timer.Stop()
        $script:spawned = $false
        Clear-HarnessSession
        Show-Toast '已停止' 2000
        # 用非阻塞定时器延迟退出，避免 Start-Sleep 堵死 WinForms UI 线程导致轻提示来不及绘制
        $script:exitTimer = New-Object System.Windows.Forms.Timer
        $script:exitTimer.Interval = 2100
        $script:exitTimer.add_Tick({
            $script:exitTimer.Stop()
            $script:exitTimer.Dispose()
            $tray.Visible = $false
            [System.Windows.Forms.Application]::Exit()
        })
        $script:exitTimer.Start()
    }
})
$timer.Start()
# 启动完成即回收一次：WinForms + 图标加载后是常驻内存的峰值点
Invoke-MemoryTrim

# ---- 消息循环 ----
[System.Windows.Forms.Application]::Run()

# ---- 清理 ----
$timer.Stop()
$tray.Visible = $false
$tray.Dispose()
try { $mutex.ReleaseMutex() } catch {}
Write-TrayLog 'tray launcher exited'
