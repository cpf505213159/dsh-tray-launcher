# 主题检测测试：断言返回布尔、注册表键缺失时安全回退、图标颜色映射正确
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cs = Join-Path $root 'lib\TrayTheme.cs'
if (-not (Test-Path $cs)) { throw '缺少 lib\TrayTheme.cs' }
Add-Type -Path $cs -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll')

$isLight = [TrayTheme]::IsLightTheme()
if ($isLight -isnot [bool]) { throw ('IsLightTheme 返回类型错误: ' + $isLight.GetType().Name) }

# 注册表键缺失（精简版 Windows / 非中文品牌机）不得抛错
$missing = [TrayTheme]::IsLightTheme('Software\NoSuchVendorKey\NoSuchSubKey')
if ($missing -ne $false) { throw '注册表键缺失应回退 false' }

if ([TrayTheme]::IconColor($true) -ne '#000000') { throw '浅色主题图标应为 #000000' }
if ([TrayTheme]::IconColor($false) -ne '#FFFFFF') { throw '深色主题图标应为 #FFFFFF' }

Write-Output ('PASS: theme icon (current light=' + $isLight + ')')
