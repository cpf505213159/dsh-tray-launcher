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

    /// <summary>当前主题下鲸鱼图标应使用的颜色：浅色主题黑鲸鱼，深色主题白鲸鱼。</summary>
    public static string IconColor(bool light)
    {
        return light ? "#000000" : "#FFFFFF";
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
