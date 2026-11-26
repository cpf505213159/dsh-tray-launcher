# 轻提示窗测试：能显示、能在超时后自动关闭
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $root 'lib\TrayTheme.cs') -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll')

if (-not ('TrayToast' -as [type])) { throw 'TrayToast 类型不存在' }

[TrayToast]::Popup('测试提示', $false, 500)
[System.Windows.Forms.Application]::DoEvents()
if ([System.Windows.Forms.Application]::OpenForms.Count -lt 1) { throw '提示窗未显示' }

$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 1600) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 40
}
if ([System.Windows.Forms.Application]::OpenForms.Count -ne 0) { throw '提示窗未自动关闭' }

Write-Output 'PASS: toast'
