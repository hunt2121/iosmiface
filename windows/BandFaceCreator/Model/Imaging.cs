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
        public static byte[] Png(this RgbaImage img) => Faces.Png.Encode(img.W, img.H, img.Px);

        /// <summary>Формат для компілятора: indexed8, якщо вистачає 256 кольорів, інакше RGB565A8.</summary>
        public static string BestFormat(this RgbaImage img) => FaceCatalog.ColorCount(img.Px) <= 256 ? "indexed8" : "RGB565A8";

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

        /// <summary>Зменшення до maxColors кольорів (медіанний поділ), щоб картинка йшла в indexed8 (без втрат при повторному збиранні).
        /// Альфа має бути однакова для всіх пікселів; інакше картинка лишається як є.</summary>
        public static RgbaImage Quantized(this RgbaImage img, int maxColors = 256)
        {
            int n = img.W * img.H;
            var px = img.Px;
            if (n == 0 || FaceCatalog.ColorCount(px) <= maxColors) return img;
            byte a0 = px[3];
            for (int i = 0; i < n; i++) if (px[i * 4 + 3] != a0) return img;
            var q = Quantizer.Build(new[] { px }, maxColors);
            var o = (byte[])px.Clone();
            for (int i = 0; i < n; i++)
            {
                int k = Quantizer.Bin(px, i * 4), c = q.Map[k];
                o[i * 4] = q.Palette[c * 3]; o[i * 4 + 1] = q.Palette[c * 3 + 1]; o[i * 4 + 2] = q.Palette[c * 3 + 2];
            }
            return new RgbaImage(img.W, img.H, o);
        }
    }

    /// <summary>Палітра медіанним поділом гістограми 5-5-5 (спільна для превʼю й GIF).</summary>
    sealed class Quantizer
    {
        public byte[] Palette = new byte[768];
        public byte[] Map = new byte[32768];
        public int Count;

        public static int Bin(byte[] p, int i) => (p[i] >> 3) << 10 | (p[i + 1] >> 3) << 5 | p[i + 2] >> 3;
        static int Ch(int k, int c) => c == 0 ? k >> 10 : c == 1 ? (k >> 5) & 31 : k & 31;

        public static Quantizer Build(System.Collections.Generic.IEnumerable<byte[]> frames, int colors)
        {
            var count = new long[32768];
            var sr = new long[32768]; var sg = new long[32768]; var sb = new long[32768];
            foreach (var p in frames)
                for (int i = 0; i + 3 < p.Length; i += 4)
                {
                    int k = Bin(p, i);
                    count[k]++; sr[k] += p[i]; sg[k] += p[i + 1]; sb[k] += p[i + 2];
                }
            var boxes = new System.Collections.Generic.List<System.Collections.Generic.List<int>>();
            var all = new System.Collections.Generic.List<int>();
            for (int k = 0; k < 32768; k++) if (count[k] > 0) all.Add(k);
            boxes.Add(all);
            while (boxes.Count < colors)
            {
                int best = -1, bestCh = 0;
                long bestScore = 0;
                for (int i = 0; i < boxes.Count; i++)
                {
                    var box = boxes[i];
                    if (box.Count <= 1) continue;
                    int[] lo = { 31, 31, 31 }, hi = { 0, 0, 0 };
                    long n = 0;
                    foreach (var k in box)
                    {
                        for (int c = 0; c < 3; c++) { int v = Ch(k, c); if (v < lo[c]) lo[c] = v; if (v > hi[c]) hi[c] = v; }
                        n += count[k];
                    }
                    int ch = 0;
                    for (int c = 1; c < 3; c++) if (hi[c] - lo[c] > hi[ch] - lo[ch]) ch = c;
                    long score = (hi[ch] - lo[ch]) * n;
                    if (score > bestScore) { bestScore = score; best = i; bestCh = ch; }
                }
                if (best < 0) break;
                int bc = bestCh;
                var sorted = boxes[best];
                sorted.Sort((x, y) => Ch(x, bc).CompareTo(Ch(y, bc)));
                long total = 0;
                foreach (var k in sorted) total += count[k];
                long acc = 0;
                int cut = 1;
                for (int j = 0; j < sorted.Count; j++)
                {
                    acc += count[sorted[j]];
                    if (acc * 2 >= total) { cut = Math.Max(1, Math.Min(sorted.Count - 1, j + 1)); break; }
                }
                boxes[best] = sorted.GetRange(0, cut);
                boxes.Add(sorted.GetRange(cut, sorted.Count - cut));
            }
            var q = new Quantizer { Count = boxes.Count };
            for (int i = 0; i < boxes.Count; i++)
            {
                long r = 0, g = 0, b = 0, n = 0;
                foreach (var k in boxes[i]) { r += sr[k]; g += sg[k]; b += sb[k]; n += count[k]; q.Map[k] = (byte)i; }
                n = Math.Max(n, 1);
                q.Palette[i * 3] = (byte)(r / n); q.Palette[i * 3 + 1] = (byte)(g / n); q.Palette[i * 3 + 2] = (byte)(b / n);
            }
            return q;
        }
    }
}
