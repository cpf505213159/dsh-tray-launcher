# 托盘主题自适应图标与菜单美化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让托盘图标随 Windows 深浅主题自动变白/变黑，并重做右键菜单配色与布局；移除梁祖、鲸鱼娘图标。

**Architecture:** 全部改动集中在 `tray.ps1`（PowerShell 5.1 + WinForms）。用 Add-Type 内联两个 C# 辅助类：`TrayIconFactory`（读取 `icons/deepseek.ico` 的 PNG 帧、按目标色重着色、组装 PNG-ICO）和 `TrayMenuRenderer`（深/浅两套配色的 ToolStripRenderer）。主题值通过 .NET 注册表 API 读取，复用现有 3 秒 tick 轮询比对。

**Tech Stack:** PowerShell 5.1, .NET WinForms, System.Drawing, GDI+, ICO(PNG-compressed) 容器。

**Spec:** `docs/superpowers/specs/2026-11-26-tray-theme-icon-design.md`

## Global Constraints

- `tray.ps1` / `install.ps1` / `uninstall.ps1` 必须保持 UTF-8 BOM（`node scripts/check-bom.mjs` 必须通过）。
- 只用 PowerShell 5.1 与内置 .NET 程序集，不新增 npm/二进制依赖。
- 不改变启动、重启、浏览器打开与外部 harness 挂载逻辑。
- 深色图标 `#FFFFFF`、浅色图标 `#000000`、悬停高亮 `#4D6BFE`。
- 主题切换后不重启托盘，3 秒内生效。

## Review Focus

- 浅色主题下若菜单仍是深色文字/深色底，属于严重回归（任务 3 的测试覆盖）。
- 生成的 ICO 若无 16/32 尺寸，托盘会显示模糊（任务 1 的尺寸断言覆盖）。
- 自定义图标模式下切主题不得覆盖用户图标（任务 4 的测试覆盖）。
- 注册表键缺失（精简版 Windows）时不得报错退出（任务 2 的容错测试覆盖）。
- 删除梁祖/鲸鱼娘后，任何代码路径仍引用它们即崩溃（任务 5 的 grep 断言覆盖）。

---

### Task 1: 图标着色与 ICO 生成工厂

**Files:**
- Modify: `tray.ps1`（顶部 Add-Type 区块新增 `TrayIconFactory`）
- Create: `scripts/test-icon-factory.ps1`

**Interfaces:**
- Produces: `[TrayIconFactory]::Build(sourceIco, rgbHex, outIco)` → 返回 bool；`[TrayIconFactory]::MakeIcon(sourceIco, rgbHex)` → 返回 `System.Drawing.Icon`。

- [ ] **Step 1: 写验证脚本（失败）**

`scripts/test-icon-factory.ps1`：
```powershell
# 断言：生成的 ICO 含 16/32/48/64/256 五尺寸，且指定像素为纯白/纯黑
$out = Join-Path $env:TEMP 'tf-test.ico'
if (-not [TrayIconFactory]::Build($src, '#FFFFFF', $out)) { throw 'Build failed' }
# 解析 ICO 目录，断言尺寸集合
# 用 Bitmap 从 32x32 条目解码，采样不透明像素，断言 R=G=B=255
```

- [ ] **Step 2: 运行脚本确认失败**

Run: `powershell -NoProfile -File scripts/test-icon-factory.ps1`
Expected: FAIL（`TrayIconFactory` 类型不存在）

- [ ] **Step 3: 在 tray.ps1 实现 `TrayIconFactory`**

职责：解析源 ICO 目录 → 对每个 PNG 条目解码 → 逐像素 `Color.FromArgb(a, R, G, B)` → 编码 PNG → 写 ICONDIR/ICONDIRENTRY → 输出。BMP 条目原样拷贝（兼容非 PNG 源）。

- [ ] **Step 4: 运行脚本确认通过**，并人工导出 32px 预览目视为白色鲸鱼。

- [ ] **Step 5: Commit**

`git add tray.ps1 scripts/test-icon-factory.ps1 && git commit -m "feat: add themeable icon factory"`

---

### Task 2: 主题检测与图标切换

**Files:**
- Modify: `tray.ps1`（图标解析区、tick 区）

**Interfaces:**
- Consumes: `TrayIconFactory::Build/MakeIcon`（Task 1）
- Produces: `Test-SystemUsesLightTheme()` → bool；`Update-AutoIcon()` → 重建并应用图标；`$script:iconMode`（`'auto'`/路径）。

- [ ] **Step 1: 写失败测试**：`scripts/test-theme-icon.ps1` 断言 `Test-SystemUsesLightTheme` 返回布尔且在注册表键缺失时返回 `$false` 不抛错。

- [ ] **Step 2: 运行确认失败。**

- [ ] **Step 3: 实现**
  - `Test-SystemUsesLightTheme`：`[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize')`，`GetValue('SystemUsesLightTheme', 1)`，`try/catch` 返回 `$false`。
  - `Update-AutoIcon`：根据主题选 `#FFFFFF`/`#000000`，调用工厂生成 `dataDir\auto-light.ico|auto-dark.ico`（已存在且源未变可复用），设置 `$tray.Icon`，更新快捷方式图标。
  - 启动时若 `iconMode -eq 'auto'` 调用一次；tick 中每 3 秒比对主题值，变化时调用。

