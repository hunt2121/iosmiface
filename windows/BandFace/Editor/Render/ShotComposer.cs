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
        /// <summary>«Циферблат для Xiaomi Smart Band 10 • 11»: Band 10 і 11 мають той самий екран — циферблат підходить обом</summary>
        public static string AutoAbove(FaceProject p)
        {
            var d = p.Meta.Device;
            return S.Get("shotFor", d.Width == 212 && d.Height == 520 ? "Xiaomi Smart Band 10 • 11" : d.Title);
        }

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

        /// <summary>Розкладка сітки: стовпці, ширина екрана, вузький режим (дрібніші підписи, стани — лише значком)</summary>
        struct Layout
        {
            public int Cols; public double W; public bool Narrow;
            public double Gap => Narrow ? 18 : 30;
            public const double RowGap = 30;
        }

        static double ItemWidth(ShotSet s, Layout l) => Math.Max(CellBody(s, l.W).Width, s.Captions ? l.W + (l.Narrow ? 18 : 40) : 0);

        static Size GridSize(ShotSet s, Layout l, int n, double capH)
        {
            int rows = (n + l.Cols - 1) / l.Cols;
            var body = CellBody(s, l.W);
            return new Size(l.Cols * ItemWidth(s, l) + (l.Cols - 1) * l.Gap, rows * (body.Height + capH) + (rows - 1) * Layout.RowGap);
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

        static FormattedText Text(string s, double size, FontWeight w, Brush b) =>
            new FormattedText(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, w, FontStretches.Normal), size, b, 2.0);

        static SolidColorBrush B(string hex, double opacity = 1) => Imaging.Brush(hex, opacity);

        sealed class Palette
        {
            public bool Light;
            public Brush Fg => Light ? B("#111318") : Brushes.White;
            public Brush Sub => B(Light ? "#6B7080" : "#A3A9B6");
            public Brush SubSoft => B(Light ? "#6B7080" : "#A3A9B6", 0.8);
            public Brush Line => Light ? B("#000000", 0.12) : B("#FFFFFF", 0.14);
            public string State(Item it) => Light
                ? (it.State == 1 ? "#1E6FE0" : it.State == 2 ? "#C46A00" : "#6A4FD8")
                : (it.State == 1 ? "#5AA2FF" : it.State == 2 ? "#FFB23F" : "#B9A6FF");
        }

        // ---------- Складання ----------

        public static BitmapSource Compose(FaceProject p, ShotSet s)
        {
            var list = Items(s);
            if (list.Count == 0) return null;
            var bgc = BackgroundColors(p, s.Background);
            var pal = new Palette { Light = IsLight(bgc) };
            var fixedSize = Fixed(s.Format);

            string above = s.Above ?? AutoAbove(p), title = s.Title ?? AutoTitle(p), below = s.Below ?? AutoBelow(p);
            double titleSize = fixedSize == null ? 64 : s.Format == "wide" ? 44 : 48;
            var aboveT = Text(above.ToUpperInvariant(), 11.5, FontWeights.SemiBold, pal.Sub);
            var titleT = Text(title, titleSize, FontWeights.ExtraBold, pal.Fg);
            var chips = below.Split(new[] { " · " }, StringSplitOptions.RemoveEmptyEntries);
            var chipT = chips.Select(c => Text(c, 12.5, FontWeights.Medium, pal.Sub)).ToList();
            const double chipH = 24;
            double header = 0;
            if (above.Length > 0) header += aboveT.Height;
            if (title.Length > 0) header += (header > 0 ? 12 : 0) + titleT.Height;
            if (chips.Length > 0) header += (header > 0 ? 14 : 0) + chipH;
            if (header > 0) header += 42;
            var creditT = Text(S.Get("shotCredit"), 12, FontWeights.Medium, pal.SubSoft);
            double footer = s.Credit ? 40 + creditT.Height : 0;

            int n = list.Count;
            double capH = s.Captions ? (list.Any(i => StateText(i) != null) ? 66 : 39) : 0;
            const double padX = 56, padY = 48;
            var lay = new Layout { Cols = AutoColumns(n), W = ScreenWidth(s.Size) };
            Size canvas;
            if (fixedSize is Size fx)
            {
                var area = new Size(fx.Width - 2 * padX, fx.Height - 2 * padY - header - footer);
                var best = new Layout { Cols = 1, W = 10 };
                foreach (var narrow in new[] { false, true })
                {
                    for (int c = 1; c <= n; c++)
                    {
                        double lo = 10, hi = 400;
                        for (int k = 0; k < 24; k++)
                        {
                            var m = (lo + hi) / 2;
                            var g = GridSize(s, new Layout { Cols = c, W = m, Narrow = narrow }, n, capH);
                            if (g.Width <= area.Width && g.Height <= area.Height) lo = m; else hi = m;
                        }
                        if (lo > best.W) best = new Layout { Cols = c, W = lo, Narrow = narrow };
                    }
                    // вузький режим — лише коли звичайний дає зовсім дрібні екрани
                    if (best.W >= 90) break;
                }
                best.W = Math.Min(Math.Floor(best.W * new[] { 1, 0.9, 0.78 }[Math.Max(0, Math.Min(2, s.Size))]), 260);
                lay = best;
                canvas = fx;
            }
            else
            {
                var g = GridSize(s, lay, n, capH);
                canvas = new Size(Math.Max(g.Width + 2 * padX, 640), g.Height + 2 * padY + header + footer);
            }
            var grid = GridSize(s, lay, n, capH);
            var body = CellBody(s, lay.W);
            double iw = ItemWidth(s, lay);

            var renderer = new FaceRenderer(p);
            if (s.Time != null) { var d = p.Meta.Demo.Copy(); d.Time = s.Time; d.RealTime = false; renderer.Demo = d; }
            var bandImg = s.Band ? BandImage(pal.Light) : null;

            var dv = new DrawingVisual();
            RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
            using (var dc = dv.RenderOpen())
            {
                dc.DrawRectangle(BackgroundBrush(p, s.Background), null, new Rect(canvas));
                // легке світіння за екранами
                var glowC = pal.Light ? Color.FromArgb(191, 255, 255, 255) : Color.FromArgb(26, 120, 160, 255);
                var glow = new RadialGradientBrush(glowC, Color.FromArgb(0, glowC.R, glowC.G, glowC.B))
                {
                    MappingMode = BrushMappingMode.Absolute, Center = new Point(canvas.Width / 2, canvas.Height * 0.62),
                    GradientOrigin = new Point(canvas.Width / 2, canvas.Height * 0.62), RadiusX = canvas.Width * 0.42, RadiusY = canvas.Width * 0.42 * 0.75,
                };
                glow.Freeze();
                dc.DrawRectangle(glow, null, new Rect(canvas));

                double total = header + grid.Height + footer;
                double y0 = (canvas.Height - total) / 2, y = y0;
                void Center(FormattedText t, double yy) => dc.DrawText(t, new Point((canvas.Width - t.WidthIncludingTrailingWhitespace) / 2, yy));
                if (header > 0)
                {
                    if (above.Length > 0)
                    {
                        // розрідження літер: FormattedText його не вміє — рядок збирається з літер із проміжками
                        var spaced = Spaced(above.ToUpperInvariant(), 11.5, pal.Sub, 2.6, out double sw, out double sh);
                        double x = (canvas.Width - sw) / 2;
                        foreach (var (t, dx) in spaced) dc.DrawText(t, new Point(x + dx, y));
                        double ly = y + sh / 2;
                        dc.DrawRectangle(pal.Line, null, new Rect(x - 14 - 28, ly, 28, 1));
                        dc.DrawRectangle(pal.Line, null, new Rect(x + sw + 14, ly, 28, 1));
                        y += sh;
                    }
                    if (title.Length > 0) { if (y > y0) y += 12; Center(titleT, y); y += titleT.Height; }
                    if (chips.Length > 0)
                    {
                        if (y > y0) y += 14;
                        var widths = chipT.Select(t => t.WidthIncludingTrailingWhitespace + 22).ToList();
                        double x = (canvas.Width - (widths.Sum() + (chips.Length - 1) * 8)) / 2;
                        var pen = new Pen(pal.Line, 1); pen.Freeze();
                        for (int i = 0; i < chipT.Count; i++)
                        {
                            var r = new Rect(x + 0.5, y + 0.5, widths[i] - 1, chipH - 1);
                            dc.DrawRoundedRectangle(null, pen, r, chipH / 2, chipH / 2);
                            dc.DrawText(chipT[i], new Point(x + 11, y + (chipH - chipT[i].Height) / 2));
                            x += widths[i] + 8;
                        }
                        y += chipH;
                    }
                    y += 42;
                }

                int rows = (n + lay.Cols - 1) / lay.Cols;
                for (int i = 0; i < n; i++)
                {
                    var it = list[i];
                    int r = i / lay.Cols, col = i % lay.Cols;
                    int inRow = r == rows - 1 ? n - r * lay.Cols : lay.Cols;
                    double rowX = (canvas.Width - (inRow * iw + (inRow - 1) * lay.Gap)) / 2;
                    double cx = rowX + col * (iw + lay.Gap) + iw / 2;
                    double top = y + r * (body.Height + capH + Layout.RowGap);
                    DrawScreen(dc, p, s, it, renderer, bandImg, pal.Light, new Rect(cx - body.Width / 2, top, body.Width, body.Height));
                    if (s.Captions) DrawCaption(dc, p, it, pal, lay.Narrow, cx, iw, top + body.Height + 20);
                }
                if (s.Credit)
                {
                    double cy = y + grid.Height + 40;
                    double tw = creditT.WidthIncludingTrailingWhitespace, x0 = (canvas.Width - (13 + 6 + tw)) / 2;
                    dc.PushTransform(new TranslateTransform(x0, cy + (creditT.Height - 13) / 2));
                    dc.PushTransform(new ScaleTransform(13 / 26.0, 13 / 26.0));
                    dc.DrawGeometry(pal.SubSoft, null, (Geometry)Application.Current.Resources["BandGeometry"]);
                    dc.Pop(); dc.Pop();
                    dc.DrawText(creditT, new Point(x0 + 19, cy));
                }
            }
            var rtb = new RenderTargetBitmap((int)Math.Round(canvas.Width * 2), (int)Math.Round(canvas.Height * 2), 192, 192, PixelFormats.Pbgra32);
            rtb.Render(dv);
            rtb.Freeze();
            return rtb;
        }

        /// <summary>Рядок із розрідженими літерами: кожна літера окремо, з проміжком kern між ними</summary>
        static List<(FormattedText, double)> Spaced(string s, double size, Brush b, double kern, out double width, out double height)
        {
            var r = new List<(FormattedText, double)>();
            double x = 0; height = 0;
            foreach (var ch in s)
            {
                var t = Text(ch.ToString(), size, FontWeights.SemiBold, b);
                r.Add((t, x));
                x += t.WidthIncludingTrailingWhitespace + kern;
                height = Math.Max(height, t.Height);
            }
            width = Math.Max(0, x - kern);
            return r;
        }

        /// <summary>Підпис під екраном: назва і мітка стану (кольорова капсула зі значком; у вузькому режимі — лише значок)</summary>
        static void DrawCaption(DrawingContext dc, FaceProject p, Item it, Palette pal, bool narrow, double cx, double width, double top)
        {
            var nameT = Text(Name(p, it.Screen), narrow ? 12 : 14.5, FontWeights.SemiBold, pal.Fg);
            nameT.MaxTextWidth = width; nameT.MaxLineCount = 1; nameT.Trimming = TextTrimming.CharacterEllipsis;
            nameT.TextAlignment = TextAlignment.Center;
            dc.DrawText(nameT, new Point(cx - width / 2, top));
            var st = StateText(it);
            if (st == null) return;
            var col = Imaging.ParseColor(pal.State(it));
            var colB = new SolidColorBrush(col); colB.Freeze();
            double pillY = top + nameT.Height + 7, pillH = 20, iconW = 12;
            var textT = Text(st, 11.5, FontWeights.Medium, colB);
            double w = narrow ? 26 : 8 + iconW + 5 + textT.WidthIncludingTrailingWhitespace + 9;
            var bg = new SolidColorBrush(Color.FromArgb((byte)(255 * (pal.Light ? 0.12 : 0.15)), col.R, col.G, col.B)); bg.Freeze();
            dc.DrawRoundedRectangle(bg, null, new Rect(cx - w / 2, pillY, w, pillH), pillH / 2, pillH / 2);
            var ir = new Rect(narrow ? cx - iconW / 2 : cx - w / 2 + 8, pillY + (pillH - iconW) / 2, iconW, iconW);
            StateIcon(dc, it, ir, colB);
            if (!narrow) dc.DrawText(textT, new Point(ir.Right + 5, pillY + (pillH - textT.Height) / 2));
        }

        /// <summary>Значок стану в квадраті r: Bluetooth від'єднано, батарея, місяць (AOD); поле 18×18</summary>
        static void StateIcon(DrawingContext dc, Item it, Rect r, Brush b)
        {
            double k = r.Width / 18;
            dc.PushTransform(new TranslateTransform(r.X, r.Y));
            dc.PushTransform(new ScaleTransform(k, k));
            if (it.State == 1)
            {
                var pen = new Pen(b, 1.9) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round }; pen.Freeze();
                dc.DrawGeometry(null, pen, Geometry.Parse("M5,5.6 L12.4,12 L8.8,15.2 L8.8,2.8 L12.4,6 L5,12.4 M3.2,3.2 L14.8,14.8"));
            }
            else if (it.State == 2)
            {
                var pen = new Pen(b, 1.6); pen.Freeze();
                dc.DrawRoundedRectangle(null, pen, new Rect(0.8, 3.8, 14, 10.4), 3, 3);
                dc.DrawRoundedRectangle(b, null, new Rect(2.8, 5.8, 2.6, 6.4), 1, 1);
                dc.DrawRoundedRectangle(b, null, new Rect(15.6, 7.2, 1.8, 3.6), 0.9, 0.9);
            }
            else
            {
                var moon = new CombinedGeometry(GeometryCombineMode.Exclude, new EllipseGeometry(new Rect(1.5, 1.5, 15, 15)), new EllipseGeometry(new Rect(6.5, -2, 13, 13)));
                dc.DrawGeometry(b, null, moon);
            }
            dc.Pop(); dc.Pop();
        }

        static void DrawScreen(DrawingContext dc, FaceProject p, ShotSet s, Item it, FaceRenderer renderer, BitmapSource band, bool light, Rect rect)
        {
            var screen = rect;
            if (band != null)
            {
                double k = rect.Width / BandImg.Width;
                screen = new Rect(rect.X + BandScreen.X * k, rect.Y + BandScreen.Y * k, BandScreen.Width * k, BandScreen.Height * k);
            }
            // тінь-овал під екраном, ніби він стоїть на поверхні
            if (s.Shadow) GroundShadow(dc, rect, band != null ? (light ? 0.35 : 0.7) : (light ? 0.35 : 0.75));
            if (band != null) dc.DrawImage(band, rect);
            renderer.ColorVariant = it.Screen.Color;
            renderer.BluetoothOff = it.State == 1;
            renderer.LowBattery = it.State == 2;
            renderer.SlotChoice = it.Screen.Widgets;
            var dev = p.Meta.Device;
            var img = renderer.Render(Theme(p, it.Screen), Math.Max(1, Math.Ceiling(screen.Width * 2 / DevW))).Image;
            double r = band != null || s.Rounded ? dev.Corner * screen.Width / dev.Width : 0;
            dc.PushClip(new RectangleGeometry(screen, r, r));
            dc.DrawImage(img, screen);
            dc.Pop();
            if (band == null)
            {
                // тонкий світлий обідок по краю капсули
                var pen = new Pen(B("#FFFFFF", 0.08), 1); pen.Freeze();
                var rr = Math.Max(0, r - 0.5);
                dc.DrawRoundedRectangle(null, pen, new Rect(screen.X + 0.5, screen.Y + 0.5, screen.Width - 1, screen.Height - 1), rr, rr);
            }
        }

        static void GroundShadow(DrawingContext dc, Rect r, double alpha)
        {
            double w = r.Width * 0.76, h = 28;
            var c = Color.FromArgb((byte)(255 * 0.9 * alpha), 0, 0, 0);
            var g = new RadialGradientBrush(c, Color.FromArgb(0, 0, 0, 0)); g.Freeze();
            dc.DrawEllipse(g, null, new Point(r.X + r.Width / 2, r.Bottom), w / 2 + 6, (w / 2 + 6) * h / w);
        }
    }
}
