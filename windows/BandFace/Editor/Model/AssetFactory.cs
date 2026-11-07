// SPDX-License-Identifier: MIT
// Генерація картинок для нових елементів: цифри з будь-якого шрифту, кільця, смуги, стрілки.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using BandFace.Faces;

namespace BandFace.Creator
{
    /// <summary>Шрифти: усі встановлені у Windows і додані користувачем файли (.ttf / .otf / .ttc).</summary>
    static class FontLibrary
    {
        public static string Folder
        {
            get
            {
                var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BandFace", "Creator", "Fonts");
                Directory.CreateDirectory(d);
                return d;
            }
        }

        static Dictionary<string, FontFamily> user;
        static readonly Dictionary<string, string> files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static string Pending => Path.Combine(Folder, "remove.txt");
        static readonly string[] Exts = { ".ttf", ".otf", ".ttc" };

        /// <summary>Додані користувачем сімейства: назва → FontFamily з файла</summary>
        public static Dictionary<string, FontFamily> User
        {
            get
            {
                if (user != null) return user;
                user = new Dictionary<string, FontFamily>(StringComparer.OrdinalIgnoreCase);
                files.Clear();
                // файли, які не вдалося видалити минулого разу (Windows тримала їх відкритими)
                try
                {
                    if (File.Exists(Pending))
                    {
                        foreach (var f in File.ReadAllLines(Pending)) try { if (f.Length > 0 && File.Exists(f)) File.Delete(f); } catch (Exception) { }
                        File.Delete(Pending);
                    }
                }
                catch (Exception) { }
                foreach (var file in Directory.GetFiles(Folder).Where(f => Exts.Contains(Path.GetExtension(f).ToLowerInvariant())))
                {
                    try
                    {
                        foreach (var f in Fonts.GetFontFamilies(new Uri(file)))
                        {
                            var n = Name(f);
                            if (user.ContainsKey(n)) continue;
                            user[n] = f;
                            files[n] = file;
                        }
                    }
                    catch (Exception) { }
                }
                return user;
            }
        }

        /// <summary>Прибирає доданий шрифт; false — файл зайнятий, видалиться під час наступного запуску</summary>
        public static bool Remove(string name)
        {
            if (!User.ContainsKey(name) || !files.TryGetValue(name, out var file)) return true;
            user.Remove(name);
            try { File.Delete(file); return true; }
            catch (Exception)
            {
                try { File.AppendAllText(Pending, file + Environment.NewLine); } catch (Exception) { }
                return false;
            }
        }

        public static string Name(FontFamily f)
        {
            var names = f.FamilyNames;
            if (names.TryGetValue(System.Windows.Markup.XmlLanguage.GetLanguage("en-us"), out var n)) return n;
            foreach (var kv in names) return kv.Value;
            var s = f.Source;
            int i = s.LastIndexOf('#');
            return i >= 0 ? s.Substring(i + 1) : s;
        }

        /// <summary>Усі назви для вибору: спершу додані, далі системні за абеткою</summary>
        public static List<string> AllNames()
        {
            var sys = Fonts.SystemFontFamilies.Select(Name).Distinct().OrderBy(x => x, StringComparer.CurrentCultureIgnoreCase);
            return User.Keys.OrderBy(x => x).Concat(sys.Where(x => !User.ContainsKey(x))).ToList();
        }

        /// <summary>Копіює файл шрифту в бібліотеку; повертає назви нових сімейств</summary>
        public static List<string> Add(string path)
        {
            var dst = Path.Combine(Folder, Path.GetFileName(path));
            if (!string.Equals(Path.GetFullPath(path), Path.GetFullPath(dst), StringComparison.OrdinalIgnoreCase)) File.Copy(path, dst, true);
            var before = new HashSet<string>(User.Keys, StringComparer.OrdinalIgnoreCase);
            user = null;
            return User.Keys.Where(k => !before.Contains(k)).ToList();
        }

        public static FontFamily Family(string name)
        {
            if (string.IsNullOrEmpty(name)) return new FontFamily("Segoe UI");
            return User.TryGetValue(name, out var f) ? f : new FontFamily(name);
        }

        /// <summary>Які набори символів є в шрифті: цифри, латиниця, кирилиця (для підказки у виборі)</summary>
        public static string Coverage(string name)
        {
            try
            {
                var tf = new Typeface(Family(name), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
                if (!tf.TryGetGlyphTypeface(out var g)) return "";
                var m = g.CharacterToGlyphMap;
                var parts = new List<string>();
                if ("0123456789".All(c => m.ContainsKey(c))) parts.Add("0–9");
                if ("AZaz".All(c => m.ContainsKey(c))) parts.Add("Lat");
                if ("АЯаяЇЄҐ".All(c => m.ContainsKey(c))) parts.Add("Кир");
                return string.Join(" · ", parts);
            }
            catch (Exception) { return ""; }
        }
    }

