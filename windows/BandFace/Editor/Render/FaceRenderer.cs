// SPDX-License-Identifier: MIT
// Малює тему циферблата так, як її покаже браслет (з пробними даними), і повертає рамки шарів для вибору й перетягування.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BandFace.Faces;

namespace BandFace.Creator
{
    public sealed class LayerBox
    {
        public XNode Layout;
        public Rect Rect;
    }

    public sealed class RenderResult
    {
        public BitmapSource Image;
        public List<LayerBox> Boxes;
    }

    sealed class FaceRenderer
    {
        readonly FaceProject p;
        public bool Live;
        /// <summary>Час анімації, с: який кадр показує кожен Sprite</summary>
        public double Time;
        /// <summary>Тимчасові позиції шарів під час перетягування (без зміни маніфесту)</summary>
        public readonly Dictionary<XNode, Point> Overrides = new Dictionary<XNode, Point>();
        /// <summary>Кольоровий варіант: 0 — основний, далі за colorGroupTable</summary>
        public int ColorVariant;

        public FaceRenderer(FaceProject p) { this.p = p; }

        /// <summary>Ресурс за посиланням; для картинок — версія вибраного кольорового варіанта, якщо вона є</summary>
        XNode Pick(string r)
        {
            var b = p.ResourceRef(r);
            if (b == null || ColorVariant <= 0 || (b.Tag != "Image" && b.Tag != "ImageArray")) return b;
            return ColorVariants.Variant(p, b, ColorVariant) ?? b;
        }

        // MARK: Картинки

        public BitmapSource Image(string src)
        {
            if (src == null) return null;
            var path = MemoryStorage.Normalize(src);
            return p.Images.Get(path, () =>
            {
                var d = p.File(path);
                var png = d == null ? null : Png.Decode(d);
                return png?.ToBitmap();
            });
        }

        public List<BitmapSource> Frames(XNode arr)
        {
            var o = new List<BitmapSource>();
            if (arr == null) return o;
            if (arr.Tag == "Image") { var i = Image(arr.Str("src")); if (i != null) o.Add(i); return o; }
            foreach (var c in arr.All("Image")) { var i = Image(c.Str("src")); if (i != null) o.Add(i); }
            return o;
        }

        // MARK: Малювання

        /// <summary>Тема на полотні розміру пристрою. layers — лише шари з цими номерами; opaque: false — без фону теми.</summary>
        public RenderResult Render(int theme, double scale, Func<int, bool> layers = null, bool opaque = true)
        {
            var dev = p.Meta.Device;
            var boxes = new List<LayerBox>();
            var dv = new DrawingVisual();
            RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
            TextOptions.SetTextRenderingMode(dv, TextRenderingMode.Grayscale);
            using (var dc = dv.RenderOpen())
            {
                dc.PushTransform(new ScaleTransform(scale, scale));
                if (opaque) dc.DrawRectangle(Imaging.Brush(p.Theme(theme)?.Str("bgColor") ?? "#000000"), null, new Rect(0, 0, dev.Width, dev.Height));
                dc.PushClip(new RectangleGeometry(new Rect(0, 0, dev.Width, dev.Height)));
                var ls = p.Layouts(theme);
                for (int i = 0; i < ls.Count; i++)
                {
                    if (layers != null && !layers(i)) continue;
                    boxes.Add(Box(ls[i], dc));
                }
                dc.Pop();
                dc.Pop();
            }
            int w = Math.Max(1, (int)Math.Round(dev.Width * scale)), h = Math.Max(1, (int)Math.Round(dev.Height * scale));
            var rtb = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
            rtb.Render(dv);
            rtb.Freeze();
            return new RenderResult { Image = rtb, Boxes = boxes };
        }

        LayerBox Box(XNode l, DrawingContext dc)
        {
            Point o;
            if (!Overrides.TryGetValue(l, out o)) o = new Point(l.Int("x"), l.Int("y"));
            var r = Draw(Pick(l.Str("ref")), o, dc, 0);
            return new LayerBox { Layout = l, Rect = r ?? new Rect(o.X, o.Y, 16, 16) };
        }

        /// <summary>Рамки шарів теми без малювання — для інспектора й вирівнювання</summary>
        public List<LayerBox> Boxes(int theme) => p.Layouts(theme).Select(l => Box(l, null)).ToList();

        int Value(XNode res) => SampleData.Value(res.Str("source") ?? "", Live, p.Meta.Demo);

        static void Put(DrawingContext dc, ImageSource img, Rect r) { if (dc != null) dc.DrawImage(img, r); }

