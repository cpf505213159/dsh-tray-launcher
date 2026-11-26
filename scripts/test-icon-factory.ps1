# 图标工厂测试：生成 ICO、校验尺寸集合、校验着色
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$cs = Join-Path $root 'lib\TrayTheme.cs'
if (-not (Test-Path $cs)) { throw "缺少 lib\TrayTheme.cs（预期先失败）" }
Add-Type -Path $cs -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll')

$src = Join-Path $root 'icons\deepseek.ico'
$outWhite = Join-Path $env:TEMP 'tray-test-white.ico'
$outBlack = Join-Path $env:TEMP 'tray-test-black.ico'

function Read-IcoEntries([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    $n = [BitConverter]::ToUInt16($b, 4)
    $list = @()
    for ($i = 0; $i -lt $n; $i++) {
        $o = 6 + $i * 16
        $w = if ($b[$o] -eq 0) { 256 } else { [int]$b[$o] }
        $size = [BitConverter]::ToInt32($b, $o + 8)
        $off = [BitConverter]::ToInt32($b, $o + 12)
        $data = New-Object byte[] $size
        [Array]::Copy($b, $off, $data, 0, $size)
        $list += [pscustomobject]@{ Width = $w; Bytes = $data }
    }
    return $list
}

function Get-OpaqueColors($pngBytes) {    $ms = New-Object IO.MemoryStream(,$pngBytes)
    $bmp = New-Object System.Drawing.Bitmap($ms)
    $colors = @{}
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.A -gt 200) { $colors[('{0},{1},{2}' -f $c.R, $c.G, $c.B)] = $true }
        }
    }
    $bmp.Dispose(); $ms.Dispose()
    return ,@($colors.Keys)
}

# --- 白色 ---
if (-not [TrayIconFactory]::Build($src, '#FFFFFF', $outWhite)) { throw 'Build(white) 返回 false' }
$entries = Read-IcoEntries $outWhite
$sizes = ($entries | ForEach-Object { $_.Width } | Sort-Object) -join ','
if ($sizes -ne '16,32,48,64,256') { throw "尺寸集合错误: $sizes" }
$small = ($entries | Where-Object { $_.Width -eq 32 }).Bytes
$cols = Get-OpaqueColors $small
if ($cols.Count -ne 1 -or $cols[0] -ne '255,255,255') { throw "白色着色错误: $($cols -join ' | ')" }

# --- 黑色 ---
if (-not [TrayIconFactory]::Build($src, '#000000', $outBlack)) { throw 'Build(black) 返回 false' }
$entries = Read-IcoEntries $outBlack
$small = ($entries | Where-Object { $_.Width -eq 32 }).Bytes
$cols = Get-OpaqueColors $small
if ($cols.Count -ne 1 -or $cols[0] -ne '0,0,0') { throw "黑色着色错误: $($cols -join ' | ')" }

# --- 颜色格式容错 ---
if (-not [TrayIconFactory]::Build($src, '4D6BFE', $outWhite)) { throw 'Build(无#前缀) 失败' }

Remove-Item $outWhite, $outBlack -ErrorAction SilentlyContinue
Write-Output 'PASS: icon factory'