    static class AssetFactory
    {
        static FontWeight Weight(int w) => FontWeight.FromOpenTypeWeight(Math.Max(1, Math.Min(999, w)));

        /// <summary>Шрифт генератора: вибраний або відповідник iOS-стилю</summary>
        public static Typeface FontOf(Generator g)
        {
            if (!string.IsNullOrEmpty(g.Font)) return new Typeface(FontLibrary.Family(g.Font), FontStyles.Normal, Weight(g.Weight), FontStretches.Normal);
            switch (g.Style)
            {
                case "condensed": return new Typeface(new FontFamily("Bahnschrift"), FontStyles.Normal, Weight(g.Weight), FontStretches.Condensed);
                case "mono": return new Typeface(new FontFamily("Consolas"), FontStyles.Normal, Weight(g.Weight), FontStretches.Normal);
                case "rounded":
                    if (Fonts.SystemFontFamilies.Any(f => f.Source == "Arial Rounded MT Bold"))
                        return new Typeface(new FontFamily("Arial Rounded MT Bold"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
                    return new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, Weight(g.Weight), FontStretches.Normal);
                default: return new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, Weight(g.Weight), FontStretches.Normal);
            }
        }

        static FormattedText Text(string s, Typeface tf, double size, Brush b)
            => new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, tf, size, b, 1.0);

        static double K(Generator g) => Math.Max(0.3, Math.Min(2, g.WidthPct / 100.0));

        /// <summary>Поле навколо знака під обвідку й тінь</summary>
        static int Pad(Generator g) => !g.Styled ? 0 : (int)Math.Ceiling(Math.Max(0, g.Outline) + Math.Max(Math.Abs(g.ShadowX), Math.Abs(g.ShadowY))) + 1;

        /// <summary>Текст з ефектами набору цифр: тінь → обвідка (зовнішня) → заливка (колір або градієнт згори донизу).
        /// Ширина літер стискає/розтягує знак відносно його середини.</summary>
        static void Draw(DrawingContext dc, FormattedText t, Point at, Generator g)
        {
            if (!g.Styled) { dc.DrawText(t, at); return; }
            var geo = t.BuildGeometry(at);
            double k = K(g);
            if (Math.Abs(k - 1) > 0.001)
            {
                geo = geo.Clone();
                geo.Transform = new ScaleTransform(k, 1, at.X + t.WidthIncludingTrailingWhitespace / 2, 0);
            }
            if (g.ShadowX != 0 || g.ShadowY != 0)
            {
                dc.PushTransform(new TranslateTransform(g.ShadowX, g.ShadowY));
                dc.DrawGeometry(Imaging.Brush(g.ShadowColor, 0.6), g.Outline > 0 ? new Pen(Imaging.Brush(g.ShadowColor, 0.6), g.Outline * 2) { LineJoin = PenLineJoin.Round } : null, geo);
                dc.Pop();
            }
            if (g.Outline > 0) dc.DrawGeometry(null, new Pen(Imaging.Brush(g.OutlineColor), g.Outline * 2) { LineJoin = PenLineJoin.Round }, geo);
            Brush fill = string.IsNullOrEmpty(g.Color2) ? (Brush)Imaging.Brush(g.Color)
                : new LinearGradientBrush(Imaging.ParseColor(g.Color), Imaging.ParseColor(g.Color2), new Point(0, 0), new Point(0, 1));
            dc.DrawGeometry(fill, null, geo);
        }

