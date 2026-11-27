# dsh 路径解析测试：覆盖 npm / pnpm / yarn shim、引号路径、目录路径
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$installSrc = Get-Content (Join-Path $root 'install.ps1') -Raw -Encoding UTF8

# 从 install.ps1 提取 Resolve-DshFromShim 与 Resolve-DshFromPath 定义并加载
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($installSrc, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw ("install.ps1 parse error: " + $errors[0].Message) }
$funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Resolve-DshFromShim', 'Resolve-DshFromPath') }, $true)
if ($funcs.Count -ne 2) { throw ('Expected 2 resolver functions, found ' + $funcs.Count) }
foreach ($fn in $funcs) { Invoke-Expression $fn.Extent.Text }

$tmp = Join-Path $env:TEMP ('dsh-resolve-test-' + [guid]::NewGuid().ToString('N'))
try {
    # 1) 模拟 pnpm 全局布局（%dp0%\global\5\node_modules\@deepseek-ai\dsh\lib\bin.js）
    $pnpmBin = Join-Path $tmp 'pnpm'
    $pnpmTarget = Join-Path $pnpmBin 'global\5\node_modules\@deepseek-ai\dsh\lib\bin.js'
    New-Item -ItemType Directory -Path (Split-Path $pnpmTarget -Parent) -Force | Out-Null
    Set-Content -Path $pnpmTarget -Value '// pnpm bin' -Encoding UTF8
    $pnpmShim = Join-Path $pnpmBin 'dsh.cmd'
    Set-Content -Path $pnpmShim -Value ("@ECHO off`r`n`"%_prog%`" `"%dp0%\global\5\node_modules\@deepseek-ai\dsh\lib\bin.js`" %*") -Encoding ASCII
    $r1 = Resolve-DshFromShim $pnpmShim
    if ($r1 -ne $pnpmTarget) { throw "pnpm shim 解析失败: got '$r1', expected '$pnpmTarget'" }

    # 1b) 模拟 PowerShell .ps1 shim（$basedir/global/5/node_modules/@deepseek-ai/dsh/lib/bin.js）
    $ps1Shim = Join-Path $pnpmBin 'dsh.ps1'
    Set-Content -Path $ps1Shim -Value '& "$basedir/global/5/node_modules/@deepseek-ai/dsh/lib/bin.js" $args' -Encoding UTF8
    $r1b = Resolve-DshFromShim $ps1Shim
    if ($r1b -ne $pnpmTarget) { throw "ps1 shim 解析失败: got '$r1b', expected '$pnpmTarget'" }

    # 2) 模拟 yarn 全局布局（%~dp0\..\Data\global\node_modules\@deepseek-ai\dsh\lib\bin.js）
    $yarnBin = Join-Path $tmp 'Yarn\bin'
    $yarnTarget = Join-Path $tmp 'Yarn\Data\global\node_modules\@deepseek-ai\dsh\lib\bin.js'
    New-Item -ItemType Directory -Path $yarnBin -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $yarnTarget -Parent) -Force | Out-Null
    Set-Content -Path $yarnTarget -Value '// yarn bin' -Encoding UTF8
    $yarnShim = Join-Path $yarnBin 'dsh.cmd'
    Set-Content -Path $yarnShim -Value '"%~dp0\..\Data\global\node_modules\@deepseek-ai\dsh\lib\bin.js" %*' -Encoding ASCII
    $r2 = Resolve-DshFromShim $yarnShim
    if ($r2 -ne $yarnTarget) { throw "yarn shim 解析失败: got '$r2', expected '$yarnTarget'" }

    # 3) 带双引号的 bin.js 路径（模拟 Windows 复制文件地址 / 拖拽）
    $r3 = Resolve-DshFromPath ('"' + $pnpmTarget + '"')
    if ($r3 -ne $pnpmTarget) { throw "引号路径解析失败: got '$r3'" }

    # 4) 拖入目录（@deepseek-ai\dsh 目录或 shim 所在目录）
    $r4 = Resolve-DshFromPath (Split-Path (Split-Path $pnpmTarget -Parent) -Parent)
    if ($r4 -ne $pnpmTarget) { throw "包目录解析失败: got '$r4'" }
    $r5 = Resolve-DshFromPath $pnpmBin
    if ($r5 -ne $pnpmTarget) { throw "shim 目录解析失败: got '$r5'" }

    Write-Output 'PASS: dsh resolve'
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
