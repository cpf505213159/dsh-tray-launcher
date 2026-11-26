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

# 菜单项图标：16x16 且确实画上了像素
foreach ($kind in @('Open', 'Log', 'Restart', 'Exit', 'Palette', 'Power')) {
    $bmp = [TrayGlyphs]::Get([TrayGlyph]$kind, [System.Drawing.Color]::White)
    if ($bmp.Width -ne 16 -or $bmp.Height -ne 16) { throw ($kind + ' 图标尺寸错误: ' + $bmp.Width + 'x' + $bmp.Height) }
    $painted = 0
    for ($y = 0; $y -lt 16; $y++) { for ($x = 0; $x -lt 16; $x++) { if ($bmp.GetPixel($x, $y).A -gt 0) { $painted++ } } }
    if ($painted -lt 8) { throw ($kind + ' 图标几乎没有像素: ' + $painted) }
    $bmp.Dispose()
}

Write-Output 'PASS: menu renderer'
