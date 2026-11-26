// DeepSeek Harness 托盘的主题支持：图标着色 + 菜单渲染器。
// 由 tray.ps1 与脚本通过 Add-Type -Path 加载（Windows PowerShell 5.1 / .NET Framework）。
using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

/// <summary>Windows 深浅主题读取与图标配色。</summary>
public static class TrayTheme
{
    public const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

    /// <summary>任务栏/开始菜单是否为浅色主题。键缺失或读取失败一律按深色处理。</summary>
    public static bool IsLightTheme()
    {
        return IsLightTheme(PersonalizeKey);
    }

    /// <summary>从指定子键读取 SystemUsesLightTheme（1=浅色）。</summary>
    public static bool IsLightTheme(string subKey)
    {
        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(subKey))
            {
                if (k == null) return false;
                object v = k.GetValue("SystemUsesLightTheme");
                if (v == null) return false;
                return Convert.ToInt32(v) == 1;
            }
        }
        catch
        {
            return false;
        }
    }
}

/// <summary>右键菜单绘制：深/浅两套配色，悬停用品牌蓝填充圆角块。</summary>
public class TrayMenuRenderer : ToolStripRenderer
{
    public Color BackColor { get; private set; }
    public Color TextColor { get; private set; }
    public Color HoverColor { get; private set; }
    public Color SeparatorColor { get; private set; }
    public Color BorderColor { get; private set; }

    public TrayMenuRenderer(bool light)
    {
        HoverColor = Color.FromArgb(0x4D, 0x6B, 0xFE);
        if (light)
        {
            BackColor = Color.FromArgb(250, 250, 250);
            TextColor = Color.FromArgb(32, 32, 32);
            SeparatorColor = Color.FromArgb(226, 226, 226);
            BorderColor = Color.FromArgb(214, 214, 214);
        }
        else
        {
            BackColor = Color.FromArgb(32, 32, 32);
            TextColor = Color.FromArgb(240, 240, 240);
            SeparatorColor = Color.FromArgb(66, 66, 66);
            BorderColor = Color.FromArgb(56, 56, 56);
        }
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        using (SolidBrush b = new SolidBrush(BackColor))
            e.Graphics.FillRectangle(b, e.AffectedBounds);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        using (Pen p = new Pen(BorderColor))
            e.Graphics.DrawRectangle(p, 0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        Rectangle r = new Rectangle(2, 1, e.Item.Width - 4, e.Item.Height - 2);
        using (GraphicsPath path = RoundedRect(r, 6))
        using (SolidBrush b = new SolidBrush(HoverColor))
            e.Graphics.FillPath(b, path);
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        if (!e.Item.Enabled)
            e.TextColor = Color.FromArgb(128, TextColor);
        else if (e.Item.Selected)
            e.TextColor = Color.White;
        else
            e.TextColor = TextColor;
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        int y = e.Item.Height / 2;
        using (Pen p = new Pen(SeparatorColor))
            e.Graphics.DrawLine(p, 10, y, e.Item.Width - 10, y);
    }

    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
    {
        e.ArrowColor = e.Item.Selected ? Color.White : TextColor;
        base.OnRenderArrow(e);
    }

    private static GraphicsPath RoundedRect(Rectangle r, int radius)
    {
        int d = radius * 2;
        GraphicsPath path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}

/// <summary>读取多尺寸 ICO，按目标色重着色并以 PNG-compressed ICO 输出。</summary>
public static class TrayIconFactory
{
    /// <summary>把 sourceIco 中所有图标按 tint 着色，写到 outIco。成功返回 true。</summary>
    public static bool Build(string sourceIco, string rgbHex, string outIco)
    {
        try
        {
            Color tint = ParseColor(rgbHex);
            byte[] src = File.ReadAllBytes(sourceIco);
            if (src.Length < 6 || BitConverter.ToUInt16(src, 2) != 1) return false;
            int count = BitConverter.ToUInt16(src, 4);

            var images = new List<byte[]>();
            var sizes = new List<int>();

            for (int i = 0; i < count; i++)
            {
                int o = 6 + i * 16;
                int w = src[o] == 0 ? 256 : src[o];
                int h = src[o + 1] == 0 ? 256 : src[o + 1];
                int size = BitConverter.ToInt32(src, o + 8);
                int off = BitConverter.ToInt32(src, o + 12);
                if (off < 0 || size < 0 || off + size > src.Length) return false;

                byte[] data = new byte[size];
                Array.Copy(src, off, data, 0, size);

                bool isPng = data.Length > 8 && data[0] == 0x89 && data[1] == 0x50
                             && data[2] == 0x4E && data[3] == 0x47;
                images.Add(isPng ? RecolorPng(data, tint) : data);
                sizes.Add(w);
            }

            if (images.Count == 0) return false;

            using (var ms = new MemoryStream())
            using (var bw = new BinaryWriter(ms))
            {
                bw.Write((ushort)0);
                bw.Write((ushort)1);
                bw.Write((ushort)images.Count);
                int offset = 6 + images.Count * 16;
                for (int i = 0; i < images.Count; i++)
                {
                    int dim = sizes[i];
                    bw.Write((byte)(dim >= 256 ? 0 : dim));
                    bw.Write((byte)(dim >= 256 ? 0 : dim));
                    bw.Write((byte)0);
                    bw.Write((byte)0);
                    bw.Write((ushort)1);
                    bw.Write((ushort)32);
                    bw.Write(images[i].Length);
                    bw.Write(offset);
                    offset += images[i].Length;
                }
                foreach (byte[] img in images) bw.Write(img);
                File.WriteAllBytes(outIco, ms.ToArray());
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>直接返回着色后的 Icon（内部经临时文件加载）；失败返回 null。</summary>
    public static Icon MakeIcon(string sourceIco, string rgbHex)
    {
        string tmp = Path.Combine(Path.GetTempPath(), "dsh-tray-" + Guid.NewGuid().ToString("N") + ".ico");
        try
        {
            if (!Build(sourceIco, rgbHex, tmp)) return null;
            Icon icon = new Icon(tmp);
            return icon;
        }
        catch
        {
            return null;
        }
        finally
        {
            try { File.Delete(tmp); } catch { }
        }
    }

    private static Color ParseColor(string hex)
    {
        if (hex == null) throw new ArgumentNullException("hex");
        hex = hex.Trim().TrimStart('#');
        if (hex.Length != 6) throw new FormatException("expected RRGGBB");
        return Color.FromArgb(
            Convert.ToInt32(hex.Substring(0, 2), 16),
            Convert.ToInt32(hex.Substring(2, 2), 16),
            Convert.ToInt32(hex.Substring(4, 2), 16));
    }

    private static byte[] RecolorPng(byte[] png, Color tint)
    {
        using (var input = new MemoryStream(png))
        using (var bmp = new Bitmap(input))
        {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                int len = Math.Abs(data.Stride) * bmp.Height;
                byte[] buf = new byte[len];
                Marshal.Copy(data.Scan0, buf, 0, len);
                for (int i = 0; i + 3 < len; i += 4)
                {
                    if (buf[i + 3] == 0) continue;
                    buf[i] = tint.B;
                    buf[i + 1] = tint.G;
                    buf[i + 2] = tint.R;
                }
                Marshal.Copy(buf, 0, data.Scan0, len);
            }
            finally
            {
                bmp.UnlockBits(data);
            }

            using (var outMs = new MemoryStream())
            {
                bmp.Save(outMs, ImageFormat.Png);
                return outMs.ToArray();
            }
        }
    }
}