        static Rect Union(Rect? a, Rect b) => a.HasValue ? Rect.Union(a.Value, b) : b;

        /// <summary>Малює ресурс; повертає рамку (dc == null — лише вимірювання).</summary>
        public Rect? Draw(XNode res, Point o, DrawingContext dc, int depth)
        {
            if (res == null || depth >= 6) return null;
            switch (res.Tag)
            {
                case "Image":
                {
                    var img = Image(res.Str("src"));
                    if (img == null) return null;
                    var r = new Rect(o.X, o.Y, img.PixelWidth, img.PixelHeight);
                    Put(dc, img, r); return r;
                }
                case "ImageArray":
                {
                    var img = Frames(res).FirstOrDefault();
                    if (img == null) return null;
                    var r = new Rect(o.X, o.Y, img.PixelWidth, img.PixelHeight);
                    Put(dc, img, r); return r;
                }
                case "Sprite":
                {
                    var fr = Frames(Pick(res.Str("ref")));
                    if (fr.Count == 0) return null;
                    var img = fr[SpriteFrame(res, fr.Count, Time)];
                    var r = new Rect(o.X, o.Y, img.PixelWidth, img.PixelHeight);
                    Put(dc, img, r); return r;
                }
                case "DataItemImageNumber": return DrawNumber(res, o, dc);
                case "DataItemImageValues":
                {
                    var fr = Frames(Pick(res.Str("ref")));
                    if (fr.Count == 0) return null;
                    var prm = res.All("Param").Select(x => x.Int("value")).ToList();
                    int v = Value(res), idx = 0;
                    // без порогів (Param) браслет бере картинку за номером: значення 3 — картинка 3
                    if (prm.Count == 0) idx = Math.Max(0, v);
                    for (int i = 0; i < prm.Count; i++) if (v >= prm[i]) idx = i;
                    var img = fr[Math.Min(idx, fr.Count - 1)];
                    var r = new Rect(o.X, o.Y, img.PixelWidth, img.PixelHeight);
                    Put(dc, img, r); return r;
                }
                case "DataItemPointer": return DrawPointer(res, o, dc);
                case "DataItemArcProgressBar": return DrawArc(res, o, dc);
                case "DataItemLineProgressBar": return DrawLine(res, o, dc);
                case "DataItemText": return DrawText(res, o, dc);
                case "Widget":
                {
                    Rect? u = null;
                    foreach (var it in res.All("Item"))
                    {
                        var r = Draw(Pick(it.Str("ref")), new Point(o.X + it.Int("x"), o.Y + it.Int("y")), dc, depth + 1);
                        if (r.HasValue) u = Union(u, r.Value);
                    }
                    if (res.Has("w") && res.Has("h")) u = new Rect(o.X, o.Y, Math.Max(0, res.Int("w")), Math.Max(0, res.Int("h")));
                    return u;
                }
                case "Slot":
                {
                    var it = res.All("Item").FirstOrDefault();
                    return it == null ? (Rect?)null : Draw(Pick(it.Str("ref")), o, dc, depth + 1);
                }
                default: return null;
            }
        }

        /// <summary>Кадр анімації: interval мс на кадр; repeatCount 0 — без кінця, інакше після повторів лишається останній</summary>
        public static int SpriteFrame(XNode res, int count, double time)
        {
            int step = (int)(time * 1000) / Math.Max(1, res.Int("interval", 100));
            int repeats = res.Int("repeatCount");
            if (repeats > 0 && step >= count * repeats) return count - 1;
            return step % count;
        }

        double Fraction(XNode res)
        {
            double v = Value(res);
            double start = res.Has("valueStartSource") ? 0 : res.Int("valueStart");
            double range = res.Has("valueRangeSource") ? 100 : res.Int("valueRange");
            if (range == 0) return 0;
            return Math.Min(Math.Max((v - start) / range, 0), 1);
        }

