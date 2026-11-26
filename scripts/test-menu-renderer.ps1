# 菜单渲染器测试：深浅两套配色与品牌蓝悬停色
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cs = Join-Path $root 'lib\TrayTheme.cs'
if (-not (Test-Path $cs)) { throw '缺少 lib\TrayTheme.cs' }
Add-Type -Path $cs -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll')

if (-not ('TrayMenuRenderer' -as [type])) { throw 'TrayMenuRenderer 类型不存在' }

$light = New-Object TrayMenuRenderer($true)
$dark  = New-Object TrayMenuRenderer($false)

# 浅色主题：浅底深字
if ($light.BackColor.R -lt 200) { throw ('浅色主题背景过深: ' + $light.BackColor) }
if ($light.TextColor.R -gt 100) { throw ('浅色主题文字过浅: ' + $light.TextColor) }

# 深色主题：深底浅字
if ($dark.BackColor.R -gt 100) { throw ('深色主题背景过浅: ' + $dark.BackColor) }
if ($dark.TextColor.R -lt 180) { throw ('深色主题文字过深: ' + $dark.TextColor) }

# 悬停高亮为品牌蓝 #4D6BFE
if ($light.HoverColor.R -ne 0x4D -or $light.HoverColor.G -ne 0x6B -or $light.HoverColor.B -ne 0xFE) {
    throw ('悬停色错误: ' + $light.HoverColor)
}
if ($dark.HoverColor.R -ne 0x4D -or $dark.HoverColor.G -ne 0x6B -or $dark.HoverColor.B -ne 0xFE) {
    throw ('悬停色错误(dark): ' + $dark.HoverColor)
}

Write-Output 'PASS: menu renderer'