- [ ] **Step 4: 运行测试 + 手动切换系统主题观察图标（黑↔白）。**

- [ ] **Step 5: Commit**

`git commit -m "feat: follow Windows theme for tray icon"`

---

### Task 3: 菜单渲染器与美化

**Files:**
- Modify: `tray.ps1`（Add-Type 新增 `TrayMenuRenderer`；菜单创建区）

**Interfaces:**
- Produces: `[TrayMenuRenderer]` 构造参数 `(bool light)`；`$menu.Renderer = New-Object TrayMenuRenderer((Test-SystemUsesLightTheme))`。

- [ ] **Step 1: 写失败测试**：`scripts/test-menu-renderer.ps1` 断言 `TrayMenuRenderer` 类型存在，且 `light=$true` 时 `TextColor` 为深色、`light=$false` 时 `TextColor` 为浅色。

- [ ] **Step 2: 运行确认失败。**

- [ ] **Step 3: 实现渲染器**
  - 重写 `OnRenderToolStripBackground`、`OnRenderMenuItemBackground`（悬停/选中 `#4D6BFE`）、`OnRenderItemText`、`OnRenderSeparator`、`OnRenderArrow`。
  - 设置 `menu.Padding`、`menu.Font`（微软雅黑 9pt）、`ShowImageMargin`。
  - 主题切换时重建 renderer。

- [ ] **Step 4: 运行测试 + 截图托盘菜单目视（深/浅两套）。**

- [ ] **Step 5: Commit**

`git commit -m "feat: themed menu renderer"`

---

### Task 4: 菜单结构与图标模式

**Files:**
- Modify: `tray.ps1`（`$script:PresetIcons`/`PresetLabels`/`Resolve-IconPath`/`Apply-Icon`/菜单构建）

**Interfaces:**
- Consumes: `Update-AutoIcon`（Task 2）、`TrayMenuRenderer`（Task 3）
- Produces: `$script:iconMode` 持久化到 config `icon` 字段（`'auto'` 或绝对路径）。

- [ ] **Step 1: 写失败测试**：`scripts/test-icon-mode.ps1` 断言 config 值为 `'auto'` 时解析为自动模式；自定义路径不存在时回退 `'auto'`。

- [ ] **Step 2: 运行确认失败。**

- [ ] **Step 3: 实现**
  - 删除 `PresetIcons`/`PresetLabels` 的梁祖、鲸鱼娘条目，仅保留 `'auto'`。
  - 菜单：`打开界面`、`打开日志`、分隔、`图标`（`自动适配主题` 勾选项 + `自定义…`）、`开机自启`、分隔、`重启 Harness`、`退出`。
  - 移除切换图标气泡；预设切换时仅更新快捷方式图标。
  - 自定义图标保存到 `dataDir\custom.ico`，config 存绝对路径；切主题不覆盖。

- [ ] **Step 4: 运行测试 + 手动点菜单位项验证。**

- [ ] **Step 5: Commit**

`git commit -m "feat: simplified icon menu with auto theme mode"`

---

### Task 5: 清理资源与安装链路

**Files:**
- Delete: `icons/liangzu.ico`, `icons/whale-girl.ico`, `liangzu-icon.ico`, `docs/liangzu-icon.png`, `docs/whale-girl.png`
- Modify: `install.ps1`, `package.json`, `README.md`, `docs/preview-tray.png` references

- [ ] **Step 1: grep 断言**：`grep -rn "liangzu\|whale-girl\|梁祖\|鲸鱼娘" tray.ps1 install.ps1 package.json README.md` 应无结果。
- [ ] **Step 2: 删除文件并更新 install.ps1**
  - `-Icon` 参数保留（自定义路径）；默认图标模式写 `auto`。
  - 快捷方式图标用安装时主题对应的生成图标。
  - `package.json` files 去掉两个 ico，保留 `icons/deepseek.ico`。
  - README 移除两个预设的描述，说明自动适配。
- [ ] **Step 3: 运行 `node scripts/check-bom.mjs` + 语法解析 + DryRun 安装。**
- [ ] **Step 4: Commit**

`git commit -m "chore: drop legacy icon presets"`

---

### Task 6: 集成验证与发布

- [ ] **Step 1: 全量校验**：BOM、语法、三个测试脚本、`install.ps1 -DryRun`。
- [ ] **Step 2: 重装并启动**：确认单页面、图标可见、菜单渲染正常。
- [ ] **Step 3: 主题切换实测**：切系统深/浅色，3 秒内图标变色、菜单变配色。
- [ ] **Step 4: 提交并推送** `origin/main`。

## Self-Review

- Spec 覆盖：图标着色(T1)、主题跟随(T2)、菜单美化(T3)、自定义图标保留(T4)、删除资源(T5)、快捷方式图标(T4/T5)。
- 类型一致：`TrayIconFactory`、`TrayMenuRenderer`、`Test-SystemUsesLightTheme`、`Update-AutoIcon`、`$script:iconMode` 全文统一。
- Review Focus 五项均已分配到对应任务的测试步骤。