        Rect? DrawNumber(XNode res, Point o, DrawingContext dc)
        {
            var fr = Frames(Pick(res.Str("ref")));
            // кадрів може бути менше за 10: так роблять перемикачі стану (2 кадри для «не турбувати», Bluetooth)
            if (fr.Count == 0) return null;
            int total = res.Int("totalDigits");
            var s = Math.Abs(Value(res)).ToString(CultureInfo.InvariantCulture);
            if (res.Bool("leadingZero") && total > 0 && s.Length < total) s = new string('0', total - s.Length) + s;
            if (total > 0 && s.Length > total) s = s.Substring(s.Length - total);
            double space = (sbyte)res.Int("space");
            double fw = fr[0].PixelWidth, fh = fr[0].PixelHeight;
            var unit = Image(Pick(res.Str("unitIcon"))?.Str("src"));
            double contentW = s.Length * fw + Math.Max(0, s.Length - 1) * space;
            if (unit != null) contentW += unit.PixelWidth;
            // x макета — точка прив'язки, як на браслеті: left — лівий край числа, center — середина, right — правий край
            double x = o.X;
            switch (res.Str("align"))
            {
                case "right": case "flex-end": x = o.X - contentW; break;
                case "center": x = o.X - contentW / 2; break;
            }
            var r = new Rect(x, o.Y, contentW, fh);
            foreach (var ch in s)
            {
                int d = ch - '0';
                if (d >= 0 && d < fr.Count) Put(dc, fr[d], new Rect(x, o.Y, fw, fh));
                x += fw + space;
            }
            if (unit != null)
            {
                var ur = new Rect(x - space, o.Y, unit.PixelWidth, unit.PixelHeight);
                Put(dc, unit, ur);
                return Rect.Union(r, ur);
            }
            return r;
        }

        Rect? DrawPointer(XNode res, Point o, DrawingContext dc)
        {
            var img = Frames(Pick(res.Str("ref"))).FirstOrDefault();
            if (img == null) return null;
            double px = res.Int("pivotX"), py = res.Int("pivotY");
            double a = res.Int("angleStart") + res.Int("angleRange") * Fraction(res);
            if (dc != null)
            {
                dc.PushTransform(new RotateTransform(a, o.X + px, o.Y + py));
                dc.DrawImage(img, new Rect(o.X, o.Y, img.PixelWidth, img.PixelHeight));
                dc.Pop();
            }
            // рамка — коло, яке описує стрілка
            double rad = Math.Max(Math.Sqrt(px * px + py * py), Math.Sqrt(Math.Pow(img.PixelWidth - px, 2) + Math.Pow(img.PixelHeight - py, 2)));
            return new Rect(o.X + px - rad, o.Y + py - rad, rad * 2, rad * 2);
        }

        /// <summary>Сектор кола: 0° — угорі, за годинниковою стрілкою</summary>
        static Geometry Pie(Point c, double r, double a0, double span)
        {
            if (Math.Abs(span) >= 360) return new EllipseGeometry(c, r, r);
            Point At(double deg) { double t = deg * Math.PI / 180; return new Point(c.X + r * Math.Sin(t), c.Y - r * Math.Cos(t)); }
            var fig = new PathFigure { StartPoint = c, IsClosed = true };
            fig.Segments.Add(new LineSegment(At(a0), false));
            fig.Segments.Add(new ArcSegment(At(a0 + span), new Size(r, r), 0, Math.Abs(span) > 180,
                                            span >= 0 ? SweepDirection.Clockwise : SweepDirection.Counterclockwise, false));
            var g = new PathGeometry();
            g.Figures.Add(fig);
            return g;
        }

        Rect? DrawArc(XNode res, Point o, DrawingContext dc)
        {
            Rect? u = null;
            var bg = Image(Pick(res.Str("bg"))?.Str("src"));
            if (bg != null) { var r0 = new Rect(o.X, o.Y, bg.PixelWidth, bg.PixelHeight); Put(dc, bg, r0); u = r0; }
            var fg = Frames(Pick(res.Str("ref"))).FirstOrDefault();
            if (fg == null) return u;
            var r = new Rect(o.X, o.Y, fg.PixelWidth, fg.PixelHeight);
            var c = new Point(o.X + res.Int("pivotX"), o.Y + res.Int("pivotY"));
            double rad = res.Int("barRadius") + res.Int("barWidth");
            double a0 = res.Int("angleStart"), span = res.Int("angleRange") * Fraction(res);
            if (dc != null && Math.Abs(span) > 0.01)
            {
                // круглі кінці: як на браслеті (endingStyle=round) — і на початку, і на кінці заповнення півколо
                // радіусом у пів товщини. Сектор + два кола; працює й для повного кільця, де в картинці кінців немає.
                Geometry clip = Pie(c, rad + 4, a0, span);
                bool round = res.Str("endingStyle") != "normal" && res.Int("barWidth") > 0;
                if (round)
                {
                    double br = res.Int("barRadius"), hw = res.Int("barWidth") / 2.0;
                    Point P(double deg) => new Point(c.X + br * Math.Sin(deg * Math.PI / 180), c.Y - br * Math.Cos(deg * Math.PI / 180));
                    // справжнє обʼєднання (напрям обходу сектора не «вирізає» перетин з колами)
                    clip = new CombinedGeometry(GeometryCombineMode.Union, clip,
                        new CombinedGeometry(GeometryCombineMode.Union, new EllipseGeometry(P(a0), hw, hw), new EllipseGeometry(P(a0 + span), hw, hw)));
                }
                dc.PushClip(clip);
                dc.DrawImage(fg, r);
                dc.Pop();
            }
            // крапка-індикатор на кінці заповнення
            var ind = Image(Pick(res.Str("indicatorImage"))?.Str("src"));
            if (ind != null)
            {
                double ir = res.Has("indicatorRadius") ? res.Int("indicatorRadius") : res.Int("barRadius");
                double a = (a0 + span) * Math.PI / 180;
                double ix = c.X + ir * Math.Sin(a), iy = c.Y - ir * Math.Cos(a);
                Put(dc, ind, new Rect(ix - ind.PixelWidth / 2.0, iy - ind.PixelHeight / 2.0, ind.PixelWidth, ind.PixelHeight));
            }
            return Union(u, r);
        }

