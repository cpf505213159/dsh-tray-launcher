# dsh-tray-launcher

<p align="center">
  <img src="https://img.shields.io/github/stars/cpf505213159/dsh-tray-launcher?style=flat-square&cacheSeconds=300" alt="Stars">
  &nbsp;
  <img src="https://img.shields.io/npm/v/dsh-tray-launcher?style=flat-square" alt="npm">
  &nbsp;
  <img src="https://img.shields.io/npm/dm/dsh-tray-launcher?style=flat-square" alt="Downloads">
  &nbsp;
  <img src="https://img.shields.io/github/license/cpf505213159/dsh-tray-launcher?style=flat-square" alt="License">
  &nbsp;
  <img src="https://img.shields.io/github/last-commit/cpf505213159/dsh-tray-launcher?style=flat-square" alt="Last Commit">
</p>

<p align="center">
  <strong>DeepSeek Harness 的 Windows 桌面托盘启动器</strong><br>
  <em>双击快捷方式无窗口启动 dsh web · 系统托盘常驻 · 退出即全退 · 双击安装包即装</em>
</p>

<div align="center">

[是什么](#是什么) · [功能特性](#功能特性) · [界面预览](#界面预览) · [快速开始](#快速开始) · [使用](#使用) · [配置](#配置) · [卸载](#卸载) · [常见问题](#常见问题) · [已知限制](#已知限制)

</div>

## 是什么

DeepSeek Harness（dsh）默认在终端里前台运行 `dsh web`——必须留着一个 cmd/PowerShell 窗口，误关窗口服务就没了。本工具把它变成**一个标准的 Windows 托盘应用**：双击桌面快捷方式，无任何窗口弹出，托盘出现图标，harness 就绪后自动打开浏览器；托盘菜单管理界面与日志，「退出」即完整停止（先停 harness、再关托盘，不留后台残留）。

> 默认作为 dsh 在 Windows 上的独立桌面托盘启动/常驻工具运行（不改 dsh 源码，不接管 dsh 的升级与多 profile 能力，卸载即还原）；同时包内也附带可选的 Cordis 插件入口（`src/plugin.js`），便于通过 `dsh plugin add` 让托盘随 Harness 自动挂载。

| | 终端直跑 `dsh web` | 本工具（托盘） |
| --- | --- | --- |
| 启动方式 | 手动开终端敲命令 | 双击桌面快捷方式 |
| 窗口 | cmd 常驻（误关即停） | 无窗口，托盘图标常驻 |
| 打开界面 | 手动敲浏览器地址 | 端口就绪自动打开 |
| 停止方式 | Ctrl+C / 关窗口 | 托盘右键「退出」（全退） |
| 日志 | 窗口里翻 | 落盘 + 托盘菜单一键打开 |
| 重复启动 | 端口冲突报错 | 单实例锁，自动唤起已有界面 |

> 对比桌面壳（Electron/Tauri 打包的桌面客户端）：优势在**体积与干净度**——几十 KB 的 PowerShell 脚本 + 一个图标，无需下载运行时、没有安装包，harness 一关托盘即退，不留后台进程。内存经 v1.5.0 优化后实测 **55MB 工作集 / 84MB 私有提交**（此前 168MB），与 Electron 桌面壳同级或更低。

## 功能特性

- 🪶 **低占用**：纯 PowerShell（核心脚本约 30KB）+ 一行 VBS，不下载 Electron/运行时、不写注册表、不驻留更新器。**v1.5.0 内存优化**：端口探测改纯 .NET（不再加载 NetTCPIP 模块 −29MB），GC + `EmptyWorkingSet` 定期归还工作集，实测 168MB → **55MB**（−67%）
- 🔐 **适配新版鉴权 Web UI**：dsh ≥0.1.7 的 Web UI 需要带 `?token=` 的地址打开，托盘自动从 harness 输出里取带 token 的地址（旧版无 token 时自动退回裸地址）
- 🚫 **无窗口启动**：不弹 cmd/控制台，harness 后台运行，stdout/stderr 落盘日志
- 🖥️ **系统托盘常驻**：托盘图标 + 右下角轻提示（正在启动 / 已在运行 / 已停止），harness 意外退出自动收起
- 👆 **托盘菜单**：打开界面 / 打开日志 / 开机自启 / 重启 Harness / 退出（= 停止 harness + 关托盘）；双击图标 = 打开界面
- 🌐 **就绪自动开浏览器**：后台轮询端口，harness 一监听就自动打开 Web GUI
- 🔒 **单实例保护**：互斥锁 + 端口检测，重复双击快捷方式不会重复启动，只会唤起界面
- 🔍 **自动定位 dsh**：配置文件 → npm 全局 → npx 缓存逐级探测，找不到才报错；也可手动指定
- 🎨 **品牌蓝鲸鱼图标**：托盘与桌面快捷方式使用 DeepSeek 官方品牌蓝 `#4D6BFE` 的鲸鱼图标，深色/浅色任务栏都清晰可见
- 🚀 **可选开机自启**：安装时 `-Autostart` 注册；也可随时在托盘右键「开机自启」一键开关
- 🧩 **可作 dsh 插件安装**：`dsh plugin add dsh-tray-launcher` 后托盘随 Harness 自动启动/退出，状态文件存 `%DSH_HOME%\dsh-tray`（详见下方「作为 dsh 插件安装」）
- 🩺 **控制台模式兜底**：`launch.bat` 前台运行、日志直出窗口，排查问题时用

## 界面预览

桌面快捷方式 → 无窗口启动 → 托盘图标常驻（右键菜单：打开界面 / 打开日志 / 开机自启 / 重启 Harness / 退出），harness 就绪自动打开浏览器；右键菜单配色跟随 Windows 深浅主题。

## 快速开始

### 系统要求

- Windows 10 / 11
- Windows PowerShell 5.1（系统自带，无需安装）
- 已安装 DeepSeek Harness CLI（`dsh web` 可正常启动）与 Node.js（dsh 自身要求 ≥ 22，安装本工具需要 ≥ 18）

### 双击安装（推荐，零命令）

1. 打开 <https://github.com/cpf505213159/dsh-tray-launcher>，点绿色 **Code → Download ZIP**，解压到任意位置
2. 双击解压目录里的 **`安装.bat`**
3. 看到 `[OK] Installation finished.` 后按任意键关闭窗口；桌面会多出「DeepSeek Harness」快捷方式
4. 以后双击这个快捷方式即可启动（无窗口，图标出现在托盘）

> 只拿到 `安装.bat` 这一个文件也没关系：双击它，会自动从 GitHub 下载安装器并完成安装（需要能上网）。

### npm 全局安装（备选，版本可能落后于 GitHub）

```powershell
npm install -g dsh-tray-launcher
dsh-tray-install
```

npm 上发布的是较早版本，想要本仓库的最新修复请用上面的双击安装或从仓库安装。

安装器会自动检测 dsh 与 node 位置，**安装前会列出将执行的操作并询问确认**（回车 = 继续，输入 n 取消）；找不到 dsh 时会提示你粘贴 `bin.js` 路径，也可用 `dsh-tray-install -DshPath "<bin.js 路径>"` 手动指定。自动化场景用 `-Yes` 跳过确认。

之后日常使用：

```powershell
dsh-tray
dsh-tray --console
```

`dsh-tray` 为托盘模式（无窗口），`dsh-tray --console` 为控制台模式（日志直出终端）。

### 作为 dsh 插件安装（托盘随 Harness 启动）

```powershell
dsh plugin --profile web add dsh-tray-launcher
```

包内自带 dsh 插件半体（`src/plugin.js` + `cordis.patch.yml`）：Windows 上 `dsh web` 启动时自动以无窗口方式拉起托盘图标，Harness 退出时随之关闭；已由桌面快捷方式启动的托盘会被全局互斥锁去重，不会重复出现。此方式下配置与日志保存在 `%DSH_HOME%\dsh-tray`，不写入 node_modules。非 Windows 平台自动跳过。

### 一行命令远程安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $f=Join-Path $env:TEMP 'dshtray-install.ps1'; irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/install.ps1' -OutFile $f; & $f"
```

安装器自动检测 dsh 与 node 位置，**安装前会列出将执行的操作并询问确认**（回车 = 继续，输入 n 取消）；找不到 dsh 时会提示你粘贴 `bin.js` 路径，也可用 `dsh-tray-install -DshPath "<bin.js 路径>"` 手动指定。自动化场景用 `-Yes` 跳过确认。

### 从仓库安装

```powershell
git clone https://github.com/cpf505213159/dsh-tray-launcher.git
cd dsh-tray-launcher
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

### 安装参数

| 参数 | 说明 |
| --- | --- |
| `-DshPath <路径>` | 手动指定 dsh CLI 入口（`@deepseek-ai/dsh/lib/bin.js`），自动检测失败时使用 |
| `-ShortcutName <名称>` | 桌面快捷方式名称，默认 `DeepSeek Harness` |
| `-Autostart` | 同时注册开机自启（复制快捷方式到启动文件夹） |
| `-Yes` | 跳过安装前的确认提示（自动化场景） |
| `-DryRun` | 只检测和打印，不写入任何文件 |

示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Autostart
```

## 使用

| 操作 | 效果 |
| --- | --- |
| `dsh-tray`（或双击桌面快捷方式） | 无窗口启动；托盘出图标 + 右下角提示；端口就绪自动开浏览器 |
| `dsh-tray --console`（或双击 `launch.bat`） | 控制台模式，前台运行、日志直出终端 |
| 双击托盘图标 | 打开界面 |
| 托盘「打开界面」 | 浏览器打开 Web GUI |
| 托盘「打开日志」 | 记事本打开 stdout 日志 |
| 托盘「重启 Harness」 | 停止并重新拉起 dsh web（无窗口），就绪后自动重开浏览器；仅对**本托盘拉起**的 harness 生效，挂载外部 harness 时会提示到原控制台重启 |
| 托盘「开机自启」 | 勾选状态 = 是否已注册开机自启；点击即切换（自动创建/删除启动文件夹里的快捷方式，右下角提示结果） |
| 托盘「退出」 | 停止 harness + 关闭托盘（全部退出） |
| harness 意外退出 | 右下角提示「已停止」并自动收起托盘 |

## 配置

安装器在安装目录（`%LOCALAPPDATA%\Programs\DSHTray\`）生成 `dsh-tray.config.json`，全部字段可选：

```json
{
  "dshBin":   "C:\\...\\node_modules\\@deepseek-ai\\dsh\\lib\\bin.js",
  "node":     "C:\\Program Files\\nodejs\\node.exe",
  "url":      "http://127.0.0.1:3080",
  "shortcut": "C:\\Users\\<you>\\Desktop\\DeepSeek Harness.lnk",
  "cwd":      "C:\\Users\\<you>"
}
```

| 字段 | 说明 |
| --- | --- |
| `shortcut` | 桌面快捷方式路径；托盘用它同步快捷方式图标，并作为「开机自启」开关的开关对象 |

`dshBin` / `node` 缺省时按「npm 全局 → npx 缓存 → PATH → 常见路径」顺序自动探测。日志写在安装目录 `logs\` 下（`dsh-out.log` / `dsh-err.log` / `dsh-tray.log`）。

## 卸载

**双击卸载（推荐）**：双击仓库目录里的 **`卸载.bat`**，按任意键关闭即可。

**命令行卸载**（本地脚本或远程执行）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

远程执行（未安装本仓库时）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $f=Join-Path $env:TEMP 'dshtray-uninstall.ps1'; irm 'https://raw.githubusercontent.com/cpf505213159/dsh-tray-launcher/main/uninstall.ps1' -OutFile $f; & $f"
```

会自动：结束托盘进程 → 删除桌面快捷方式（含开机自启副本）→ 删除安装目录 `%LOCALAPPDATA%\Programs\DSHTray\`。

npm 方式安装的再执行：`npm uninstall -g dsh-tray-launcher`

## 常见问题

<details>
<summary><strong>托盘图标看不到？</strong></summary>

Windows 会把不常用的新图标收进通知区「^」折叠区，点开小箭头看看，或把图标拖到常显区。
</details>

<details>
<summary><strong>重复点快捷方式会开两个 harness 吗？</strong></summary>

不会。托盘脚本带单实例互斥锁，第二个实例只会唤起已有界面后退出。
</details>

<details>
<summary><strong>报「未找到 dsh CLI」？</strong></summary>

用 `install.ps1 -DshPath <bin.js 路径>` 重新安装并手动指定；`bin.js` 一般在 `node_modules\@deepseek-ai\dsh\lib\bin.js`。
</details>

<details>
<summary><strong>harness 更新后路径变了？</strong></summary>

重跑安装器即可，自动重新探测 dsh 位置并更新配置。
</details>

<details>
<summary><strong>退出托盘后 harness 还在跑？</strong></summary>

点的是「退出」才会**停止 harness 并退出托盘**（全退）。如果你之前手动结束过托盘进程、或在旧版本里用过「退出托盘」语义，请确认用的是当前版本菜单里的「退出」。
</details>

## 已知限制

- 「退出 / 重启」只会结束**本托盘自己拉起**的 harness 进程树（`taskkill /T`）；对已在运行的外部 harness 只挂载不动它，避免误杀其它 profile 或前端服务
- 外部 harness（例如先手动跑了 `dsh web`）的 `?token=` 只存在它的进程/终端里，托盘无法读到，因此不会自动打开浏览器；请在原窗口用带 token 的地址访问
- 单实例互斥锁在**同一用户会话**内有效；不同用户/会话可各开一套
- 端口检测用 .NET `TcpClient` 直连 `127.0.0.1:3080`（不加载 NetTCPIP 模块）；监听端口由 dsh 自身配置决定，本工具只负责按该端口检测
- 仓库随附的图标形状源：DeepSeek 鲸鱼 logo 为 DeepSeek 官方标识，仅作图标随工具分发，若版权方要求移除，开 issue 将立即处理
- 本工具只负责启动/常驻，不接管 dsh 的升级、多 profile 等能力

## 许可

MIT © 2026 fancr-code

## 致谢

托盘形态与无窗口化思路参考了社区各类 dsh 桌面工具的实践；图标形状源为 DeepSeek 官方鲸鱼 logo（见「已知限制」）。
