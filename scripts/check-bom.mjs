// BOM / 编码守卫。
//
// 为什么需要：托盘由 Windows PowerShell 5.1 启动（wscript → powershell.exe -File）。
// 5.1 读取**没有 BOM** 的 UTF-8 .ps1 时会按系统 ANSI 代码页（中文系统 = GBK）解码，
// 于是脚本里的中文变成乱码、引号被拆坏，语法直接解析失败——托盘静默启动不了。
// 这个坑真实发生过（v1.5.0 发布版就踩了），所以用 CI 钉住：所有 .ps1 必须带 UTF-8 BOM。
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const scripts = ["tray.ps1", "install.ps1", "uninstall.ps1"];
const batFiles = ["安装.bat", "卸载.bat", "launch.bat"];
let failed = 0;

console.log("PowerShell 脚本编码检查（必须带 UTF-8 BOM，兼容 PowerShell 5.1）");
for (const name of scripts) {
  let buf;
  try {
    buf = readFileSync(fileURLToPath(new URL(`../${name}`, import.meta.url)));
  } catch (error) {
    console.log(`  ✗ ${name} 读取失败：${error.message}`);
    failed += 1;
    continue;
  }
  const hasBom = buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf;
  const text = buf.toString("utf8").replace(/^\uFEFF/, "");
  const hasParam = /^param\(/m.test(text) || /^#/.test(text);
  const ok = hasBom && hasParam;
  console.log(`  ${ok ? "✓" : "✗"} ${name}：${hasBom ? "有 BOM" : "缺 BOM（PowerShell 5.1 会乱码并解析失败）"}${hasParam ? "" : " · 缺少 param/注释头"}`);
  if (!ok) failed += 1;
}

console.log("\nWindows 批处理编码检查（必须纯 ASCII + CRLF，避免 cmd.exe 多字节跳转错位）");
for (const name of batFiles) {
  let buf;
  try {
    buf = readFileSync(fileURLToPath(new URL(`../${name}`, import.meta.url)));
  } catch (error) {
    console.log(`  ✗ ${name} 读取失败：${error.message}`);
    failed += 1;
    continue;
  }
  const hasNonAscii = buf.some((b) => b > 0x7f);
  const text = buf.toString("ascii");
  const hasBareLf = /(^|[^\r])\n/.test(text);
  const ok = !hasNonAscii && !hasBareLf;
  console.log(
    `  ${ok ? "✓" : "✗"} ${name}：${hasNonAscii ? "含非 ASCII 字节（cmd.exe 会解析错位）" : "纯 ASCII"}${hasBareLf ? " · 含裸 LF（应为 CRLF）" : " · CRLF"}`,
  );
  if (!ok) failed += 1;
}

if (failed > 0) {
  console.error(`\n${failed} 个文件不合格`);
  process.exit(1);
}
console.log("\n全部通过");