        Rect? DrawLine(XNode res, Point o, DrawingContext dc)
        {
            Rect? u = null;
            var bg = Image(Pick(res.Str("bg"))?.Str("src"));
            if (bg != null) { var r0 = new Rect(o.X, o.Y, bg.PixelWidth, bg.PixelHeight); Put(dc, bg, r0); u = r0; }
            var fg = Frames(Pick(res.Str("ref"))).FirstOrDefault();
            if (fg == null) return u;
            var r = new Rect(o.X, o.Y, fg.PixelWidth, fg.PixelHeight);
            double f = Fraction(res);
            double sx = res.Int("startX"), ex = res.Int("endX"), sy = res.Int("startY"), ey = res.Int("endY");
            if (sx != ex && sy != ey)
            {
                // похила лінія: заповнення до точки start + (end − start)·f, межа — перпендикуляр до лінії
                double len = Math.Sqrt((ex - sx) * (ex - sx) + (ey - sy) * (ey - sy));
                double ux = (ex - sx) / len, uy = (ey - sy) / len, nx = -uy, ny = ux, big = 2000, t = len * f;
                if (dc != null && f > 0)
                {
                    Point Q(double a, double b) => new Point(o.X + sx + ux * a + nx * b, o.Y + sy + uy * a + ny * b);
                    var fig = new PathFigure { StartPoint = Q(-big, -big), IsClosed = true };
                    fig.Segments.Add(new LineSegment(Q(t, -big), false));
                    fig.Segments.Add(new LineSegment(Q(t, big), false));
                    fig.Segments.Add(new LineSegment(Q(-big, big), false));
                    var geo = new PathGeometry();
                    geo.Figures.Add(fig);
                    dc.PushClip(geo);
                    dc.DrawImage(fg, r);
                    dc.Pop();
                }
                return Union(u, r);
            }
            Rect clip;
            if (Math.Abs(ex - sx) >= Math.Abs(ey - sy))
            {
                double a = Math.Min(sx, sx + (ex - sx) * f), b = Math.Max(sx, sx + (ex - sx) * f);
                clip = new Rect(o.X + a, r.Y, b - a, r.Height);
            }
            else
            {
                double a = Math.Min(sy, sy + (ey - sy) * f), b = Math.Max(sy, sy + (ey - sy) * f);
                clip = new Rect(r.X, o.Y + a, r.Width, b - a);
            }
            if (dc != null && clip.Width > 0 && clip.Height > 0)
            {
                dc.PushClip(new RectangleGeometry(clip));
                dc.DrawImage(fg, r);
                dc.Pop();
            }
            return Union(u, r);
        }

        // MARK: Текст (браслет малює своїм шрифтом — на полотні наближено)

        static readonly Dictionary<string, FontWeight> Weights = new Dictionary<string, FontWeight>
        {
            ["thin"] = FontWeights.Thin, ["extralight"] = FontWeights.ExtraLight, ["light"] = FontWeights.Light,
            ["regular"] = FontWeights.Normal, ["normal"] = FontWeights.Normal, ["medium"] = FontWeights.Medium,
            ["semibold"] = FontWeights.SemiBold, ["demibold"] = FontWeights.SemiBold, ["bold"] = FontWeights.Bold, ["heavy"] = FontWeights.Heavy,
        };

        public static Typeface TextFont(string weight)
        {
            FontWeight w;
            if (!Weights.TryGetValue((weight ?? "regular").ToLowerInvariant(), out w)) w = FontWeights.Normal;
            return new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, w, FontStretches.Normal);
        }

        static FormattedText Fmt(string s, Typeface tf, double size, Brush b)
            => new FormattedText(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, tf, size, b, 1.0);

