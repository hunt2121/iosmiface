// SPDX-License-Identifier: MIT
// Віджети (кілька шарів одним блоком: розташування, вирівнювання, проміжок, дія при натисканні)
// і слоти (місце на циферблаті, де віджет вибирають на браслеті). Формат — як в офіційних циферблатах:
// <Widget widgetName jumpApp w h flex_direction justify_content align_items gap> з <Item ref x y>,
// <Slot type="widget"> з <Item ref="@Widget">; у віджетах слота — preview (мініатюра) і editbox (рамка вибору).

using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class WidgetSlots
    {
        // MARK: Який віджет слота показувати в редакторі (лише в пам'яті, на браслет не пишеться)

        static readonly ConditionalWeakTable<FaceProject, Dictionary<string, int>> shown = new ConditionalWeakTable<FaceProject, Dictionary<string, int>>();
        public static int Shown(FaceProject p, XNode slot) => shown.GetOrCreateValue(p).TryGetValue(slot.Str("name") ?? "", out var i) ? i : 0;
        public static void Show(FaceProject p, XNode slot, int i) => shown.GetOrCreateValue(p)[slot.Str("name") ?? ""] = i;

        // MARK: Віджет

        /// <summary>Віджет, який користувач бачить як віджет (не службова обгортка «натиснув — відкрився застосунок»)</summary>
        public static bool IsUserWidget(FaceProject p, XNode r) => r != null && r.Tag == "Widget" && ElementFactory.TapInner(p, r) == null;

        /// <summary>row / column / free</summary>
        public static string Arrange(XNode w)
        {
            var d = w.Str("flex_direction");
            return d == "row" || d == "column" ? d : "free";
        }

        /// <summary>start / center / end — уздовж ширини віджета</summary>
        public static string Align(XNode w)
        {
            var key = Arrange(w) == "column" ? "align_items" : "justify_content";
            var v = w.Str(key) ?? "flex-start";
            return v == "center" ? "center" : v == "flex-end" ? "end" : "start";
        }

        public static int Gap(XNode w) => w.Int("gap");

        static string Flex(string a) => a == "center" ? "center" : a == "end" ? "flex-end" : "flex-start";

        public static void SetLayout(FaceProject p, XNode w, string arrange, string align, int gap, XNode layout = null)
        {
            if (arrange == "free")
            {
                // вільно: кожен елемент лишається там, де стояв
                var offs = new FaceRenderer(p).WidgetOffsets(w);
                var items = w.All("Item");
                for (int i = 0; i < items.Count; i++) items[i].Set("x", (int)Math.Round(offs[i].X)).Set("y", (int)Math.Round(offs[i].Y));
                foreach (var k in new[] { "flex_direction", "justify_content", "align_content", "align_items", "gap" }) w.Remove(k);
            }
            else
            {
                w.Set("flex_direction", arrange);
                // уздовж ряду — justify_content, поперек — align_items; «Вирівнювання» — завжди по горизонталі
                if (arrange == "row") w.Set("justify_content", Flex(align)).Set("align_items", "center");
                else w.Set("align_items", Flex(align)).Set("justify_content", "center");
                w.Set("align_content", "center").Set("gap", Math.Max(0, gap));
                foreach (var it in w.All("Item")) it.Set("x", 0).Set("y", 0);
            }
            Fit(p, w, layout);
        }

        /// <summary>Розмір віджета: щонайменше вміст; у слоті — не менший за інші віджети слота</summary>
        /// <summary>Запас окантовки навколо видимого вмісту, px</summary>
        public const int Pad = 7;

        public static bool IsManual(FaceProject p, XNode w) => p.Meta.ManualSize.Contains(w.Str("name") ?? "");

        /// <summary>Розмір віджета задано вручну — картинки з прозорими краями не впливають на область</summary>
        public static void SetSize(FaceProject p, XNode w, int width, int height)
        {
            p.Meta.ManualSize.Add(w.Str("name") ?? "");
            w.Set("w", Math.Min(Math.Max(width, 8), 2000)).Set("h", Math.Min(Math.Max(height, 8), 2000));
        }

        /// <summary>Повернути розмір за вмістом</summary>
        public static void SetAuto(FaceProject p, XNode w, XNode layout = null)
        {
            p.Meta.ManualSize.Remove(w.Str("name") ?? "");
            Fit(p, w, layout, true);
        }

        /// <summary>За вмістом для слота: один розмір усім його віджетам (за видимими пікселями), слот зсувається в лівий верхній кут вмісту</summary>
        public static void SetAutoSlot(FaceProject p, List<XNode> ws, XNode layout)
        {
            var r = new FaceRenderer(p);
            foreach (var w in ws) { p.Meta.ManualSize.Remove(w.Str("name") ?? ""); if (Arrange(w) == "free") TrimGauges(p, w); }
            Rect union = Rect.Empty;
            foreach (var w in ws)
            {
                Rect b = Rect.Empty;
                if (Arrange(w) == "free")
                {
                    foreach (var it in w.All("Item"))
                    {
                        var c = p.ResourceRef(it.Str("ref"));
                        var m = c == null ? null : r.VisibleBounds(c);
                        if (m == null) continue;
                        var q = m.Value; q.Offset(it.Int("x"), it.Int("y"));
                        b = b.IsEmpty ? q : Rect.Union(b, q);
                    }
                }
                else
                {
                    int ow = w.Int("w"), oh = w.Int("h"); w.Remove("w"); w.Remove("h");
                    var m = r.VisibleBounds(w);
                    w.Set("w", ow).Set("h", oh);
                    if (m.HasValue) b = m.Value;
                }
                if (!b.IsEmpty) union = union.IsEmpty ? b : Rect.Union(union, b);
            }
            if (union.IsEmpty) return;
            int dx = (int)Math.Floor(union.Left) - Pad, dy = (int)Math.Floor(union.Top) - Pad;
            int cw = Math.Max(8, (int)Math.Ceiling(union.Right) + Pad - dx), ch = Math.Max(8, (int)Math.Ceiling(union.Bottom) + Pad - dy);
            foreach (var w in ws)
            {
                if (Arrange(w) == "free") foreach (var it in w.All("Item")) it.Set("x", it.Int("x") - dx).Set("y", it.Int("y") - dy);
                w.Set("w", cw).Set("h", ch);
            }
            layout.Set("x", layout.Int("x") + dx).Set("y", layout.Int("y") + dy);
        }

        public static void Fit(FaceProject p, XNode w, XNode layout = null, bool shrink = false)
        {
            if (IsManual(p, w)) return;
            if (Arrange(w) == "free" && w.All("Item").Count > 0) { WrapFree(p, w, layout, shrink); return; }
            var r = new FaceRenderer(p);
            bool hadW = w.Has("w"), hadH = w.Has("h");
            int oldW = w.Int("w"), oldH = w.Int("h");
            w.Remove("w"); w.Remove("h");
            var box = r.VisibleBounds(w) ?? new Rect(0, 0, 40, 30);
            int cw = Math.Max(8, (int)Math.Ceiling(box.Right) + 2 * Pad), ch = Math.Max(8, (int)Math.Ceiling(box.Bottom) + 2 * Pad);
            bool keep = !shrink && SlotsOf(p, w).Count > 0;
            int fw = Math.Max(cw, hadW && keep ? oldW : 0), fh = Math.Max(ch, hadH && keep ? oldH : 0);
            w.Set("w", fw).Set("h", fh);
        }

        /// <summary>Вільне розташування: область віджета щільно обгортає його елементи. Якщо віджет стоїть окремим шаром,
        /// шар зсувається в лівий верхній кут елементів; у слоті місце слота лишається, елементи зсуваються всередині.</summary>
        /// <summary>Дуга у віджеті: картинки (передній план, фон, усі кольорові варіанти) фізично обрізаються по видимих пікселях,
        /// а позиція елемента й центр дуги (pivot) перераховуються — на екрані дуга лишається на тому самому місці.
        /// Так елемент не виступає за область віджета, і зверху не лишається порожнього відступу.</summary>
        public static void TrimGauges(FaceProject p, XNode w)
        {
            foreach (var it in w.All("Item"))
            {
                var res = p.ResourceRef(it.Str("ref"));
                if (res == null || res.Tag != "DataItemArcProgressBar") continue;
                var fgRef = res.Str("ref"); var bgRef = res.Str("bg");
                if (fgRef == null || !fgRef.StartsWith("@")) continue;
                Func<string, List<XNode>> images = r => string.IsNullOrEmpty(r) || !r.StartsWith("@")
                    ? new List<XNode>()
                    : p.Resources.Elements.Where(e => e.Tag == "Image" && "@" + e.Str("name") == r).ToList();
                var fg = images(fgRef); var bg = images(bgRef);
                // картинки, якими користується ще хтось інший, не чіпаємо
                bool shared = p.Resources.Elements.Any(e => e != res && (e.Str("ref") == fgRef || e.Str("bg") == fgRef || (bgRef != null && (e.Str("ref") == bgRef || e.Str("bg") == bgRef))));
                if (fg.Count == 0 || shared) continue;
                Func<XNode, RgbaImage> decode = n =>
                {
                    var src = n?.Str("src"); var d = src == null ? null : p.File(src);
                    return d == null ? null : Png.Decode(d);
                };
                int x0 = int.MaxValue, y0 = int.MaxValue, x1 = -1, y1 = -1;
                foreach (var n in new[] { fg[0], bg.Count > 0 ? bg[0] : null })
                {
                    var img = decode(n);
                    if (img == null) continue;
                    for (int y = 0; y < img.H; y++)
                        for (int x = 0; x < img.W; x++)
                            if (img.Px[(y * img.W + x) * 4 + 3] > 12) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
                }
                var baseImg = decode(fg[0]);
                if (x1 < 0 || baseImg == null) continue;
                int bw = x1 - x0 + 1, bh = y1 - y0 + 1;
                if (x0 == 0 && y0 == 0 && bw == baseImg.W && bh == baseImg.H) continue;
                foreach (var n in fg.Concat(bg))
                {
                    var img = decode(n);
                    if (img == null) continue;
                    int cx0 = Math.Max(x0, 0), cy0 = Math.Max(y0, 0), cx1 = Math.Min(x1, img.W - 1), cy1 = Math.Min(y1, img.H - 1);
                    int cw = cx1 - cx0 + 1, ch = cy1 - cy0 + 1;
                    if (cw <= 0 || ch <= 0) continue;
                    var px = new byte[cw * ch * 4];
                    for (int y = 0; y < ch; y++) Buffer.BlockCopy(img.Px, ((cy0 + y) * img.W + cx0) * 4, px, y * cw * 4, cw * 4);
                    p.SetFile(n.Str("src"), new RgbaImage(cw, ch, px).Png());
                }
                res.Set("pivotX", res.Int("pivotX") - x0); res.Set("pivotY", res.Int("pivotY") - y0);
                it.Set("x", it.Int("x") + x0); it.Set("y", it.Int("y") + y0);
            }
        }

        public static void WrapFree(FaceProject p, XNode w, XNode layout, bool shrink = false)
        {
            TrimGauges(p, w);
            var r = new FaceRenderer(p);
            Rect box = Rect.Empty;
            foreach (var it in w.All("Item"))
            {
                var c = p.ResourceRef(it.Str("ref"));
                var m = c == null ? null : r.VisibleBounds(c);
                if (m == null) continue;
                var q = m.Value; q.Offset(it.Int("x"), it.Int("y"));
                box = box.IsEmpty ? q : Rect.Union(box, q);
            }
            if (box.IsEmpty) return;
            bool inSlot = !shrink && layout == null && SlotsOf(p, w).Count > 0;
            int dx = (int)Math.Floor(box.Left) - Pad, dy = (int)Math.Floor(box.Top) - Pad;
            if (layout == null) { dx = Math.Min(0, dx); dy = Math.Min(0, dy); }
            foreach (var it in w.All("Item")) it.Set("x", it.Int("x") - dx).Set("y", it.Int("y") - dy);
            if (layout != null) layout.Set("x", layout.Int("x") + dx).Set("y", layout.Int("y") + dy);
            int cw = Math.Max(8, (int)Math.Ceiling(box.Right) + Pad - dx), ch = Math.Max(8, (int)Math.Ceiling(box.Bottom) + Pad - dy);
            w.Set("w", Math.Max(cw, inSlot ? w.Int("w") : 0)).Set("h", Math.Max(ch, inSlot ? w.Int("h") : 0));
        }

        /// <summary>Порожній віджет-ресурс</summary>
        public static XNode NewWidget(FaceProject p, string title, int w = 80, int h = 30)
        {
            var x = new XNode("Widget");
            x.Set("name", p.UniqueName("widget")).Set("widgetName", title).Set("groupType", "general").Set("w", w).Set("h", h)
             .Set("flex_direction", "row").Set("justify_content", "center").Set("align_content", "center").Set("align_items", "center").Set("gap", 4);
            p.Resources.Kids.Add(x);
            return x;
        }

        /// <summary>«Віджет» з галереї: порожній віджет по центру</summary>
        public static void AddWidget(FaceProject p, int theme, int cx, int cy, string title)
        {
            var w = NewWidget(p, title);
            ElementFactory.AddLayout(p, w.Str("name"), theme, cx - 40, cy - 15);
        }

        /// <summary>Шар екрана переходить у віджет (на тому ж місці, якщо розташування «вільно»)</summary>
        public static void AddToWidget(FaceProject p, XNode w, Point origin, XNode layout, int theme, XNode own = null)
        {
            var th = p.Theme(theme);
            if (th == null || layout == null) return;
            var r = layout.Str("ref");
            if (r == null) return;
            // перший шар порожнього віджета: розташування «вільно» — елемент лишається на місці, область стає навколо нього
            if (w.All("Item").Count == 0 && own != null)
                foreach (var k in new[] { "flex_direction", "justify_content", "align_content", "align_items", "gap" }) w.Remove(k);
            var it = w.Add("Item").Set("ref", r);
            if (Arrange(w) == "free") it.Set("x", (int)Math.Round(layout.Int("x") - origin.X)).Set("y", (int)Math.Round(layout.Int("y") - origin.Y));
            else it.Set("x", 0).Set("y", 0);
            th.Kids.Remove(layout);
            Fit(p, w, own);
        }

        /// <summary>Елемент віджета знову стає окремим шаром — на тому самому місці</summary>
        public static void TakeOut(FaceProject p, XNode w, int index, Point origin, int theme, XNode own = null)
        {
            var items = w.All("Item");
            if (index < 0 || index >= items.Count) return;
            var offs = new FaceRenderer(p).WidgetOffsets(w);
            var r = items[index].Str("ref");
            w.Kids.Remove(items[index]);
            if (r != null) ElementFactory.AddLayout(p, r.Substring(1), theme, (int)Math.Round(origin.X + offs[index].X), (int)Math.Round(origin.Y + offs[index].Y));
            Fit(p, w, own);
        }

        /// <summary>Розгрупувати: усі елементи — окремими шарами на своїх місцях, віджет прибирається</summary>
        public static void Ungroup(FaceProject p, XNode layout, int theme)
        {
            var w = p.ResourceRef(layout.Str("ref"));
            var th = p.Theme(theme);
            if (w == null || th == null) return;
            var offs = new FaceRenderer(p).WidgetOffsets(w);
            var items = w.All("Item");
            int at = th.Kids.IndexOf(layout);
            for (int i = 0; i < items.Count; i++)
            {
                var r = items[i].Str("ref");
                if (r == null) continue;
                var l = new XNode("Layout");
                l.Set("ref", r).Set("x", (int)Math.Round(layout.Int("x") + offs[i].X)).Set("y", (int)Math.Round(layout.Int("y") + offs[i].Y));
                th.Kids.Insert(++at, l);
            }
            w.Kids.RemoveAll(k => k.Tag == "Item");
            ElementFactory.Delete(p, layout, theme);
        }

        public static void MoveItem(XNode w, int index, int dir)
        {
            var items = w.All("Item");
            int j = index + dir;
            if (index < 0 || j < 0 || j >= items.Count) return;
            int a = w.Kids.IndexOf(items[index]), b = w.Kids.IndexOf(items[j]);
            var t = w.Kids[a]; w.Kids[a] = w.Kids[b]; w.Kids[b] = t;
        }

        public static void SetTap(XNode w, string app)
        {
            if (string.IsNullOrEmpty(app)) w.Remove("jumpApp"); else w.Set("jumpApp", app);
        }

        // MARK: Слот

        public static List<XNode> SlotsOf(FaceProject p, XNode w)
        {
            var key = "@" + (w.Str("name") ?? "");
            return p.Resources.Elements.Where(e => e.Tag == "Slot" && e.All("Item").Any(i => i.Str("ref") == key)).ToList();
        }

        public static List<XNode> Widgets(FaceProject p, XNode slot)
            => slot.All("Item").Select(i => p.ResourceRef(i.Str("ref"))).Where(x => x != null).ToList();

        /// <summary>«Слот» з галереї: місце по центру з одним порожнім віджетом</summary>
        public static void AddSlot(FaceProject p, int theme, int cx, int cy, string firstTitle)
        {
            var w = NewWidget(p, firstTitle, 112, 74);
            w.Set("flex_direction", "column");
            var s = new XNode("Slot");
            s.Set("name", p.UniqueName("slot")).Set("type", "widget");
            s.Add("Item").Set("ref", "@" + w.Str("name"));
            p.Resources.Kids.Add(s);
            ElementFactory.AddLayout(p, s.Str("name"), theme, cx - 56, cy - 37);
        }

        /// <summary>Розмір віджетів слота (за першим, у якого він заданий)</summary>
        static Size SlotSize(FaceProject p, XNode slot)
        {
            var f = Widgets(p, slot).FirstOrDefault(x => x.Has("w") && x.Has("h"));
            return f == null ? new Size(112, 74) : new Size(f.Int("w"), f.Int("h"));
        }

        public static XNode SlotNewWidget(FaceProject p, XNode slot, string title)
        {
            var sz = SlotSize(p, slot);
            var w = NewWidget(p, title, (int)sz.Width, (int)sz.Height);
            w.Set("flex_direction", "column");
            slot.Add("Item").Set("ref", "@" + w.Str("name"));
            return w;
        }

        /// <summary>Віджети циферблата, які можна додати в слот (ще не в ньому)</summary>
        public static List<XNode> Candidates(FaceProject p, XNode slot)
        {
            var have = new HashSet<XNode>(Widgets(p, slot));
            var nested = new HashSet<string>(p.Resources.Elements.Where(e => e.Tag == "Widget").SelectMany(e => e.All("Item")).Select(i => i.Str("ref") ?? ""));
            return p.Resources.Elements.Where(e => IsUserWidget(p, e) && !have.Contains(e) && !nested.Contains("@" + (e.Str("name") ?? ""))).ToList();
        }

        /// <summary>Готовий віджет у слот; якщо він стояв окремим шаром — шар прибирається (тепер він у слоті)</summary>
        public static void SlotAddExisting(FaceProject p, XNode slot, XNode w)
        {
            var key = "@" + (w.Str("name") ?? "");
            slot.Add("Item").Set("ref", key);
            var sk = "@" + (slot.Str("name") ?? "");
            for (int t = 0; t < p.Themes.Count; t++)
                foreach (var l in p.Layouts(t).Where(l => l.Str("ref") == key).ToList())
                {
                    // слот стає на місце віджета — елементи лишаються там, де були
                    var sl = p.Layouts(t).FirstOrDefault(x => x.Str("ref") == sk);
                    if (sl != null) sl.Set("x", l.Int("x")).Set("y", l.Int("y"));
                    p.Theme(t).Kids.Remove(l);
                }
        }

        public static void SlotRemove(FaceProject p, XNode slot, int index)
        {
            var items = slot.All("Item");
            if (items.Count <= 1 || index < 0 || index >= items.Count) return; // слот без віджетів не має сенсу
            var r = items[index].Str("ref");
            slot.Kids.Remove(items[index]);
            if (r != null) ElementFactory.Collect(p, r);
        }

        public static void SlotMove(XNode slot, int index, int dir) => MoveItem(slot, index, dir);

        // MARK: Мініатюри й рамка для вибору на браслеті

        /// <summary>Радіус м'яких кутів рамки вибору (там, де її обрізає екран), px циферблата</summary>
        public const double CornerRadius = 16;

        /// <summary>Рамка з м'якими кутами = (область ∩ екран) з відкриттям радіусом r: обидві форми стискаються на r
        /// і перетинаються, потім результат розширюється на r (Dilate). Повертає стиснуту форму й використаний радіус.</summary>
        public static Geometry SoftCore(Rect box, double boxRadius, Tuple<Rect, double> screen, double radius, out double used)
        {
            double r = Math.Max(0, Math.Min(radius, Math.Min(box.Width, box.Height) / 2 - 1));
            used = r;
            Func<Rect, double, Geometry> eroded = (rect, rad) =>
            {
                var q = new Rect(rect.X + r, rect.Y + r, Math.Max(rect.Width - 2 * r, 0.1), Math.Max(rect.Height - 2 * r, 0.1));
                double k = Math.Max(0, Math.Min(rad - r, Math.Min(q.Width, q.Height) / 2));
                return new RectangleGeometry(q, k, k);
            };
            Geometry core = eroded(box, boxRadius);
            if (screen != null) core = Geometry.Combine(core, eroded(screen.Item1, screen.Item2), GeometryCombineMode.Intersect, null);
            return core;
        }

        /// <summary>Розширення форми на t (об'єднання з товстою обводкою контуру)</summary>
        public static Geometry Dilate(Geometry path, double t)
        {
            if (t <= 0) return path;
            var pen = new Pen(Brushes.Black, 2 * t) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            return Geometry.Combine(path, path.GetWidenedPathGeometry(pen), GeometryCombineMode.Union, null);
        }

        /// <summary>Відступ рамки вибору від країв екрана, px (0 — лише не виходить за край)</summary>
        const double ScreenMargin = 0;

        const double PreviewScale = 0.634; // як в офіційних: віджет 112×74 → мініатюра 71×47

        /// <summary>Для кожного віджета слота — preview (віджет зменшений на чорному) і editbox (помаранчева рамка)</summary>
        public static void RefreshPreviews(FaceProject p)
        {
            var r = new FaceRenderer(p);
            foreach (var slot in p.Resources.Elements.Where(e => e.Tag == "Slot").ToList())
                foreach (var w in Widgets(p, slot))
                {
                    if (!w.Has("w") || !w.Has("h")) continue;
                    int W = w.Int("w"), H = w.Int("h");
                    int pw = Math.Max(8, (int)Math.Round(W * PreviewScale)), ph = Math.Max(8, (int)Math.Round(H * PreviewScale));
                    var img = Imaging.Render(pw, ph, dc =>
                    {
                        dc.DrawRectangle(Brushes.Black, null, new Rect(0, 0, pw, ph));
                        dc.PushTransform(new ScaleTransform(PreviewScale, PreviewScale));
                        r.Draw(w, new Point(0, 0), dc, 0);
                        dc.Pop();
                    });
                    SetImageRef(p, w, "preview", img, "wpreview_" + (w.Str("name") ?? "w"));
                    // рамка вибору повторює скруглення екрана внизу, не виходить за його край, а кути м'які
                    var lay = p.Layouts(0).FirstOrDefault(l => l.Str("ref") == "@" + (slot.Str("name") ?? ""));
                    double ox = lay?.Int("x") ?? 0, oy = lay?.Int("y") ?? 0;
                    var box = Imaging.Render(pw, ph, dc =>
                    {
                        var boxRect = new Rect(1.5, 1.5, pw - 3, ph - 3);
                        Tuple<Rect, double> screen = null;
                        if (lay != null)
                        {
                            var dev = p.Meta.Device;
                            double m = ScreenMargin + 1.5 / PreviewScale;
                            screen = Tuple.Create(new Rect((m - ox) * PreviewScale, (m - oy) * PreviewScale, (dev.Width - 2 * m) * PreviewScale, (dev.Height - 2 * m) * PreviewScale),
                                                  (dev.Corner - m) * PreviewScale);
                        }
                        double rr;
                        var core = SoftCore(boxRect, Math.Min(boxRect.Width, boxRect.Height) / 2, screen, CornerRadius * PreviewScale, out rr);
                        var ring = Geometry.Combine(Dilate(core, rr + 1.5), Dilate(core, Math.Max(rr - 1.5, 0)), GeometryCombineMode.Exclude, null);
                        dc.DrawGeometry(Imaging.Brush("#FFFFFF", 0.5), null, ring);
                    });
                    SetImageRef(p, w, "editbox", box, "weditbox_" + pw + "x" + ph + (lay != null ? "_" + (int)ox + "_" + (int)oy : ""));
                }
        }

        static void SetImageRef(FaceProject p, XNode w, string attr, RgbaImage img, string name)
        {
            var cur = p.ResourceRef(w.Str(attr));
            // спільна рамка одного розміру — один ресурс на всі віджети
            var same = p.Resources.Elements.FirstOrDefault(e => e.Tag == "Image" && e.Str("name") == name);
            if (attr == "editbox" && same != null) { w.Set(attr, "@" + name); return; }
            if (cur != null && cur.Tag == "Image" && (cur.Str("name") ?? "").StartsWith(attr == "preview" ? "wpreview_" : "weditbox_"))
            {
                ElementFactory.ReplaceImage(p, cur, img);
                return;
            }
            var n = ElementFactory.AddImageResource(p, img, name);
            w.Set(attr, "@" + n);
        }
    }
}
