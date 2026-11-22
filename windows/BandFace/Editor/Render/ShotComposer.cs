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
                // стан — на самому екрані; обидва стани — два окремі екрани
                if (sc.Bluetooth && sc.Battery) { r.Add(new Item { Screen = sc, State = 1 }); r.Add(new Item { Screen = sc, State = 2 }); }
                else r.Add(new Item { Screen = sc, State = sc.Bluetooth ? 1 : sc.Battery ? 2 : 0 });
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

        /// <summary>Найбільша сторона готової картинки, pt (1920 px)</summary>
        const double MaxSide = 960;

        static int AutoColumns(int n) => n <= 5 ? Math.Max(1, n) : n <= 12 ? (n + 1) / 2 : 6;

        /// <summary>Задані формати — довша сторона 960 pt (1920 px), як і найбільша «Авто»</summary>
        static Size? Fixed(string format)
        {
            switch (format)
            {
                case "square": return new Size(960, 960);
                case "wide": return new Size(960, 540);
                default: return null;
            }
        }

        /// <summary>Рядок над назвою у два рядки (для 16:9): розрив ближче до середини, «10 • 11» не розривається</summary>
        static string[] SplitKicker(string text, Func<string, double> width)
        {
            var words = new List<string>();
            foreach (var w in text.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries))
                if (words.Count > 0 && (w == "•" || words[words.Count - 1].EndsWith("•"))) words[words.Count - 1] += " " + w; else words.Add(w);
            if (words.Count < 2) return new[] { text };
            string[] best = { text }; double bw = double.MaxValue;
            for (int i = 1; i < words.Count; i++)
            {
                string a = string.Join(" ", words.Take(i)), b = string.Join(" ", words.Skip(i));
                double m = Math.Max(width(a), width(b));
                if (m < bw) { bw = m; best = new[] { a, b }; }
            }
            return best;
        }

        /// <summary>Розкладка сітки: стовпці, ширина екрана, вузький режим (дрібніші підписи, стани — лише значком)</summary>
        struct Layout
        {
            public int Cols; public double W; public bool Narrow;
            /// <summary>Скільки екранів на картинці: два-три — розставлені ширше</summary>
            public int N;
            /// <summary>Масштаб текстів (у вузьких форматах тексти менші) і найширша мітка стану</summary>
            public double Ts, Pill;
            public double Gap => (Narrow ? 18 : N <= 2 ? 72 : N == 3 ? 46 : 30) * Ts;
            public double RowGap => 30 * Ts;
        }

        static double ItemWidth(ShotSet s, Layout l) =>
            Math.Max(CellBody(s, l.W).Width, s.Captions ? (l.Narrow ? l.W + 18 * l.Ts : Math.Max(l.W + 40 * l.Ts, l.Pill)) : 0);

        static Size GridSize(ShotSet s, Layout l, int n, double capH)
        {
            int rows = (n + l.Cols - 1) / l.Cols;
            var body = CellBody(s, l.W);
            return new Size(l.Cols * ItemWidth(s, l) + (l.Cols - 1) * l.Gap, rows * (body.Height + capH) + (rows - 1) * l.RowGap);
        }

        /// <summary>Ширина мітки стану в повному вигляді</summary>
        static double PillWidth(string text, double ts) => (12 + 20 + 7 + 14) * ts + Text(text, 17.8 * ts, FontWeights.Medium, Brushes.Black).WidthIncludingTrailingWhitespace;

        static readonly BitmapImage[] bands = new BitmapImage[2];
        static BitmapImage BandImage(bool dark)
        {
            int i = dark ? 1 : 0;
            if (bands[i] != null) return bands[i];
            var b = new BitmapImage();
            b.BeginInit();
            b.UriSource = new Uri("pack://application:,,,/Assets/" + (dark ? "ShotBandDark.png" : "ShotBandLight.png"));
            b.CacheOption = BitmapCacheOption.OnLoad;
            b.EndInit();
            b.Freeze();
            return bands[i] = b;
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
            s = s.Effective(p);
            var list = Items(s);
            if (list.Count == 0) return null;
            var bgc = BackgroundColors(p, s.Background);
            var pal = new Palette { Light = IsLight(bgc) };
            var fixedSize = Fixed(s.Format);
            // 16:9: назва ліворуч, екрани праворуч на всю висоту
            bool wide = fixedSize != null && s.Format == "wide";
            const double padX = 56;
            double padY = fixedSize == null ? 48 : 40;

            // шапка; у вузьких форматах (9:16) усі тексти зменшуються, щоб рядок над назвою й назва вміщалися
            string above = s.Above ?? AutoAbove(p), title = s.Title ?? AutoTitle(p), below = s.Below ?? AutoBelow(p);
            double titleBase = fixedSize == null ? 70 : wide ? 75 : 60;
            Spaced(above.ToUpperInvariant(), 18.4, pal.Sub, 3.4, out double aw1, out _);
            double need = Math.Max(above.Length == 0 ? 0 : aw1 + 2 * 58, title.Length == 0 ? 0 : Text(title, titleBase, FontWeights.ExtraBold, pal.Fg).WidthIncludingTrailingWhitespace);
            double ts = wide ? 0.8 : fixedSize is Size f0 ? Math.Min(1, (f0.Width - 2 * padX) / Math.Max(1, need)) : 1;
            var titleT = Text(title, titleBase * ts, FontWeights.ExtraBold, pal.Fg);
            var spaced = Spaced(above.ToUpperInvariant(), 18.4 * ts, pal.Sub, 3.4 * ts, out double sw, out double sh);
            var chips = below.Split(new[] { " · " }, StringSplitOptions.RemoveEmptyEntries);
            var chipT = chips.Select(c => Text(c, 19.5 * ts, FontWeights.Medium, pal.Sub)).ToList();
            double chipH = 36 * ts;
            double header = 0;
            if (above.Length > 0) header += sh;
            if (title.Length > 0) header += (header > 0 ? 14 * ts : 0) + titleT.Height;
            if (chips.Length > 0) header += (header > 0 ? 16 * ts : 0) + chipH;
            if (header > 0) header += 46 * ts;
            var creditT = Text(S.Get("shotCredit"), 19.2 * ts, FontWeights.Medium, pal.SubSoft);
            double footer = s.Credit ? 44 * ts + creditT.Height : 0;

            // ліва колонка 16:9: рядок над назвою у два рядки, назва, капсули, лінія і «Зроблено в BandFace»
            var kicker = new List<(List<(FormattedText, double)> t, double h)>();
            double colW = 0, colH = 0;
            const double colGap = 40, padL = 60, padR = 48;
            if (wide)
            {
                if (above.Length > 0)
                    foreach (var line in SplitKicker(above.ToUpperInvariant(), t => { Spaced(t, 17.2 * ts, pal.Sub, 2.8 * ts, out double w1, out _); return w1; }))
                    {
                        var sp = Spaced(line, 17.2 * ts, pal.Sub, 2.8 * ts, out double lw, out double lh);
                        kicker.Add((sp, lh)); colW = Math.Max(colW, lw);
                    }
                double chipsW = chipT.Sum(t => t.WidthIncludingTrailingWhitespace + 30 * ts) + Math.Max(0, chips.Length - 1) * 8 * ts;
                colW = Math.Min(300, Math.Max(Math.Max(colW, chipsW), Math.Max(s.Credit ? creditT.WidthIncludingTrailingWhitespace + 28 * ts : 0, 180)));
                if (titleT.WidthIncludingTrailingWhitespace > colW)
                    titleT = Text(title, titleBase * ts * colW / titleT.WidthIncludingTrailingWhitespace, FontWeights.ExtraBold, pal.Fg);
                colW = Math.Max(colW, titleT.WidthIncludingTrailingWhitespace);
                colH = kicker.Sum(k => k.h * 1.15);
                if (title.Length > 0) colH += (colH > 0 ? 12 * ts : 0) + titleT.Height;
                if (chips.Length > 0) colH += (colH > 0 ? 18 * ts : 0) + chipH;
                if (s.Credit) colH += (colH > 0 ? 30 * ts : 0) + 20 * ts + creditT.Height;
                header = 0; footer = 0;
            }

            int n = list.Count;
            double capH = s.Captions ? (list.Any(i => StateText(i) != null) ? 94 : 52) * ts : 0;
            double pill = list.Select(StateText).Where(t => t != null).Select(t => PillWidth(t, ts)).DefaultIfEmpty(0).Max();
            Layout L(int cols, double w, bool narrow) => new Layout { Cols = cols, W = w, Narrow = narrow, N = n, Ts = ts, Pill = pill };
            var lay = L(AutoColumns(n), ScreenWidth(0), false);
            Size canvas;
            if (fixedSize is Size fx)
            {
                var area = wide ? new Size(fx.Width - padL - colW - colGap - padR, fx.Height - 2 * padY)
                    : new Size(fx.Width - 2 * padX, fx.Height - 2 * padY - header - footer);
                var best = L(1, 10, false);
                foreach (var narrow in new[] { false, true })
                {
                    for (int c = 1; c <= n; c++)
                    {
                        double lo = 10, hi = 400;
                        for (int k = 0; k < 24; k++)
                        {
                            var m = (lo + hi) / 2;
                            var g = GridSize(s, L(c, m, narrow), n, capH);
                            if (g.Width <= area.Width && g.Height <= area.Height) lo = m; else hi = m;
                        }
                        if (lo > best.W) best = L(c, lo, narrow);
                    }
                    // вузький режим — лише коли звичайний дає зовсім дрібні екрани
                    if (best.W >= 90 * ts) break;
                }
                // заданий формат заповнюється повністю (розмір екранів — лише для «Авто»)
                best.W = Math.Min(Math.Floor(best.W), 300);
                lay = best;
                canvas = fx;
            }
            else
            {
                double minW = Math.Max(640, need + 2 * padX);
                Size Fit(Layout l)
                {
                    var g = GridSize(s, l, n, capH);
                    return new Size(Math.Max(g.Width + 2 * padX, minW), g.Height + 2 * padY + header + footer);
                }
                canvas = Fit(lay);
                // не більше 1920 px по довшій стороні (960 pt): більші картинки месенджери однаково зменшують;
                // замість зменшення всієї картинки — менші екрани, тексти лишаються того ж розміру
                if (Math.Max(canvas.Width, canvas.Height) > MaxSide)
                {
                    foreach (var narrow in new[] { false, true })
                    {
                        double lo = 30, hi = ScreenWidth(0);
                        for (int k = 0; k < 24; k++)
                        {
                            var m = (lo + hi) / 2;
                            var c = Fit(L(lay.Cols, m, narrow));
                            if (Math.Max(c.Width, c.Height) <= MaxSide) lo = m; else hi = m;
                        }
                        lay = L(lay.Cols, Math.Floor(lo), narrow);
                        if (lo >= 90) break;
                    }
                    canvas = Fit(lay);
                }
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
                double y0 = (canvas.Height - total) / 2, y = wide ? (canvas.Height - grid.Height) / 2 : y0;
                // місце під екрани по ширині
                double gx = wide ? padL + colW + colGap : 0, gw = wide ? canvas.Width - gx - padR : canvas.Width;
                void Credit(double x0, double cy)
                {
                    double icon = 20 * ts;
                    dc.PushTransform(new TranslateTransform(x0, cy + (creditT.Height - icon) / 2));
                    dc.PushTransform(new ScaleTransform(icon / 26.0, icon / 26.0));
                    dc.DrawGeometry(pal.SubSoft, null, (Geometry)Application.Current.Resources["BandGeometry"]);
                    dc.Pop(); dc.Pop();
                    dc.DrawText(creditT, new Point(x0 + icon + 8 * ts, cy));
                }
                if (wide)
                {
                    double cy = (canvas.Height - colH) / 2, start = cy;
                    foreach (var (sp, h) in kicker) { foreach (var (t, dx) in sp) dc.DrawText(t, new Point(padL + dx, cy)); cy += h * 1.15; }
                    if (title.Length > 0) { if (cy > start) cy += 12 * ts; dc.DrawText(titleT, new Point(padL - 2 * ts, cy)); cy += titleT.Height; }
                    if (chips.Length > 0)
                    {
                        if (cy > start) cy += 18 * ts;
                        double x = padL;
                        var pen = new Pen(pal.Line, 1); pen.Freeze();
                        foreach (var t in chipT)
                        {
                            double w = t.WidthIncludingTrailingWhitespace + 30 * ts;
                            dc.DrawRoundedRectangle(null, pen, new Rect(x + 0.5, cy + 0.5, w - 1, chipH - 1), chipH / 2, chipH / 2);
                            dc.DrawText(t, new Point(x + 15 * ts, cy + (chipH - t.Height) / 2));
                            x += w + 8 * ts;
                        }
                        cy += chipH;
                    }
                    if (s.Credit)
                    {
                        if (cy > start) { cy += 30 * ts; dc.DrawRectangle(pal.Line, null, new Rect(padL, cy, colW, 1)); }
                        cy += 20 * ts;
                        Credit(padL, cy);
                    }
                }
                void Center(FormattedText t, double yy) => dc.DrawText(t, new Point((canvas.Width - t.WidthIncludingTrailingWhitespace) / 2, yy));
                if (header > 0)
                {
                    if (above.Length > 0)
                    {
                        // розрідження літер: FormattedText його не вміє — рядок збирається з літер із проміжками
                        double x = (canvas.Width - sw) / 2;
                        foreach (var (t, dx) in spaced) dc.DrawText(t, new Point(x + dx, y));
                        double ly = y + sh / 2;
                        dc.DrawRectangle(pal.Line, null, new Rect(x - 58 * ts, ly, 40 * ts, 1.5));
                        dc.DrawRectangle(pal.Line, null, new Rect(x + sw + 18 * ts, ly, 40 * ts, 1.5));
                        y += sh;
                    }
                    if (title.Length > 0) { if (y > y0) y += 14 * ts; Center(titleT, y); y += titleT.Height; }
                    if (chips.Length > 0)
                    {
                        if (y > y0) y += 16 * ts;
                        var widths = chipT.Select(t => t.WidthIncludingTrailingWhitespace + 30 * ts).ToList();
                        double x = (canvas.Width - (widths.Sum() + (chips.Length - 1) * 8 * ts)) / 2;
                        var pen = new Pen(pal.Line, 1); pen.Freeze();
                        for (int i = 0; i < chipT.Count; i++)
                        {
                            var r = new Rect(x + 0.5, y + 0.5, widths[i] - 1, chipH - 1);
                            dc.DrawRoundedRectangle(null, pen, r, chipH / 2, chipH / 2);
                            dc.DrawText(chipT[i], new Point(x + 15 * ts, y + (chipH - chipT[i].Height) / 2));
                            x += widths[i] + 8 * ts;
                        }
                        y += chipH;
                    }
                    y += 46 * ts;
                }

                int rows = (n + lay.Cols - 1) / lay.Cols;
                for (int i = 0; i < n; i++)
                {
                    var it = list[i];
                    int r = i / lay.Cols, col = i % lay.Cols;
                    int inRow = r == rows - 1 ? n - r * lay.Cols : lay.Cols;
                    double rowX = gx + (gw - (inRow * iw + (inRow - 1) * lay.Gap)) / 2;
                    double cx = rowX + col * (iw + lay.Gap) + iw / 2;
                    double top = y + r * (body.Height + capH + lay.RowGap);
                    DrawScreen(dc, p, s, it, renderer, bandImg, pal.Light, new Rect(cx - body.Width / 2, top, body.Width, body.Height));
                    if (s.Captions) DrawCaption(dc, p, it, pal, lay.Narrow, ts, cx, iw, top + body.Height + 22 * ts);
                }
                if (s.Credit && !wide)
                    Credit((canvas.Width - (20 * ts + 8 * ts + creditT.WidthIncludingTrailingWhitespace)) / 2, y + grid.Height + 44 * ts);
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
        static void DrawCaption(DrawingContext dc, FaceProject p, Item it, Palette pal, bool narrow, double ts, double cx, double width, double top)
        {
            var nameT = Text(Name(p, it.Screen), (narrow ? 16 : 23) * ts, FontWeights.SemiBold, pal.Fg);
            nameT.MaxTextWidth = width; nameT.MaxLineCount = 1; nameT.Trimming = TextTrimming.CharacterEllipsis;
            nameT.TextAlignment = TextAlignment.Center;
            dc.DrawText(nameT, new Point(cx - width / 2, top));
            var st = StateText(it);
            if (st == null) return;
            var col = Imaging.ParseColor(pal.State(it));
            var colB = new SolidColorBrush(col); colB.Freeze();
            double pillY = top + nameT.Height + 9 * ts, pillH = 32 * ts, iconW = 20 * ts;
            var textT = Text(st, 17.8 * ts, FontWeights.Medium, colB);
            double w = narrow ? 38 * ts : PillWidth(st, ts);
            var bg = new SolidColorBrush(Color.FromArgb((byte)(255 * (pal.Light ? 0.12 : 0.15)), col.R, col.G, col.B)); bg.Freeze();
            dc.DrawRoundedRectangle(bg, null, new Rect(cx - w / 2, pillY, w, pillH), pillH / 2, pillH / 2);
            var ir = new Rect(narrow ? cx - iconW / 2 : cx - w / 2 + 12 * ts, pillY + (pillH - iconW) / 2, iconW, iconW);
            StateIcon(dc, it.State, ir, colB, null);
            if (!narrow) dc.DrawText(textT, new Point(ir.Right + 7 * ts, pillY + (pillH - textT.Height) / 2));
        }

        /// <summary>Значок стану в квадраті r: Bluetooth від'єднано, батарея, місяць (AOD); поле 18×18</summary>
        /// <summary>Значок стану в квадраті r (поле 26×26): перекреслений Bluetooth, батарея з низьким зарядом, місяць (AOD).
        /// low — колір смужки заряду (у кнопках — червоний), null — як значок</summary>
        public static void StateIcon(DrawingContext dc, int state, Rect r, Brush b, Brush low)
        {
            double k = r.Width / 26;
            dc.PushTransform(new TranslateTransform(r.X, r.Y));
            dc.PushTransform(new ScaleTransform(k, k));
            if (state == 1)
            {
                var pen = new Pen(b, 2.3) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round }; pen.Freeze();
                dc.DrawGeometry(null, pen, Geometry.Parse("M8.2,8.6 L17.4,16.6 L12.8,20.8 L12.8,5.2 L17.4,9.4 L8.2,17.4 M5,5 L21,21"));
            }
            else if (state == 2)
            {
                var body = new CombinedGeometry(GeometryCombineMode.Exclude, new RectangleGeometry(new Rect(3, 6.5, 19, 13), 3, 3), new RectangleGeometry(new Rect(5.3, 8.8, 14.4, 8.4), 0.9, 0.9));
                dc.DrawGeometry(b, null, body);
                dc.DrawRoundedRectangle(b, null, new Rect(23.2, 10.6, 1.4, 4.8), 0.7, 0.7);
                dc.DrawRoundedRectangle(low ?? b, null, new Rect(6.8, 10.3, 3.4, 5.4), 1, 1);
            }
            else
            {
                var moon = new CombinedGeometry(GeometryCombineMode.Exclude, new EllipseGeometry(new Rect(3, 3, 20, 20)), new EllipseGeometry(new Rect(9.6, -1.6, 17.4, 17.4)));
                dc.DrawGeometry(b, null, moon);
            }
            dc.Pop(); dc.Pop();
        }

        /// <summary>Значки меню знімка (поле 26×26): 0 — із закругленими кутами, 1 — без закруглень, 2 — набір</summary>
        public static ImageSource MenuIcon(int kind, Brush b)
        {
            var dg = new DrawingGroup();
            using (var dc = dg.Open())
            {
                dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, 26, 26));
                var pen = new Pen(b, 1.8); pen.Freeze();
                var thin = new Pen(b, 1.6) { }; thin.Freeze();
                if (kind < 2)
                {
                    double rr = kind == 0 ? 5 : 1.6;
                    dc.DrawRoundedRectangle(null, pen, new Rect(8, 2, 10, 22), rr, rr);
                    dc.DrawRoundedRectangle(b, null, new Rect(10.6, 8.2, 4.8, 1.8), 0.9, 0.9);
                    dc.DrawRoundedRectangle(b, null, new Rect(10.6, 11.6, 4.8, 1.8), 0.9, 0.9);
                    dc.PushOpacity(0.55);
                    dc.DrawRoundedRectangle(b, null, new Rect(11.6, 15, 2.8, 1.6), 0.8, 0.8);
                    dc.Pop();
                }
                else
                {
                    dc.PushOpacity(0.55);
                    dc.DrawRoundedRectangle(null, thin, new Rect(1.6, 6, 6.4, 14), 3.2, 3.2);
                    dc.DrawRoundedRectangle(null, thin, new Rect(18, 6, 6.4, 14), 3.2, 3.2);
                    dc.Pop();
                    dc.DrawRoundedRectangle(null, pen, new Rect(9, 3, 8, 20), 4, 4);
                    dc.DrawRoundedRectangle(b, null, new Rect(11.2, 9.4, 3.6, 1.6), 0.8, 0.8);
                    dc.DrawRoundedRectangle(b, null, new Rect(11.2, 12.4, 3.6, 1.6), 0.8, 0.8);
                }
            }
            dg.Freeze();
            var img = new DrawingImage(dg); img.Freeze();
            return img;
        }

        /// <summary>Значок стану картинкою (кнопки під карткою)</summary>
        public static ImageSource StateImage(int state, double size, Brush b, Brush low)
        {
            var dg = new DrawingGroup();
            using (var dc = dg.Open())
            {
                dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, size, size));
                StateIcon(dc, state, new Rect(0, 0, size, size), b, low);
            }
            dg.Freeze();
            var img = new DrawingImage(dg); img.Freeze();
            return img;
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
            if (band != null)
            {
                // тінь браслета — за його формою: розмита копія силуету, зсунута донизу
                if (s.Shadow) BandShadow(dc, band, rect, light ? 0.22 : 0.55);
                dc.DrawImage(band, rect);
            }
            else if (s.Shadow) GroundShadow(dc, rect, light ? 0.35 : 0.75);
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

        static readonly Dictionary<(BitmapSource, double), BitmapSource> shadows = new Dictionary<(BitmapSource, double), BitmapSource>();

        static void BandShadow(DrawingContext dc, BitmapSource band, Rect r, double alpha)
        {
            if (!shadows.TryGetValue((band, alpha), out var sh))
            {
                // силует браслета чорним, розмитий
                var dv = new DrawingVisual();
                int pw = band.PixelWidth / 2 + 40, ph = band.PixelHeight / 2 + 40;
                using (var c = dv.RenderOpen())
                {
                    c.PushOpacityMask(new ImageBrush(band) { Stretch = Stretch.Fill, Viewbox = new Rect(0, 0, 1, 1), Viewport = new Rect(20.0 / pw, 20.0 / ph, (pw - 40.0) / pw, (ph - 40.0) / ph) });
                    c.DrawRectangle(new SolidColorBrush(Color.FromArgb((byte)(255 * alpha), 0, 0, 0)), null, new Rect(0, 0, pw, ph));
                    c.Pop();
                }
                dv.Effect = new System.Windows.Media.Effects.BlurEffect { Radius = 11, KernelType = System.Windows.Media.Effects.KernelType.Gaussian };
                var rtb = new RenderTargetBitmap(pw, ph, 96, 96, PixelFormats.Pbgra32);
                rtb.Render(dv);
                rtb.Freeze();
                shadows[(band, alpha)] = sh = rtb;
            }
            double k = r.Width / (band.PixelWidth / 2.0);
            dc.DrawImage(sh, new Rect(r.X - 20 * k, r.Y - 20 * k + 14, r.Width + 40 * k, r.Height + 40 * k));
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