        Rect? DrawText(XNode res, Point o, DrawingContext dc)
        {
            var s = res.Str("string") ?? "";
            foreach (var c in res.All("Content"))
            {
                var src = c.Str("source");
                if (src == null) continue;
                int i = s.IndexOf("%s", StringComparison.Ordinal);
                if (i < 0) i = s.IndexOf("%d", StringComparison.Ordinal);
                if (i >= 0) s = s.Substring(0, i) + SampleData.Value(src, Live, p.Meta.Demo) + s.Substring(i + 2);
            }
            bool arc = (res.Str("style") ?? "normal") != "normal";
            double h0 = Math.Max(res.Int("h"), 1);
            double size = res.Has("fontSize") ? Math.Max(res.Int("fontSize"), 1) : Math.Max(10, h0 * 0.8);
            var tf = TextFont(res.Str("fontWeight"));
            var brush = Imaging.Brush(res.Str("color") ?? "#FFFFFF", Math.Max(0, Math.Min(100, res.Int("opacity", 100))) / 100.0);
            if (arc) return DrawArcText(s, res, o, dc, tf, size, brush);
            double w = Math.Max(res.Int("w"), 1), h = h0;
            var r = new Rect(o.X, o.Y, w, h);
            if (dc == null || s.Length == 0) return r;
            var ft = Fmt(s, tf, size, brush);
            bool wrap = res.Str("longMode") == "wrap";
            var align = res.Str("align");
            if (wrap)
            {
                ft.MaxTextWidth = w;
                ft.TextAlignment = align == "center" ? TextAlignment.Center : align == "right" ? TextAlignment.Right : TextAlignment.Left;
                int ls = res.Int("lineSpace");
                if (ls != 0) ft.LineHeight = Math.Max(1, size * 1.3 + ls);
            }
            double tw = wrap ? w : ft.WidthIncludingTrailingWhitespace, th = ft.Height;
            double dx = 0;
            if (!wrap) dx = align == "center" ? (w - tw) / 2 : align == "right" ? w - tw : 0;
            double rot = res.Int("rotation");
            if (rot != 0) dc.PushTransform(new RotateTransform(rot, r.X + r.Width / 2, r.Y + r.Height / 2));
            dc.PushClip(new RectangleGeometry(r));
            dc.DrawText(ft, new Point(r.X + dx, r.Y + Math.Max(0, (h - th) / 2)));
            dc.Pop();
            if (rot != 0) dc.Pop();
            return r;
        }

        /// <summary>Текст дугою: коло радіуса radius, рамка — квадрат 2r від точки макета; 0° — угорі, за годинниковою</summary>
        Rect? DrawArcText(string s, XNode res, Point o, DrawingContext dc, Typeface tf, double size, Brush brush)
        {
            double r = Math.Max(res.Int("radius"), 1);
            var box = new Rect(o.X, o.Y, r * 2, r * 2);
            if (dc == null || s.Length == 0) return box;
            double cx = box.X + r, cy = box.Y + r, kern = res.Int("letterSpace");
            var glyphs = s.Select(ch => Fmt(ch.ToString(), tf, size, brush)).ToList();
            var widths = glyphs.Select(g => g.WidthIncludingTrailingWhitespace + kern).ToList();
            double total = widths.Sum();
            double lineH = glyphs.Count > 0 ? glyphs[0].Height : size;
            double ascent = glyphs.Count > 0 ? glyphs[0].Baseline : size * 0.8;
            var va = res.Str("verticalAlign") ?? "top";
            double mid = va == "center" ? r - lineH / 2 : va == "bottom" ? r - lineH : r;
            double rr = Math.Max(1, va == "top" ? r - ascent : mid);
            double a0 = res.Int("startAngle"), span = res.Int("span");
            double textAngle = total / rr * 180 / Math.PI;
            var al = res.Str("align") ?? "center";
            double a = al == "left" ? a0 : al == "right" ? a0 + span - textAngle : a0 + (span - textAngle) / 2;
            for (int i = 0; i < glyphs.Count; i++)
            {
                double wch = widths[i];
                double half = wch / 2 / rr * 180 / Math.PI;
                double ang = a + half, t = ang * Math.PI / 180;
                double px = cx + rr * Math.Sin(t), py = cy - rr * Math.Cos(t);
                dc.PushTransform(new RotateTransform(ang, px, py));
                dc.DrawText(glyphs[i], new Point(px - (wch - kern) / 2, py - ascent));
                dc.Pop();
                a += wch / rr * 180 / Math.PI;
            }
            return box;
        }
    }
}