        /// <summary>Кадри «0»…«9» однакового розміру, щільно по висоті цифр (межі — за справжніми пікселями).</summary>
        public static List<RgbaImage> DigitFrames(Generator g)
        {
            var tf = FontOf(g);
            var brush = Imaging.Brush(g.Color);
            double size = Math.Max(4, g.FontSize);
            double adv = 0, lh = 0;
            for (int d = 0; d <= 9; d++)
            {
                var t = Text(d.ToString(), tf, size, brush);
                adv = Math.Max(adv, t.WidthIncludingTrailingWhitespace);
                lh = Math.Max(lh, t.Height);
            }
            int pad = Pad(g);
            int w = (int)Math.Ceiling(adv * K(g)) + 2 + pad * 2;
            lh = Math.Ceiling(lh);
            int tall = (int)(lh * 2) + pad * 2;
            double top = lh / 2 + pad;
            var full = new List<RgbaImage>();
            for (int d = 0; d <= 9; d++)
            {
                var t = Text(d.ToString(), tf, size, brush);
                full.Add(Imaging.Render(w, tall, dc => Draw(dc, t, new Point((w - t.WidthIncludingTrailingWhitespace) / 2, top), g)));
            }
            int minY = tall, maxY = -1;
            foreach (var img in full)
                for (int y = 0; y < tall; y++)
                    for (int x = 0; x < w; x++)
                        if (img.Px[(y * w + x) * 4 + 3] != 0) { if (y < minY) minY = y; if (y > maxY) maxY = y; break; }
            if (maxY < minY) return full;
            int y0 = Math.Max(0, minY - 1), y1 = Math.Min(tall - 1, maxY + 1), h = y1 - y0 + 1;
            return full.Select(img => new RgbaImage(w, h, img.Px.Slice(y0 * w * 4, h * w * 4))).ToList();
        }

        /// <summary>Напис: рядок вибраним шрифтом і кольором, щільно обрізаний за справжніми пікселями (поле 1 px).
        /// Текст на браслеті — лише картинками: власний текст браслета (DataItemText) на Smart Band 10 не перевірений.</summary>
        public static RgbaImage LabelImage(Generator g)
        {
            var t = (g.Text ?? "").Trim();
            if (t.Length == 0) return null;
            var tf = FontOf(g);
            var s = Text(t, tf, Math.Max(4, g.FontSize), Imaging.Brush(g.Color));
            int pad = Pad(g);
            double tw = s.WidthIncludingTrailingWhitespace;
            int w = (int)Math.Ceiling(tw * K(g)) + 8 + pad * 2;
            double lh = Math.Ceiling(s.Height);
            int tall = (int)(lh * 2) + pad * 2;
            var full = Imaging.Render(w, tall, dc => Draw(dc, s, new Point((w - tw) / 2, lh / 2 + pad), g));
            int minX = w, maxX = -1, minY = tall, maxY = -1;
            for (int y = 0; y < tall; y++)
                for (int x = 0; x < w; x++)
                    if (full.Px[(y * w + x) * 4 + 3] != 0)
                    {
                        if (x < minX) minX = x; if (x > maxX) maxX = x;
                        if (y < minY) minY = y; if (y > maxY) maxY = y;
                    }
            if (maxX < minX) return null;
            int x0 = Math.Max(0, minX - 1), x1 = Math.Min(w - 1, maxX + 1), y0 = Math.Max(0, minY - 1), y1 = Math.Min(tall - 1, maxY + 1);
            int cw = x1 - x0 + 1, ch = y1 - y0 + 1;
            var px = new byte[cw * ch * 4];
            for (int y = 0; y < ch; y++) Buffer.BlockCopy(full.Px, ((y0 + y) * w + x0) * 4, px, y * cw * 4, cw * 4);
            return new RgbaImage(cw, ch, px);
        }

        /// <summary>Значок одиниці («%», «°», «км») тим самим шрифтом і кольором, тієї ж висоти, що й цифри.</summary>
        public static RgbaImage UnitImage(string text, Generator g)
        {
            var t = (text ?? "").Trim();
            if (t.Length == 0) return null;
            var digits = DigitFrames(g);
            if (digits.Count == 0) return null;
            var digit = digits[0];
            var tf = FontOf(g);
            var brush = Imaging.Brush(g.Color);
            double size = Math.Max(4, g.FontSize);
            var s = Text(t, tf, size, brush);
            var z = Text("0", tf, size, brush);
            double lh = Math.Ceiling(Math.Max(s.Height, z.Height));
            int pad = Pad(g);
            double sw = s.WidthIncludingTrailingWhitespace;
            int w = (int)Math.Ceiling(sw * K(g)) + 4 + pad * 2;
            int tall = (int)(lh * 2) + pad * 2;
            double top = lh / 2 + pad;
            var full = Imaging.Render(w, tall, dc => Draw(dc, s, new Point((w - sw) / 2, top), g));
            // та сама вертикальна вирізка, що й у цифр: шукаємо її за кадром «0»
            var zero = Imaging.Render(digit.W, tall, dc => Draw(dc, z, new Point((digit.W - z.WidthIncludingTrailingWhitespace) / 2, top), g));
            int y0 = tall;
            for (int y = 0; y < tall && y0 == tall; y++)
                for (int x = 0; x < digit.W; x++)
                    if (zero.Px[(y * digit.W + x) * 4 + 3] != 0) { y0 = y; break; }
            y0 = Math.Max(0, y0 - 1);
            int h = digit.H;
            if (y0 + h > tall) return null;
            return new RgbaImage(w, h, full.Px.Slice(y0 * w * 4, h * w * 4));
        }

