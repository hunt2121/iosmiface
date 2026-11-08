// SPDX-License-Identifier: MIT
// Значок програми з меню «Пуск» за її AppUserModelId (shell:AppsFolder\<id>) — запасний шлях,
// коли сповіщення не дає логотипа (звичайні Win32-програми, як-от Telegram Desktop).

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace BandFace
{
    static class ShellIcon
    {
        [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr phbm); }

        [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; }

        [StructLayout(LayoutKind.Sequential)]
        struct BITMAPINFOHEADER
        {
            public int biSize, biWidth, biHeight; public short biPlanes, biBitCount;
            public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct BITMAP { public int bmType, bmWidth, bmHeight, bmWidthBytes; public short bmPlanes, bmBitsPixel; public IntPtr bmBits; }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHCreateItemFromParsingName(string path, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IntPtr ppv);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
        [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int size, out BITMAP bmp);
        [DllImport("gdi32.dll")] static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint lines, byte[] bits, ref BITMAPINFOHEADER bi, uint usage);
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

        const int SIIGBF_BIGGERSIZEOK = 0x1, SIIGBF_ICONONLY = 0x4;

        /// <summary>PNG значка програми; null — не вдалося</summary>
        public static byte[] PngForAppId(string aumid, int size = 256)
        {
            if (string.IsNullOrEmpty(aumid)) return null;
            IntPtr unk = IntPtr.Zero, hbm = IntPtr.Zero;
            try
            {
                if (SHCreateItemFromParsingName(@"shell:AppsFolder\" + aumid, IntPtr.Zero, typeof(IShellItemImageFactory).GUID, out unk) != 0 || unk == IntPtr.Zero) return null;
                var f = (IShellItemImageFactory)Marshal.GetObjectForIUnknown(unk);
                if (f.GetImage(new SIZE { cx = size, cy = size }, SIIGBF_BIGGERSIZEOK | SIIGBF_ICONONLY, out hbm) != 0 || hbm == IntPtr.Zero) return null;
                if (GetObject(hbm, Marshal.SizeOf(typeof(BITMAP)), out var bm) == 0 || bm.bmWidth <= 0 || bm.bmHeight <= 0) return null;
                int w = bm.bmWidth, h = bm.bmHeight;
                // пікселі зверху вниз, 32 біти з прозорістю (вже помножені на неї)
                var bi = new BITMAPINFOHEADER { biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER)), biWidth = w, biHeight = -h, biPlanes = 1, biBitCount = 32 };
                var px = new byte[w * h * 4];
                var dc = GetDC(IntPtr.Zero);
                try { if (GetDIBits(dc, hbm, 0, (uint)h, px, ref bi, 0) == 0) return null; }
                finally { ReleaseDC(IntPtr.Zero, dc); }
                // без прозорості (усі альфи 0) — вважаємо непрозорим
                bool anyAlpha = false;
                for (int i = 3; i < px.Length; i += 4) if (px[i] != 0) { anyAlpha = true; break; }
                if (!anyAlpha) for (int i = 3; i < px.Length; i += 4) px[i] = 255;
                var src = BitmapSource.Create(w, h, 96, 96, PixelFormats.Pbgra32, null, px, w * 4);
                var enc = new PngBitmapEncoder();
                enc.Frames.Add(BitmapFrame.Create(src));
                using (var ms = new MemoryStream()) { enc.Save(ms); return ms.ToArray(); }
            }
            catch (Exception) { return null; }
            finally
            {
                if (hbm != IntPtr.Zero) DeleteObject(hbm);
                if (unk != IntPtr.Zero) Marshal.Release(unk);
            }
        }
    }
}
