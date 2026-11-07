// SPDX-License-Identifier: MIT
// Перетворення між RGBA (без розмноження на альфу, як у компіляторі) і картинками WPF; малювання в RGBA.

using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class Imaging
    {
        /// <summary>PNG ресурсу циферблата: завжди не більше 256 кольорів (Band 10/11 знає лише indexed8, див. Band10.cs)</summary>
        public static byte[] Png(this RgbaImage img) { var q = Band10.To256(img); return Faces.Png.Encode(q.W, q.H, q.Px); }

        /// <summary>Формат для компілятора: на Band 10/11 усі картинки — indexed8 (фото зменшуються до 256 кольорів).</summary>
        public static string BestFormat(this RgbaImage img) => "indexed8";

        /// <summary>RGBA → картинка WPF (Bgra32, без розмноження).</summary>
        public static BitmapSource ToBitmap(this RgbaImage img)
        {
            if (img.W <= 0 || img.H <= 0) return null;
            var bgra = new byte[img.Px.Length];
            for (int i = 0; i < bgra.Length; i += 4)
            {
                bgra[i] = img.Px[i + 2]; bgra[i + 1] = img.Px[i + 1]; bgra[i + 2] = img.Px[i]; bgra[i + 3] = img.Px[i + 3];
            }
            var b = BitmapSource.Create(img.W, img.H, 96, 96, PixelFormats.Bgra32, null, bgra, img.W * 4);
            b.Freeze();
            return b;
        }

        /// <summary>Будь-яка картинка WPF → RGBA без розмноження.</summary>
        public static RgbaImage FromBitmap(BitmapSource src)
        {
            var conv = src.Format == PixelFormats.Bgra32 ? src : new FormatConvertedBitmap(src, PixelFormats.Bgra32, null, 0);
            int w = conv.PixelWidth, h = conv.PixelHeight;
            var bgra = new byte[w * h * 4];
            conv.CopyPixels(bgra, w * 4, 0);
            var px = new byte[bgra.Length];
            for (int i = 0; i < px.Length; i += 4)
            {
                px[i] = bgra[i + 2]; px[i + 1] = bgra[i + 1]; px[i + 2] = bgra[i]; px[i + 3] = bgra[i + 3];
            }
            return new RgbaImage(w, h, px);
        }

        /// <summary>Малювання в RGBA заданого розміру (сірим згладжуванням тексту — ClearType на прозорому фоні дає кольорові краї).</summary>
        public static RgbaImage Render(int w, int h, Action<DrawingContext> draw)
        {
            w = Math.Max(1, w); h = Math.Max(1, h);
            var dv = new DrawingVisual();
            TextOptions.SetTextRenderingMode(dv, TextRenderingMode.Grayscale);
            TextOptions.SetTextFormattingMode(dv, TextFormattingMode.Ideal);
            RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
            RenderOptions.SetEdgeMode(dv, EdgeMode.Unspecified);
            using (var dc = dv.RenderOpen()) draw(dc);
            var rtb = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
            rtb.Render(dv);
            var pb = new byte[w * h * 4];
            rtb.CopyPixels(pb, w * 4, 0);
            var px = new byte[pb.Length];
            for (int i = 0; i < pb.Length; i += 4)
            {
                int a = pb[i + 3];
                px[i + 3] = (byte)a;
                if (a == 0) continue;
                if (a == 255) { px[i] = pb[i + 2]; px[i + 1] = pb[i + 1]; px[i + 2] = pb[i]; continue; }
                px[i] = (byte)Math.Min(255, (pb[i + 2] * 255 + a / 2) / a);
                px[i + 1] = (byte)Math.Min(255, (pb[i + 1] * 255 + a / 2) / a);
                px[i + 2] = (byte)Math.Min(255, (pb[i] * 255 + a / 2) / a);
            }
            return new RgbaImage(w, h, px);
        }

        /// <summary>Декодування будь-якого формату (JPEG, BMP, GIF, TIFF, ICO…) засобами Windows.</summary>
        public static RgbaImage Decode(byte[] data)
        {
            using (var ms = new MemoryStream(data))
            {
                var dec = BitmapDecoder.Create(ms, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                return FromBitmap(dec.Frames[0]);
            }
        }

        /// <summary>Файл картинки → RGBA, за потреби зменшений до maxSide.</summary>
        public static RgbaImage Load(string path, double maxSide = 1000)
        {
            var img = Faces.Png.Decode(File.ReadAllBytes(path)) ?? Decode(File.ReadAllBytes(path));
            return Fit(img, maxSide);
        }

        public static RgbaImage Fit(RgbaImage img, double maxSide)
        {
            double s = Math.Min(1, maxSide / Math.Max(img.W, img.H));
            if (s >= 1) return img;
            int w = Math.Max(1, (int)Math.Round(img.W * s)), h = Math.Max(1, (int)Math.Round(img.H * s));
            var bmp = img.ToBitmap();
            return Render(w, h, dc => dc.DrawImage(bmp, new Rect(0, 0, w, h)));
        }

        /// <summary>Картинка в рамку w×h зі збереженням пропорцій (по центру).</summary>
        public static RgbaImage Contain(RgbaImage img, int w, int h)
        {
            if (img.W == w && img.H == h) return img;
            double s = Math.Min((double)w / img.W, (double)h / img.H);
            double dw = img.W * s, dh = img.H * s;
            var bmp = img.ToBitmap();
            return Render(w, h, dc => dc.DrawImage(bmp, new Rect((w - dw) / 2, (h - dh) / 2, dw, dh)));
        }

        /// <summary>Заповнення рамки w×h з обрізанням країв (для фону).</summary>
        public static RgbaImage Cover(RgbaImage img, int w, int h)
        {
            double s = Math.Max((double)w / img.W, (double)h / img.H);
            double dw = img.W * s, dh = img.H * s;
            var bmp = img.ToBitmap();
            return Render(w, h, dc => dc.DrawImage(bmp, new Rect((w - dw) / 2, (h - dh) / 2, dw, dh)));
        }

        public static Color ParseColor(string hex)
        {
            var s = (hex ?? "").Trim();
            if (s.StartsWith("#")) s = s.Substring(1);
            uint v;
            if (s.Length != 6 || !uint.TryParse(s, System.Globalization.NumberStyles.HexNumber, null, out v)) v = 0xFFFFFF;
            return Color.FromRgb((byte)(v >> 16), (byte)(v >> 8), (byte)v);
        }

        public static string Hex(Color c) => "#" + c.R.ToString("X2") + c.G.ToString("X2") + c.B.ToString("X2");

        public static SolidColorBrush Brush(string hex, double opacity = 1)
        {
            var b = new SolidColorBrush(ParseColor(hex)) { Opacity = opacity };
            b.Freeze();
            return b;
        }

        /// <summary>Не більше 256 кольорів (разом із прозорістю)</summary>
        public static RgbaImage Quantized(this RgbaImage img) => Band10.To256(img);
    }
}