        /// <summary>Кільце: повне коло заданого кольору (для дуги й фону дуги).</summary>
        public static RgbaImage Ring(double radius, double width, string color)
        {
            int size = (int)Math.Ceiling(radius * 2 + width + 4);
            double m = size / 2.0;
            var pen = new Pen(Imaging.Brush(color), width);
            return Imaging.Render(size, size, dc => dc.DrawEllipse(null, pen, new Point(m, m), radius, radius));
        }

        static Point OnCircle(double m, double r, double deg)
        {
            double t = deg * Math.PI / 180;
            return new Point(m + r * Math.Sin(t), m - r * Math.Cos(t));
        }

        /// <summary>Дуга від start на range градусів (0° — угорі, за годинниковою; від'ємна — проти).
        /// Розмір картинки — як у повного кільця, центр посередині (pivot не залежить від кута).</summary>
        public static RgbaImage ArcSegment(double radius, double width, string color, double start, double range, bool round)
        {
            if (Math.Abs(range) >= 359.99) return Ring(radius, width, color);
            int size = (int)Math.Ceiling(radius * 2 + width + 4);
            double m = size / 2.0;
            var cap = round ? PenLineCap.Round : PenLineCap.Flat;
            var pen = new Pen(Imaging.Brush(color), width) { StartLineCap = cap, EndLineCap = cap };
            var fig = new PathFigure { StartPoint = OnCircle(m, radius, start), IsClosed = false };
            fig.Segments.Add(new System.Windows.Media.ArcSegment(OnCircle(m, radius, start + range), new Size(radius, radius), 0, Math.Abs(range) > 180,
                range >= 0 ? SweepDirection.Clockwise : SweepDirection.Counterclockwise, true));
            var g = new PathGeometry();
            g.Figures.Add(fig);
            return Imaging.Render(size, size, dc => { if (Math.Abs(range) > 0.01) dc.DrawGeometry(null, pen, g); });
        }

        /// <summary>Лінія під будь-яким кутом (0° — праворуч, 90° — донизу). Повертає картинку й кінці лінії в ній.</summary>
        public static RgbaImage LineSegment(double length, double width, string color, double angle, bool round, out Point start, out Point end)
        {
            double t = angle * Math.PI / 180;
            double dx = Math.Cos(t) * length, dy = Math.Sin(t) * length;
            // майже горизонтальна/вертикальна — рівно, без «сходинки» в пів пікселя
            if (Math.Abs(dx) < 0.01) dx = 0;
            if (Math.Abs(dy) < 0.01) dy = 0;
            double pad = width / 2 + 1;
            int w = (int)Math.Ceiling(Math.Abs(dx) + pad * 2), h = (int)Math.Ceiling(Math.Abs(dy) + pad * 2);
            var s = new Point(pad - Math.Min(0, dx), pad - Math.Min(0, dy));
            var e = new Point(s.X + dx, s.Y + dy);
            start = s; end = e;
            var cap = round ? PenLineCap.Round : PenLineCap.Flat;
            var pen = new Pen(Imaging.Brush(color), width) { StartLineCap = cap, EndLineCap = cap };
            return Imaging.Render(w, h, dc => dc.DrawLine(pen, s, e));
        }

        /// <summary>Смуга для лінійної шкали.</summary>
        public static RgbaImage Bar(double length, double width, string color)
        {
            return Imaging.Render((int)Math.Ceiling(length), (int)Math.Ceiling(width),
                dc => dc.DrawRoundedRectangle(Imaging.Brush(color), null, new Rect(0, 0, length, width), width / 2, width / 2));
        }

        /// <summary>Стрілка: заокруглена смужка, вісь обертання — внизу по центру.</summary>
        public static RgbaImage Hand(double length, double width, string color)
        {
            int w = (int)Math.Ceiling(width + 2), h = (int)Math.Ceiling(length + width + 2);
            return Imaging.Render(w, h, dc => dc.DrawRoundedRectangle(Imaging.Brush(color), null, new Rect(1, 1, width, length + width), width / 2, width / 2));
        }

        public static RgbaImage Dot(int d, string color)
            => Imaging.Render(d, d, dc => dc.DrawEllipse(Imaging.Brush(color), null, new Point(d / 2.0, d / 2.0), d / 2.0, d / 2.0));

        public static RgbaImage Fill(int w, int h, string color)
            => Imaging.Render(w, h, dc => dc.DrawRectangle(Imaging.Brush(color), null, new Rect(0, 0, w, h)));
    }
}
