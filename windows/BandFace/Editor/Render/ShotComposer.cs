// SPDX-License-Identifier: MIT
// «Набір знімків»: екрани циферблата (стилі, кольори, AOD, стани) на одній оформленій картинці —
// тло, назва, підписи, рамка капсулою чи браслетом. Розмір — за кількістю екранів або за форматом (1:1, 9:16, 16:9).
// Те саме, що ShotComposer в iOS: однакові розміри й правила.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace BandFace.Creator
{
    static class ShotComposer
    {
        public sealed class Item
        {
            public ShotScreen Screen;
            /// <summary>0 — звичайний, 1 — Bluetooth від'єднано, 2 — заряд 15 %</summary>
            public int State;
        }

        public static List<Item> Items(ShotSet s)
        {
            var r = new List<Item>();
            foreach (var sc in s.Screens)
            {
                r.Add(new Item { Screen = sc });
                if (sc.Bluetooth) r.Add(new Item { Screen = sc, State = 1 });
                if (sc.Battery) r.Add(new Item { Screen = sc, State = 2 });
            }
            return r;
        }

        // ---------- Тексти ----------

        static int StyleTheme(FaceProject p, ShotScreen sc)
        {
            var st = p.StyleThemes();
            return sc.Style >= 0 && sc.Style < st.Count ? st[sc.Style] : (st.Count > 0 ? st[0] : 0);
        }

        /// <summary>Тема екрана: стиль або його AOD (якщо AOD немає — сам стиль)</summary>
        public static int Theme(FaceProject p, ShotScreen sc)
        {
            var t = StyleTheme(p, sc);
            if (sc.Aod) { var a = p.AodOf(t); if (a >= 0) return a; }
            return t;
        }

        public static string ColorName(int i) => i == 0 ? S.Get("baseColor") : S.Get("colorN", i);

        public static string DefaultName(FaceProject p, ShotScreen sc)
        {
            var s = p.StyleTitle(StyleTheme(p, sc));
            if (ColorVariants.IsEnabled(p)) s += " · " + ColorName(sc.Color);
            return s;
        }

        public static string Name(FaceProject p, ShotScreen sc) => string.IsNullOrEmpty(sc.Name) ? DefaultName(p, sc) : sc.Name;

        public static string StateText(Item it) =>
            it.State == 1 ? S.Get("shotBtOff") : it.State == 2 ? S.Get("shotLowBattery") : it.Screen.Aod ? S.Get("screenAod") : null;

        public static string AutoTitle(FaceProject p) => p.DisplayName;
        public static string AutoAbove(FaceProject p) => S.Get("shotFor", p.Meta.Device.Title);

        public static string AutoBelow(FaceProject p)
        {
            int n = p.StyleThemes().Count, c = ColorVariants.IsEnabled(p) ? ColorVariants.Colors(p).Count : 0;
            var parts = new List<string>();
            if (n > 1) parts.Add(Plural(n, "shotStyles"));
            if (c > 1) parts.Add(Plural(c, "shotColors"));
            return string.Join(" · ", parts);
        }

        static string Plural(int n, string key)
        {
            int a = n % 10, b = n % 100;
            var form = a == 1 && b != 11 ? "1" : a >= 2 && a <= 4 && (b < 12 || b > 14) ? "2" : "5";
            return S.Get(key + form, n);
        }

        // ---------- Тло ----------

        public static Color[] BackgroundColors(FaceProject p, string key)
        {
            Color C(string h) => Imaging.ParseColor(h);
            switch (key)
            {
                case "dark": return new[] { C("#1F2A3A"), C("#0C0C0E") };
                case "black": return new[] { C("#000000") };
                case "white": return new[] { C("#FFFFFF") };
                case "light": return new[] { C("#F2F2F5") };
                case "blue": return new[] { C("#1E4FD8"), C("#0B1A4A") };
                case "face":
                    var cs = ColorVariants.Colors(p);
                    var b = C(cs.Count > 0 ? cs[0] : p.Theme(p.StyleThemes().FirstOrDefault())?.Str("bgColor") ?? "#1F2A3A");
                    return new[] { Mix(b, Colors.Black, 0.55), Mix(b, Colors.Black, 0.88) };
                default: return new[] { C(key) };
            }
        }

        static Color Mix(Color a, Color b, double t) =>
            Color.FromRgb((byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));

        public static Brush BackgroundBrush(FaceProject p, string key)
        {
            var cs = BackgroundColors(p, key);
            Brush br = cs.Length > 1 ? new LinearGradientBrush(cs[0], cs[1], new Point(0.3, 0), new Point(0.7, 1)) : (Brush)new SolidColorBrush(cs[0]);
            br.Freeze();
            return br;
        }

        static double Lum(Color c) => (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) / 255;
        public static bool IsLight(Color[] cs) => cs.Average(Lum) > 0.55;

        // ---------- Розміри (pt; картинка — удвічі більша) ----------

        const double DevW = 212, DevH = 520;
        /// <summary>Рамка-браслет: картинка 480×1240, екран у ній — (97, 262, 287×704)</summary>
        static readonly Size BandImg = new Size(480, 1240);
        static readonly Rect BandScreen = new Rect(97, 262, 287, 704);

        static double ScreenWidth(int size) => new double[] { 170, 150, 120 }[Math.Max(0, Math.Min(2, size))];

        static Size CellBody(ShotSet s, double w)
        {
            if (s.Band) { var k = w / BandScreen.Width; return new Size(BandImg.Width * k, BandImg.Height * k); }
            return new Size(w, w * DevH / DevW);
        }

        static int AutoColumns(int n) => n <= 5 ? Math.Max(1, n) : n <= 12 ? (n + 1) / 2 : 6;

        static Size? Fixed(string format)
        {
            switch (format)
            {
                case "square": return new Size(620, 620);
                case "story": return new Size(540, 960);
                case "wide": return new Size(960, 540);
                default: return null;
            }
        }

        static BitmapImage BandImage(bool dark)
        {
            var b = new BitmapImage();
            b.BeginInit();
            b.UriSource = new Uri("pack://application:,,,/Assets/" + (dark ? "ShotBandDark.png" : "ShotBandLight.png"));
            b.CacheOption = BitmapCacheOption.OnLoad;
            b.EndInit();
            b.Freeze();
            return b;
        }

        static FormattedText Text(string s, double size, FontWeight w, Brush b, double kern = 0)
        {
            var ft = new FormattedText(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, w, FontStretches.Normal), size, b, 2.0);
            return ft;
        }

        static Brush B(string hex) { var b = Imaging.Brush(hex); return b; }

        // ---------- Складання ----------

        public static BitmapSource Compose(FaceProject p, ShotSet s)
        {
            var list = Items(s);
            if (list.Count == 0) return null;
            var bgc = BackgroundColors(p, s.Background);
            bool light = IsLight(bgc);
            Brush fg = light ? B("#121212") : Brushes.White;
            Brush sub = B(light ? "#6B6F78" : "#9AA0AA");
            Brush kick = B(light ? "#8A8F99" : "#8F97A6");

            string above = s.Above ?? AutoAbove(p), title = s.Title ?? AutoTitle(p), below = s.Below ?? AutoBelow(p);
            var aboveT = Text(above.ToUpperInvariant(), 13, FontWeights.Medium, kick);
            var titleT = Text(title, 56, FontWeights.Black, fg);
            var belowT = Text(below, 16, FontWeights.Normal, sub);
            double header = 0;
            if (above.Length > 0) header += aboveT.Height + 6;
            if (title.Length > 0) header += titleT.Height;
            if (below.Length > 0) header += belowT.Height + 4;
            if (header > 0) header += 36;
            var creditBrush = fg.Clone(); creditBrush.Opacity = 0.5; creditBrush.Freeze();
            var creditT = Text(S.Get("shotCredit"), 13, FontWeights.Medium, creditBrush);
            double footer = s.Credit ? creditT.Height + 34 : 0;

            int n = list.Count;
            double capH = s.Captions ? (list.Any(i => StateText(i) != null) ? 54 : 34) : 0;
            double w = ScreenWidth(s.Size);
            int cols = AutoColumns(n);
            const double gapX = 34, gapY = 34, padX = 60, padY = 50;
            Size Grid(int c, double ww)
            {
                var body = CellBody(s, ww); int rows = (n + c - 1) / c;
                double cw = Math.Max(body.Width, s.Captions ? ww + 40 : 0);
                return new Size(c * cw + (c - 1) * gapX, rows * (body.Height + capH) + (rows - 1) * gapY);
            }
            Size canvas;
            var fixedSize = Fixed(s.Format);
            if (fixedSize is Size fx)
            {
                var area = new Size(fx.Width - 2 * padX, fx.Height - 2 * padY - header - footer);
                int bestC = 1; double bestW = 10;
                for (int c = 1; c <= n; c++)
                {
                    var g = Grid(c, 100);
                    var k = Math.Min(area.Width / g.Width, area.Height / g.Height);
                    var wc = 100 * k * new[] { 1, 0.9, 0.75 }[Math.Max(0, Math.Min(2, s.Size))];
                    if (wc > bestW) { bestW = wc; bestC = c; }
                }
                cols = bestC; w = Math.Min(bestW, 260);
                canvas = fx;
            }
            else
            {
                var g = Grid(cols, w);
                canvas = new Size(Math.Max(g.Width + 2 * padX, 640), g.Height + 2 * padY + header + footer);
            }
            var grid = Grid(cols, w);
            var cell = CellBody(s, w);
            double cellW = (grid.Width - (cols - 1) * gapX) / cols;

            var renderer = new FaceRenderer(p);
            if (s.Time != null) { var d = p.Meta.Demo.Copy(); d.Time = s.Time; d.RealTime = false; renderer.Demo = d; }
            var bandImg = s.Band ? BandImage(light) : null;

            var dv = new DrawingVisual();
            RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
            using (var dc = dv.RenderOpen())
            {
                dc.DrawRectangle(BackgroundBrush(p, s.Background), null, new Rect(canvas));
                double total = header + grid.Height + footer;
                double y = (canvas.Height - total) / 2;
                void Center(FormattedText t) { dc.DrawText(t, new Point((canvas.Width - t.WidthIncludingTrailingWhitespace) / 2, y)); y += t.Height; }
                if (header > 0)
                {
                    if (above.Length > 0) { Center(aboveT); y += 6; }
                    if (title.Length > 0) Center(titleT);
                    if (below.Length > 0) { y += 4; Center(belowT); }
                    y += 36;
                }
                double x0 = (canvas.Width - grid.Width) / 2;
                int rows = (n + cols - 1) / cols;
                for (int i = 0; i < n; i++)
                {
                    var it = list[i];
                    int r = i / cols, col = i % cols;
                    int inRow = r == rows - 1 ? n - r * cols : cols;
                    double rowX = x0 + (grid.Width - (inRow * cellW + (inRow - 1) * gapX)) / 2;
                    double cx = rowX + col * (cellW + gapX) + cellW / 2;
                    double top = y + r * (cell.Height + capH + gapY);
                    DrawScreen(dc, p, s, it, renderer, bandImg, light, new Rect(cx - cell.Width / 2, top, cell.Width, cell.Height));
                    if (s.Captions)
                    {
                        var nameT = Text(Name(p, it.Screen), 15, FontWeights.SemiBold, fg);
                        nameT.MaxTextWidth = cellW + 20; nameT.MaxLineCount = 1; nameT.Trimming = TextTrimming.CharacterEllipsis;
                        double ty = top + cell.Height + 14;
                        dc.DrawText(nameT, new Point(cx - Math.Min(nameT.Width, cellW + 20) / 2, ty));
                        ty += nameT.Height + 3;
                        var st = StateText(it);
                        if (st != null)
                        {
                            var col2 = it.State == 2 ? B(light ? "#E07800" : "#FFC46B") : B(light ? "#2F7DF6" : "#9CC8FF");
                            var stT = Text(st, 13, FontWeights.Normal, col2);
                            dc.DrawText(stT, new Point(cx - stT.Width / 2, ty));
                        }
                    }
                }
                if (s.Credit) { y += grid.Height + 34; Center(creditT); }
            }
            var rtb = new RenderTargetBitmap((int)Math.Round(canvas.Width * 2), (int)Math.Round(canvas.Height * 2), 192, 192, PixelFormats.Pbgra32);
            rtb.Render(dv);
            rtb.Freeze();
            return rtb;
        }

        static void DrawScreen(DrawingContext dc, FaceProject p, ShotSet s, Item it, FaceRenderer renderer, BitmapSource band, bool light, Rect rect)
        {
            var screen = rect;
            if (band != null)
            {
                double k = rect.Width / BandImg.Width;
                screen = new Rect(rect.X + BandScreen.X * k, rect.Y + BandScreen.Y * k, BandScreen.Width * k, BandScreen.Height * k);
                if (s.Shadow) DrawShadow(dc, new RectangleGeometry(new Rect(rect.X + rect.Width * 0.12, rect.Y + rect.Height * 0.06, rect.Width * 0.76, rect.Height * 0.9), rect.Width * 0.3, rect.Width * 0.3), light);
                dc.DrawImage(band, rect);
            }
            renderer.ColorVariant = it.Screen.Color;
            renderer.BluetoothOff = it.State == 1;
            renderer.LowBattery = it.State == 2;
            renderer.SlotChoice = it.Screen.Widgets;
            var dev = p.Meta.Device;
            var img = renderer.Render(Theme(p, it.Screen), Math.Max(1, Math.Ceiling(screen.Width * 2 / DevW))).Image;
            double r = band != null || s.Rounded ? dev.Corner * screen.Width / dev.Width : 0;
            var geo = new RectangleGeometry(screen, r, r);
            if (band == null && s.Shadow) DrawShadow(dc, geo, light);
            dc.PushClip(geo);
            dc.DrawImage(img, screen);
            dc.Pop();
        }

        /// <summary>М'яка тінь під формою: кілька прозорих шарів, зсунутих донизу (DrawingContext не має розмиття)</summary>
        static void DrawShadow(DrawingContext dc, Geometry g, bool light)
        {
            double a = light ? 0.05 : 0.11;
            for (int i = 6; i >= 1; i--)
            {
                var pen = new Pen(new SolidColorBrush(Color.FromArgb((byte)(255 * a), 0, 0, 0)), i * 7);
                pen.LineJoin = PenLineJoin.Round;
                pen.Freeze();
                dc.PushTransform(new TranslateTransform(0, 10 + i * 1.5));
                dc.DrawGeometry(pen.Brush, pen, g);
                dc.Pop();
            }
        }
    }
}
